import Foundation

/// Центральный координатор импорта:
/// - Безопасное сохранение через временные файлы (.staging/*.tmp) и атомарный move
/// - Персистентное хранение в SQLite (CatalogDatabase)
/// - Контроль свободного места на диске (DiskSpaceGuard)
/// - Сверка диска с каталогом и устранение последствий аварий (DiskCatalogReconciler)
/// - Предотвращение коллизий имен и защита активных заданий
public actor TransferCoordinator: CameraTransportDelegate {
    public static let shared = TransferCoordinator()
    
    // Ссылки на подсистемы
    private let storageManager: StorageManager
    private let database: CatalogDatabase
    private let reconciler: DiskCatalogReconciler
    private let diskGuard: DiskSpaceGuard
    private var transports: [CameraTransportType: CameraTransport] = [:]
    
    // Состояние сессий
    public private(set) var activeSession: CaptureSession
    public private(set) var allSessions: [CaptureSession] = []
    
    // Состояние источников
    public private(set) var connectedSources: [CameraSource] = []
    
    // Состояние заданий и ассетов
    public private(set) var jobs: [UUID: TransferJob] = [:]
    public private(set) var assets: [MediaAsset] = []
    public private(set) var captureGroups: [CaptureGroup] = []
    public private(set) var exportJobs: [UUID: ExportJob] = [:]
    
    // Автоматическое фоновое копирование на внешний накопитель (Live Mirror)
    public var isAutoExportEnabled: Bool = false
    public var autoExportDestinationURL: URL?
    public var autoExportBookmarkData: Data?
    public var autoExportFormat: ExportFormatSelection = .both
    public var onAutoExportFailed: (@Sendable (String) -> Void)?
    
    // Callbacks для подписчиков (UI / ViewModel)
    public var onJobUpdated: (@Sendable (TransferJob) -> Void)?
    public var onAssetIngested: (@Sendable (MediaAsset, CaptureGroup) -> Void)?
    public var onCaptureGroupUpdated: (@Sendable (CaptureGroup) -> Void)?
    public var onSourcesChanged: (@Sendable ([CameraSource]) -> Void)?
    public var onSessionChanged: (@Sendable (CaptureSession) -> Void)?
    public var onSpeedUpdated: (@Sendable (Double) -> Void)?
    
    public init(
        storageManager: StorageManager = .shared,
        database: CatalogDatabase = .shared,
        reconciler: DiskCatalogReconciler = DiskCatalogReconciler(),
        diskGuard: DiskSpaceGuard = DiskSpaceGuard()
    ) {
        self.storageManager = storageManager
        self.database = database
        self.reconciler = reconciler
        self.diskGuard = diskGuard
        
        let initialName = CaptureSession.defaultSessionName()
        let initialFolder = storageManager.baseStorageURL.appendingPathComponent(initialName, isDirectory: true)
        let initialSession = CaptureSession(name: initialName, folderURL: initialFolder)
        self.activeSession = initialSession
        self.allSessions = [initialSession]
    }
    
    // MARK: - Инициализация, восстановление и сверка с диском (Этапы 2 и 3)
    
    /// Восстановление состояния каталога, сессий и устранение остаточных staging-файлов
    public func bootstrap() async {
        // 1. Очистка остаточных временных staging-файлов после возможных аварий
        let sessionsRootURL = await storageManager.currentSessionURL.deletingLastPathComponent()
        _ = reconciler.cleanAllStagingFiles(in: sessionsRootURL)
        
        // 2. Восстановление незавершенных заданий в базе данных
        _ = await database.markIncompleteJobsInterrupted(reason: "Сессия прервана перезапуском приложения")
        
        // 3. Загрузка сессий из SQLite
        var dbSessions = await database.getAllSessions()
        
        // 4. Импорт существующих папок съемок из Documents/Sessions, если их нет в БД
        let knownPaths = Set(dbSessions.map { $0.folderURL.standardizedFileURL.path })
        let discoveredFolders = reconciler.discoverExistingSessionFolders(in: sessionsRootURL, knownSessionFolderPaths: knownPaths)
        for disc in discoveredFolders {
            await database.upsertSession(disc)
            await storageManager.registerSession(disc)
            dbSessions.append(disc)
            
            // Сканируем и регистрируем существующие файлы в папке
            let discoveredAssets = reconciler.discoverAssetsInSessionFolder(session: disc, knownFilePaths: [])
            for asset in discoveredAssets {
                await database.upsertAsset(asset)
            }
        }
        
        // 5. Определение активной сессии
        if let savedActive = await database.getActiveSession() {
            self.activeSession = savedActive
            await storageManager.registerSession(savedActive, setActive: true)
        } else if let first = dbSessions.first {
            self.activeSession = first
            await database.setActiveSession(id: first.id)
            await storageManager.registerSession(first, setActive: true)
        } else {
            // Создаем новую начальную сессию
            let initial = (try? await storageManager.createNewSession()) ?? activeSession
            await database.upsertSession(initial, isActive: true)
            self.activeSession = initial
            dbSessions = [initial]
        }
        
        // Синхронизируем все сессии из базы в StorageManager
        let allDBSessions = await database.getAllSessions()
        self.allSessions = allDBSessions
        await storageManager.syncSessions(from: allDBSessions, activeSessionID: activeSession.id)
        
        // 6. Загрузка ассетов текущей активной сессии
        let sessionAssets = await database.getAssets(for: activeSession.id)
        
        // 7. Сверка с диском: проверка отсутствующих файлов (удаленных через «Файлы»)
        let missingIDs = reconciler.reconcileAssetsWithDisk(knownAssets: sessionAssets)
        for missingID in missingIDs {
            await database.markAssetMissing(id: missingID, isMissing: true)
        }
        
        // 7a. Сверка файлов на диске с каталогом: поиск недорегистрированных файлов
        // (на случай аварийного завершения процесса между сохранением файла на диск и записью в SQLite)
        let knownAssetPaths = Set(sessionAssets.map { $0.fileURL.standardizedFileURL.path })
        let untrackedAssets = reconciler.discoverAssetsInSessionFolder(session: activeSession, knownFilePaths: knownAssetPaths)
        for untracked in untrackedAssets {
            await database.upsertAsset(untracked)
        }
        
        self.assets = await database.getAssets(for: activeSession.id)
        rebuildCaptureGroups()
        
        // 8. Загрузка заданий активной сессии
        let sessionJobs = await database.getJobs(for: activeSession.id)
        self.jobs = Dictionary(uniqueKeysWithValues: sessionJobs.map { ($0.id, $0) })
        
        onSessionChanged?(self.activeSession)
        for transport in transports.values {
            await transport.didChangeActiveSession(self.activeSession)
        }
    }
    
    /// Восстанавливает историю, затем выбирает сессию для нового запуска приложения.
    public func bootstrapForLaunch(resumeLastSession: Bool) async throws {
        await bootstrap()
        if !resumeLastSession && (!assets.isEmpty || activeSession.isClosed) {
            _ = try await startNewSession()
        }
    }

    private func rebuildCaptureGroups() {
        var groupList: [CaptureGroup] = []
        for asset in assets {
            if let index = groupList.firstIndex(where: { $0.canAccept(asset: asset) }) {
                groupList[index].addAsset(asset)
            } else {
                groupList.append(CaptureGroup(asset: asset))
            }
        }
        self.captureGroups = groupList.sorted(by: { ($0.captureDate ?? Date.distantPast) > ($1.captureDate ?? Date.distantPast) })
    }
    
    // MARK: - Управление транспортами
    
    public func registerTransport(_ transport: CameraTransport) {
        self.transports[transport.transportType] = transport
        transport.delegate = self
        let currentSession = self.activeSession
        Task {
            await transport.didChangeActiveSession(currentSession)
        }
    }
    
    // MARK: - Управление сессиями (История, Переименование, Завершение, Удаление)
    
    @discardableResult
    public func startNewSession(named sessionName: String? = nil) async throws -> CaptureSession {
        // Синхронизируем известные сессии в storageManager перед разрешением имени
        let currentDBSessions = await database.getAllSessions()
        await storageManager.syncSessions(from: currentDBSessions, activeSessionID: activeSession.id)
        
        let newSession = try await storageManager.createNewSession(named: sessionName)
        await database.upsertSession(newSession, isActive: true)
        await database.setActiveSession(id: newSession.id)
        
        self.activeSession = newSession
        self.allSessions = await database.getAllSessions()
        self.assets.removeAll()
        self.captureGroups.removeAll()
        // Сохраняем незавершенные (pending, inProgress, verifying) задания других сессий,
        // чтобы ожидающие USB/FTP переносы не теряли назначение, а сессии были защищены от удаления
        self.jobs = self.jobs.filter { !$0.value.state.isTerminal }
        
        onSessionChanged?(newSession)
        for transport in transports.values {
            await transport.didChangeActiveSession(newSession)
        }
        return newSession
    }
    
    @discardableResult
    public func switchActiveSession(to sessionID: UUID) async -> CaptureSession? {
        if let sessionInDb = await database.getSession(by: sessionID) {
            await storageManager.registerSession(sessionInDb)
        }
        guard let switched = await storageManager.switchSession(to: sessionID) else {
            return nil
        }
        await database.setActiveSession(id: sessionID)
        self.activeSession = switched
        self.allSessions = await database.getAllSessions()
        
        // Перезагружаем ассеты и задания для выбранной сессии
        self.assets = await database.getAssets(for: sessionID)
        rebuildCaptureGroups()
        
        let sessionJobs = await database.getJobs(for: sessionID)
        var newJobs = Dictionary(uniqueKeysWithValues: sessionJobs.map { ($0.id, $0) })
        // Сохраняем активные (нетерминальные) задания других сессий, пока они выполняются
        for (id, inFlight) in self.jobs where !inFlight.state.isTerminal {
            newJobs[id] = inFlight
        }
        self.jobs = newJobs
        
        onSessionChanged?(switched)
        for transport in transports.values {
            await transport.didChangeActiveSession(switched)
        }
        return switched
    }
    
    public func renameSession(id: UUID, newName: String) async throws -> CaptureSession {
        // 1. Проверяем, что нет активных (нетерминальных) заданий переноса для этой сессии
        let activeJobCount = jobs.values.filter { $0.sessionID == id && !$0.state.isTerminal }.count
        guard activeJobCount == 0 else {
            throw TransferError.generic("Невозможно переименовать сессию во время активной передачи файлов: выполняется \(activeJobCount) перенос(ов)")
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if allSessions.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            throw TransferError.generic("Сессия с именем '\(trimmedName)' уже существует")
        }
        
        // 2. Получаем предыдущую сессию до перемещения папки
        let existingSession: CaptureSession?
        if let found = allSessions.first(where: { $0.id == id }) {
            existingSession = found
        } else if activeSession.id == id {
            existingSession = activeSession
        } else {
            existingSession = await database.getSession(by: id)
        }
        guard let oldSession = existingSession else {
            throw TransferError.generic("Сессия не найдена")
        }
        let oldFolderPath = oldSession.folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        
        // 3. Переименовываем папку на диске
        let updatedSession = try await storageManager.renameSession(id: id, newName: newName)
        let newFolderPath = updatedSession.folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        
        // 4. Обновляем каталог (сессию, пути ассетов и пути заданий) в SQLite
        await database.updateSessionNameAndPaths(
            id: id,
            newName: updatedSession.name,
            oldFolderPath: oldFolderPath,
            newFolderPath: newFolderPath
        )
        
        // 5. Обновляем пути заданий сессии в памяти
        if oldFolderPath != newFolderPath {
            for (jobID, job) in self.jobs where job.sessionID == id {
                let destPath = job.destinationURL.resolvingSymlinksInPath().standardizedFileURL.path
                if destPath.hasPrefix(oldFolderPath) {
                    let rel = String(destPath.dropFirst(oldFolderPath.count))
                    let newURL = URL(fileURLWithPath: newFolderPath + rel)
                    var updatedJob = job
                    updatedJob.destinationURL = newURL
                    self.jobs[jobID] = updatedJob
                }
            }
        }
        
        // 6. Обновляем список сессий
        self.allSessions = await database.getAllSessions()
        
        // 7. Если переименована активная сессия — обновляем ассеты и группы в памяти
        if activeSession.id == id {
            self.activeSession = updatedSession
            self.assets = await database.getAssets(for: id)
            rebuildCaptureGroups()
            onSessionChanged?(updatedSession)
        }
        
        return updatedSession
    }
    
    public func closeSession(id: UUID) async {
        await database.setSessionClosed(id: id, isClosed: true)
        self.allSessions = await database.getAllSessions()
        if activeSession.id == id {
            self.activeSession.isClosed = true
            onSessionChanged?(self.activeSession)
        }
    }
    
    public func updateSessionMetadata(
        id: UUID,
        author: String?,
        copyright: String?,
        comment: String?
    ) async {
        await database.updateSessionMetadata(id: id, author: author, copyright: copyright, comment: comment)
        self.allSessions = await database.getAllSessions()
        if activeSession.id == id {
            self.activeSession.author = author
            self.activeSession.copyright = copyright
            self.activeSession.comment = comment
            onSessionChanged?(self.activeSession)
        }
    }
    
    public func getSessionStats(id: UUID) async -> SessionStats {
        await database.getSessionStats(id: id)
    }
    
    public func getDatabaseStats() async -> CatalogDatabase.DatabaseStats {
        await database.getDatabaseStats()
    }
    
    public func reconcileDiskCatalog() async -> (missingCount: Int, recoveredCount: Int) {
        let sessionAssets = await database.getAssets(for: activeSession.id)
        let missingIDs = reconciler.reconcileAssetsWithDisk(knownAssets: sessionAssets)
        for missingID in missingIDs {
            await database.markAssetMissing(id: missingID, isMissing: true)
        }
        let knownAssetPaths = Set(sessionAssets.map { $0.fileURL.standardizedFileURL.path })
        let untrackedAssets = reconciler.discoverAssetsInSessionFolder(session: activeSession, knownFilePaths: knownAssetPaths)
        for untracked in untrackedAssets {
            await database.upsertAsset(untracked)
        }
        self.assets = await database.getAssets(for: activeSession.id)
        rebuildCaptureGroups()
        return (missingIDs.count, untrackedAssets.count)
    }
    
    /// Очистить файлы активной сессии (с защитой активных заданий)
    public func clearActiveSession() async throws {
        let activeJobCount = jobs.values.filter { $0.sessionID == activeSession.id && !$0.state.isTerminal }.count
        guard activeJobCount == 0 else {
            throw TransferError.generic("Невозможно очистить файлы сессии: в данный момент выполняется \(activeJobCount) активных переносов")
        }
        
        try await storageManager.clearSessionFiles(sessionID: activeSession.id, activeJobCount: activeJobCount)
        
        // Удаляем записи из БД
        let sessionAssets = await database.getAssets(for: activeSession.id)
        for a in sessionAssets {
            await database.deleteAsset(id: a.id)
        }
        
        assets.removeAll()
        captureGroups.removeAll()
        // Удаляем задания только очищаемой активной сессии
        self.jobs = self.jobs.filter { $0.value.sessionID != activeSession.id }
    }
    
    /// Полное удаление сессии с диска и из базы данных (с защитой активных заданий)
    public func deleteSession(id: UUID) async throws {
        let activeJobCount = jobs.values.filter { $0.sessionID == id && !$0.state.isTerminal }.count
        guard activeJobCount == 0 else {
            throw TransferError.generic("Невозможно удалить сессию: в данный момент выполняется \(activeJobCount) активных переносов")
        }
        
        try await storageManager.deleteSessionDirectory(sessionID: id, activeJobCount: activeJobCount)
        await database.deleteSession(id: id)
        
        // Удаляем задания удаленной сессии из памяти
        self.jobs = self.jobs.filter { $0.value.sessionID != id }
        
        self.allSessions = await database.getAllSessions()
        if activeSession.id == id {
            if let next = allSessions.first {
                await switchActiveSession(to: next.id)
            } else {
                _ = try? await startNewSession()
            }
        }
    }
    
    // MARK: - Рейтинг, отбор и пакетные операции (Этап 9)
    
    public func updateRating(for groupID: String, rating: Int) async {
        guard let idx = captureGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var group = captureGroups[idx]
        group.setRating(rating)
        captureGroups[idx] = group
        
        let assetIDs = group.allAssets.map { $0.id }
        for aID in assetIDs {
            if let aIdx = assets.firstIndex(where: { $0.id == aID }) {
                assets[aIdx].rating = max(0, min(5, rating))
            }
        }
        await database.batchUpdateRating(ids: assetIDs, rating: rating)
        onCaptureGroupUpdated?(group)
    }
    
    public func updatePickStatus(for groupID: String, status: PickStatus) async {
        guard let idx = captureGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var group = captureGroups[idx]
        group.setPickStatus(status)
        captureGroups[idx] = group
        
        let assetIDs = group.allAssets.map { $0.id }
        for aID in assetIDs {
            if let aIdx = assets.firstIndex(where: { $0.id == aID }) {
                assets[aIdx].pickStatus = status
            }
        }
        await database.batchUpdatePickStatus(ids: assetIDs, status: status)
        onCaptureGroupUpdated?(group)
    }
    
    public func batchUpdateRating(groupIDs: [String], rating: Int) async {
        for gid in groupIDs {
            await updateRating(for: gid, rating: rating)
        }
    }
    
    public func batchUpdatePickStatus(groupIDs: [String], status: PickStatus) async {
        for gid in groupIDs {
            await updatePickStatus(for: gid, status: status)
        }
    }
    
    public func batchDeleteGroups(groupIDs: [String]) async throws {
        let set = Set(groupIDs)
        let groupsToDelete = captureGroups.filter { set.contains($0.id) }
        
        for g in groupsToDelete {
            for a in g.allAssets {
                try? FileManager.default.removeItem(at: a.fileURL)
                await database.deleteAsset(id: a.id)
                assets.removeAll(where: { $0.id == a.id })
            }
        }
        captureGroups.removeAll(where: { set.contains($0.id) })
    }
    
    // MARK: - Управление заданиями переноса (TransferJob)
    
    /// Проверка, был ли ассет уже импортирован в текущую сессию
    public func isAssetAlreadyImported(sourceFileID: String, filename: String, fileSize: Int64) async -> Bool {
        let importedIDs = await database.getImportedSourceFileIDs(for: activeSession.id)
        if importedIDs.contains(sourceFileID) {
            return true
        }
        return await database.hasAsset(sessionID: activeSession.id, filename: filename, fileSize: fileSize)
    }
    
    /// Получение множества идентификаторов уже импортированных файлов активной сессии
    public func getImportedSourceFileIDs() async -> Set<String> {
        await database.getImportedSourceFileIDs(for: activeSession.id)
    }
    
    /// Получение задания переноса из оперативной памяти или из базы данных SQLite
    public func getJob(by id: UUID) async -> TransferJob? {
        if let j = jobs[id] {
            return j
        }
        return await database.getJob(id: id)
    }
    
    public func getJob(id: UUID) async -> TransferJob? {
        await getJob(by: id)
    }
    
    public func upsertJobForTesting(_ job: TransferJob) async {
        self.jobs[job.id] = job
        await database.upsertJob(job)
        onJobUpdated?(job)
    }
    
    /// Поиск задания по sourceFileID среди активных заданий или в БД
    public func findJob(bySourceFileID sourceFileID: String) async -> TransferJob? {
        if let j = jobs.values.first(where: { $0.sourceFileID == sourceFileID }) {
            return j
        }
        for session in allSessions {
            let sessionJobs = await database.getJobs(for: session.id)
            if let found = sessionJobs.first(where: { $0.sourceFileID == sourceFileID }) {
                return found
            }
        }
        return nil
    }
    
    /// Создание задания переноса для входящего файла с безопасным staging-путем и контролем места
    public func createTransferJob(
        source: CameraSource,
        filename: String,
        sourceFileID: String? = nil,
        expectedSize: Int64? = nil
    ) async throws -> TransferJob {
        let session = self.activeSession
        
        // 1. Контроль свободного места на диске перед началом
        try diskGuard.validateSpaceBeforeTransfer(at: session.folderURL, expectedBytes: expectedSize ?? 0)
        
        let jobID = UUID()
        
        // 2. Создание пути во временном каталоге (.staging/*.tmp)
        let stagingURL = try await storageManager.createStagingURL(for: filename, in: session, jobID: jobID)
        
        // 3. Предварительное определение бесконфликтного целевого имени
        let destinationURL = try await storageManager.resolveUniqueDestinationURL(for: filename, in: session)
        
        let job = TransferJob(
            id: jobID,
            source: source,
            sourceFileID: sourceFileID ?? filename,
            destinationURL: destinationURL,
            stagingURL: stagingURL,
            sessionID: session.id,
            state: .pending,
            totalBytes: expectedSize
        )
        
        self.jobs[job.id] = job
        await database.upsertJob(job)
        onJobUpdated?(job)
        return job
    }
    
    public func updateJobProgress(
        jobID: UUID,
        transferredBytes: Int64,
        totalBytes: Int64?,
        speedMBs: Double
    ) {
        guard let job = jobs[jobID] else { return }
        let updated = job.updatingProgress(
            transferredBytes: transferredBytes,
            totalBytes: totalBytes,
            progress: totalBytes != nil && totalBytes! > 0 ? Double(transferredBytes) / Double(totalBytes!) : 0.0
        )
        self.jobs[jobID] = updated
        onJobUpdated?(updated)
        onSpeedUpdated?(speedMBs)
    }
    
    /// Финализация переноса: верификация во временном файле -> атомарный move -> регистрация в БД -> группировка
    @discardableResult
    public func finalizeTransfer(
        jobID: UUID,
        actualSize: Int64,
        duration: TimeInterval
    ) async throws -> MediaAsset {
        let foundJob: TransferJob?
        if let j = jobs[jobID] {
            foundJob = j
        } else {
            foundJob = await database.getJob(id: jobID)
        }
        guard let job = foundJob else {
            throw TransferError.generic("Задание \(jobID) не найдено")
        }
        
        // 1. Переход в статус проверки
        let verifyingJob = job.markingVerifying()
        self.jobs[jobID] = verifyingJob
        await database.upsertJob(verifyingJob)
        onJobUpdated?(verifyingJob)
        
        let sourceURL = job.stagingURL ?? job.destinationURL
        
        // 2. Проверка целостности файла (размер, expectedSize, magic bytes)
        let verificationResult = await storageManager.verifyFile(
            at: sourceURL,
            expectedSize: job.totalBytes ?? (actualSize > 0 ? actualSize : nil)
        )
        
        guard verificationResult.isValid else {
            let reason: String
            if case .corrupted(let err) = verificationResult {
                reason = err
            } else {
                reason = "Ошибка проверки целостности файла"
            }
            
            // Удаляем временный staging файл при ошибке
            if let st = job.stagingURL {
                await storageManager.removeStagingFile(at: st)
            }
            
            let failedJob = job.failing(error: .verificationFailed(reason))
            self.jobs[jobID] = failedJob
            await database.upsertJob(failedJob)
            onJobUpdated?(failedJob)
            throw TransferError.verificationFailed(reason)
        }
        
        // 3. Разрешение бесконфликтного целевого имени перед атомарным перемещением
        var targetSessionOpt = allSessions.first(where: { $0.id == job.sessionID })
        if targetSessionOpt == nil {
            targetSessionOpt = await database.getSession(by: job.sessionID)
        }
        guard let targetSession = targetSessionOpt ?? Optional(activeSession) else {
            throw TransferError.generic("Целевая сессия не найдена")
        }
        
        let finalDestinationURL: URL
        if job.stagingURL != nil {
            finalDestinationURL = try await storageManager.resolveUniqueDestinationURL(
                for: job.destinationURL.lastPathComponent,
                in: targetSession
            )
            // АТОМАРНОЕ ПЕРЕМЕЩЕНИЕ ИЗ .staging В ФИНАЛЬНУЮ ПАПКУ
            try await storageManager.commitStagingFile(stagingURL: sourceURL, to: finalDestinationURL)
        } else {
            finalDestinationURL = job.destinationURL
        }
        
        // 4. Извлечение метаданных
        let exif = RAWPreviewExtractor.extractEXIFMetadata(from: finalDestinationURL)
        var metadata = AssetMetadata()
        if let exifSub = exif?["{Exif}"] as? [String: Any] {
            metadata.exposureTime = exifSub["ExposureTime"] as? Double
            metadata.fNumber = exifSub["FNumber"] as? Double
            metadata.focalLength = exifSub["FocalLength"] as? Double
            if let isoArray = exifSub["ISOSpeedRatings"] as? [Int], let first = isoArray.first {
                metadata.iso = first
            }
            if let dateStr = exifSub["DateTimeOriginal"] as? String {
                let df = DateFormatter()
                df.dateFormat = "yyyy:MM:dd HH:mm:ss"
                metadata.captureDate = df.date(from: dateStr)
            }
        }
        if let tiff = exif?["{TIFF}"] as? [String: Any] {
            metadata.cameraModel = tiff["Model"] as? String ?? job.source.model
            metadata.lensModel = tiff["LensModel"] as? String
        }
        
        // 5. Создание MediaAsset и регистрация в постоянной базе данных
        let format = MediaFormat(fileExtension: finalDestinationURL.pathExtension)
        let checksum = await storageManager.computeLocalSHA256(for: finalDestinationURL)
        
        let asset = MediaAsset(
            sessionID: job.sessionID,
            filename: finalDestinationURL.lastPathComponent,
            fileURL: finalDestinationURL,
            format: format,
            fileSize: actualSize,
            metadata: metadata,
            verificationResult: verificationResult,
            sha256Checksum: checksum,
            isMissing: false,
            receivedAt: Date(),
            transferDuration: duration
        )
        
        await database.upsertAsset(asset)
        
        // 6. Добавление в CaptureGroup с поддержкой запаздывающего прихода второй части пары
        // (Оперативные коллекции обновляются только если завершенный файл принадлежит текущей активной сессии)
        let group: CaptureGroup
        if job.sessionID == activeSession.id {
            self.assets.insert(asset, at: 0)
            if let existingIndex = captureGroups.firstIndex(where: { $0.canAccept(asset: asset) }) {
                var updatedGroup = captureGroups[existingIndex]
                updatedGroup.addAsset(asset)
                captureGroups[existingIndex] = updatedGroup
                group = updatedGroup
            } else {
                let newGroup = CaptureGroup(asset: asset)
                captureGroups.insert(newGroup, at: 0)
                group = newGroup
            }
        } else {
            group = CaptureGroup(asset: asset)
        }
        
        // 7. Завершение задания
        var completedJob = job.completing(with: asset.id)
        completedJob.destinationURL = finalDestinationURL
        self.jobs[jobID] = completedJob
        await database.upsertJob(completedJob)
        
        onJobUpdated?(completedJob)
        if job.sessionID == activeSession.id {
            onCaptureGroupUpdated?(group)
            onAssetIngested?(asset, group)
        }
        onSpeedUpdated?(0.0)
        
        // 8. Фоновое автоматическое копирование (Live Mirror), если включено
        if isAutoExportEnabled, let targetURL = autoExportDestinationURL, autoExportFormat.shouldExport(asset: asset) {
            let destination = ExportDestination.directory(url: targetURL, bookmarkData: autoExportBookmarkData)
            Task.detached(priority: .utility) {
                do {
                    _ = try await ExportManager.shared.autoCopyAsset(asset, destination: destination, strategy: .rename)
                } catch {
                    // Локальный оригинал не затрагивается ни при каких обстоятельствах
                    print("[AutoExport] Предупреждение: фоновое автокопирование не удалось: \(error)")
                }
            }
        }
        
        return asset
    }
    
    public func failTransfer(jobID: UUID, error: TransferError) async {
        let jobOpt: TransferJob?
        if let j = jobs[jobID] { jobOpt = j } else { jobOpt = await database.getJob(id: jobID) }
        guard let job = jobOpt else { return }
        if let st = job.stagingURL {
            await storageManager.removeStagingFile(at: st)
        }
        let failed = job.failing(error: error)
        self.jobs[jobID] = failed
        await database.upsertJob(failed)
        onJobUpdated?(failed)
        onSpeedUpdated?(0.0)
    }
    
    public func interruptTransfer(jobID: UUID, reason: String) async {
        let jobOpt: TransferJob?
        if let j = jobs[jobID] { jobOpt = j } else { jobOpt = await database.getJob(id: jobID) }
        guard let job = jobOpt else { return }
        if let st = job.stagingURL {
            await storageManager.removeStagingFile(at: st)
        }
        let interrupted = job.interrupting(reason: reason)
        self.jobs[jobID] = interrupted
        await database.upsertJob(interrupted)
        onJobUpdated?(interrupted)
        onSpeedUpdated?(0.0)
    }
    
    public func cancelTransfer(jobID: UUID) async {
        let jobOpt: TransferJob?
        if let j = jobs[jobID] { jobOpt = j } else { jobOpt = await database.getJob(id: jobID) }
        guard let job = jobOpt else { return }
        if let st = job.stagingURL {
            await storageManager.removeStagingFile(at: st)
        }
        let cancelled = job.cancelling()
        self.jobs[jobID] = cancelled
        await database.upsertJob(cancelled)
        onJobUpdated?(cancelled)
        onSpeedUpdated?(0.0)
    }
    
    /// Подготовка существующего задания к повтору (очистка временных файлов, сброс ошибки, перевод в .pending, сохранение в БД)
    public func prepareJobForRetry(jobID: UUID) async throws -> TransferJob {
        let jobOpt: TransferJob?
        if let j = jobs[jobID] { jobOpt = j } else { jobOpt = await database.getJob(id: jobID) }
        guard let job = jobOpt else {
            throw TransferError.generic("Задание \(jobID) не найдено")
        }
        
        if let st = job.stagingURL {
            await storageManager.removeStagingFile(at: st)
        }
        
        var updatedJob = job
        updatedJob.attempts += 1
        updatedJob.state = .pending
        updatedJob.error = nil
        self.jobs[jobID] = updatedJob
        await database.upsertJob(updatedJob)
        onJobUpdated?(updatedJob)
        return updatedJob
    }
    
    public func retryTransfer(jobID: UUID) async throws {
        let updatedJob = try await prepareJobForRetry(jobID: jobID)
        
        guard updatedJob.source.transportType.supportsAppRetry else {
            throw TransferError.generic("Транспорт \(updatedJob.source.transportType.displayName) не поддерживает повтор со стороны приложения (камера отправляет файл по своей инициативе)")
        }
        
        guard let transport = transports[updatedJob.source.transportType] else {
            throw TransferError.generic("Транспорт \(updatedJob.source.transportType.displayName) не зарегистрирован")
        }
        
        try await transport.requestDownload(fileID: updatedJob.sourceFileID, into: updatedJob)
    }
    
    // MARK: - CameraTransportDelegate
    
    public func transport(_ transport: CameraTransport, didDiscoverSource source: CameraSource) async {
        if !connectedSources.contains(where: { $0.id == source.id }) {
            connectedSources.append(source)
            onSourcesChanged?(connectedSources)
        }
    }
    
    public func transport(_ transport: CameraTransport, didDisconnectSource sourceID: String) async {
        connectedSources.removeAll(where: { $0.id == sourceID })
        onSourcesChanged?(connectedSources)
    }
    
    public func transport(
        _ transport: CameraTransport,
        didReceiveFileOffer filename: String,
        from source: CameraSource,
        expectedSize: Int64?
    ) async -> TransferJob {
        return (try? await createTransferJob(source: source, filename: filename, expectedSize: expectedSize)) ?? TransferJob(
            source: source,
            sourceFileID: filename,
            destinationURL: activeSession.folderURL.appendingPathComponent(filename),
            sessionID: activeSession.id
        )
    }
    
    public func transport(
        _ transport: CameraTransport,
        didUpdateProgress jobID: UUID,
        transferredBytes: Int64,
        totalBytes: Int64?,
        speedMBs: Double
    ) async {
        updateJobProgress(
            jobID: jobID,
            transferredBytes: transferredBytes,
            totalBytes: totalBytes,
            speedMBs: speedMBs
        )
    }
    
    public func transport(
        _ transport: CameraTransport,
        didCompleteTransfer jobID: UUID,
        actualSize: Int64,
        duration: TimeInterval
    ) async {
        _ = try? await finalizeTransfer(jobID: jobID, actualSize: actualSize, duration: duration)
    }
    
    public func transport(_ transport: CameraTransport, didFailTransfer jobID: UUID, error: TransferError) async {
        await failTransfer(jobID: jobID, error: error)
    }
    
    public func transport(_ transport: CameraTransport, didInterruptTransfer jobID: UUID, reason: String) async {
        await interruptTransfer(jobID: jobID, reason: reason)
    }
    
    // MARK: - Экспорт файлов (ExportJob)
    
    public func setAutoExport(enabled: Bool, destinationURL: URL? = nil, bookmarkData: Data? = nil, format: ExportFormatSelection = .both) {
        self.isAutoExportEnabled = enabled
        self.autoExportDestinationURL = destinationURL
        self.autoExportBookmarkData = bookmarkData
        self.autoExportFormat = format
    }
    
    public func createExportJob(
        items: [ExportItem],
        destination: ExportDestination,
        formatSelection: ExportFormatSelection = .both,
        conflictStrategy: NameConflictStrategy = .rename,
        includeXMPSidecars: Bool = true,
        sidecarNamingConvention: XMPSidecarNamingConvention = .standardBasename,
        includeSessionManifest: Bool = false,
        sessionMetadata: SessionMetadata? = nil
    ) -> ExportJob {
        let job = ExportJob(
            items: items,
            destination: destination,
            formatSelection: formatSelection,
            conflictStrategy: conflictStrategy,
            includeXMPSidecars: includeXMPSidecars,
            sidecarNamingConvention: sidecarNamingConvention,
            includeSessionManifest: includeSessionManifest,
            sessionMetadata: sessionMetadata
        )
        self.exportJobs[job.id] = job
        return job
    }
    
    public func createExportJob(assetIDs: [UUID], destination: ExportDestination) -> ExportJob {
        let job = ExportJob(assetIDs: assetIDs, destination: destination)
        self.exportJobs[job.id] = job
        return job
    }
    
    public func updateExportJob(_ job: ExportJob) {
        self.exportJobs[job.id] = job
    }
}
