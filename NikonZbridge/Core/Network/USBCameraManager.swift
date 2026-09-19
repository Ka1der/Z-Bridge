import Foundation
@preconcurrency import ImageCaptureCore
import CoreGraphics

/// Менеджер прямого кабельного подключения к камере Nikon в режиме «Передача файлов» (MTP/PTP)
/// Реализует управляемую очередь, дифференциацию оглавления и live-снимков, режимы импорта и просмотр содержимого карты.
@MainActor
public final class USBCameraManager: NSObject, ObservableObject, @preconcurrency CameraTransport, @unchecked Sendable {
    public static let shared = USBCameraManager()
    
    // MARK: - CameraTransport Conformance
    public let transportType: CameraTransportType = .usb
    public weak var delegate: CameraTransportDelegate?
    
    public var connectedSource: CameraSource? {
        guard let cam = connectedCamera else { return nil }
        return CameraSource(
            id: "usb-\(cam.name ?? "nikon")",
            model: cam.name,
            transportType: .usb
        )
    }
    
    // MARK: - Published State
    @Published public var connectionState: USBCameraConnectionState = .disconnected
    @Published public var importMode: USBImportMode = .onlyNew
    @Published public var catalogFiles: [CameraFileItem] = []
    
    @Published public var connectedCamera: ICCameraDevice?
    @Published public var cameraName: String?
    @Published public var isConnected: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var isCatalogReady: Bool = false
    @Published public var pendingQueueCount: Int = 0
    @Published public var activeTransferCount: Int = 0
    
    public var onFileIngested: (@Sendable (IngestedFile) -> Void)?
    public var onProgress: (@Sendable (Int64, Double) -> Void)?
    
    // MARK: - Private State & Queue
    private let browser = ICDeviceBrowser()
    private let coordinator: TransferCoordinator
    public let transferQueue: USBTransferQueue
    
    private var downloadStartTimes: [String: Date] = [:] // compositeID -> Date
    private var inFlightJobs: [String: UUID] = [:]       // compositeID -> JobID
    private var cameraFileMap: [String: ICCameraFile] = [:] // compositeID -> ICCameraFile
    private var cancellingCompositeIDs: Set<String> = []
    
    public init(
        coordinator: TransferCoordinator = .shared,
        maxConcurrentDownloads: Int = 1
    ) {
        self.coordinator = coordinator
        self.transferQueue = USBTransferQueue(maxConcurrentDownloads: maxConcurrentDownloads)
        super.init()
        setupBrowser()
    }
    
    public func start() {
        browser.start()
    }
    
    public func stop() async {
        browser.stop()
        if let cam = connectedCamera {
            try? await cam.requestCloseSession()
        }
        await resetState()
    }
    
    private func setupBrowser() {
        browser.delegate = self
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask) ?? .camera
    }
    
    // MARK: - Управление режимами импорта и запуск загрузок
    
    public func setImportMode(_ mode: USBImportMode) {
        self.importMode = mode
        if mode == .allUnimported && isCatalogReady {
            Task {
                await importAllUnimported()
            }
        }
    }
    
    /// Импорт только выбранных пользователем файлов
    public func importSelectedFiles(_ items: [CameraFileItem]) async {
        guard connectedCamera != nil else { return }
        for item in items where item.status != .imported && item.status != .queued {
            guard let file = item.cameraFile ?? cameraFileMap[item.id] else { continue }
            cameraFileMap[item.id] = file
            if !catalogFiles.contains(where: { $0.id == item.id }) {
                catalogFiles.append(item)
            }
            await scheduleDownload(for: file, compositeID: item.id, existingJob: nil)
        }
        await processQueue()
    }
    
    /// Импорт всех ещё не импортированных файлов из каталога карты
    public func importAllUnimported() async {
        guard connectedCamera != nil, isCatalogReady else { return }
        for item in catalogFiles where item.status == .notImported {
            guard let file = item.cameraFile ?? cameraFileMap[item.id] else { continue }
            await scheduleDownload(for: file, compositeID: item.id, existingJob: nil)
        }
        await processQueue()
    }
    
    /// Запрос миниатюры для элемента оглавления
    public func requestThumbnail(for item: CameraFileItem) {
        guard let file = item.cameraFile ?? cameraFileMap[item.id] else { return }
        file.requestThumbnail()
    }
    
    // MARK: - CameraTransport Protocol (Pull & Retry)
    
    public func requestDownload(fileID: String, into job: TransferJob) async throws {
        guard let camera = connectedCamera else {
            throw TransferError.connectionLost("Камера не подключена по USB")
        }
        
        // Поиск файла по составному идентификатору или имени
        let foundFile = cameraFileMap[fileID]
            ?? (camera.mediaFiles as? [ICCameraFile])?.first(where: { $0.name == fileID || $0.name == job.filename })
        
        guard let file = foundFile else {
            throw TransferError.fileNotFound(fileID)
        }
        
        let compositeID = cameraFileMap.first(where: { $0.value == file })?.key
            ?? CameraFileItem.makeCompositeID(
                cameraID: camera.name ?? "nikon",
                filename: file.name ?? job.filename,
                fileSize: file.fileSize,
                creationDate: file.creationDate
            )
        cameraFileMap[compositeID] = file
        
        await scheduleDownload(for: file, compositeID: compositeID, existingJob: job)
        await processQueue()
    }
    
    public func retryTransfer(jobID: UUID) async throws {
        guard let camera = connectedCamera else {
            throw TransferError.connectionLost("Камера не подключена по USB")
        }
        
        // 1. Подготавливаем задание в координаторе (сброс ошибки, перевод в .pending, сохранение в БД)
        let updatedJob = try await coordinator.prepareJobForRetry(jobID: jobID)
        
        // 2. Ищем файл по sourceFileID или имени файла
        let fileID = updatedJob.sourceFileID
        let foundFile = cameraFileMap[fileID]
            ?? (camera.mediaFiles as? [ICCameraFile])?.first(where: { $0.name == fileID || $0.name == updatedJob.filename })
        
        guard let file = foundFile else {
            throw TransferError.fileNotFound(updatedJob.filename)
        }
        
        // 3. Определяем составной идентификатор и кэшируем файл
        let compositeID = cameraFileMap.first(where: { $0.value == file })?.key
            ?? CameraFileItem.makeCompositeID(
                cameraID: camera.name ?? "nikon",
                filename: file.name ?? updatedJob.filename,
                fileSize: file.fileSize,
                creationDate: file.creationDate
            )
        cameraFileMap[compositeID] = file
        
        // Гарантируем, что для повторяемого файла нет ошибочной отметки в importedIDs
        await transferQueue.unmarkImported(compositeID: compositeID)
        
        // 4. Планируем загрузку с существующим обновленным заданием
        await scheduleDownload(for: file, compositeID: compositeID, existingJob: updatedJob)
        await processQueue()
    }
    
    // MARK: - Планирование и исполнение очереди
    
    private func scheduleDownload(for cameraFile: ICCameraFile, compositeID: String, existingJob: TransferJob?) async {
        guard let camera = connectedCamera else { return }
        let filename = cameraFile.name ?? catalogFiles.first(where: { $0.id == compositeID })?.filename ?? "DSC_0001.NEF"
        let fileSize = cameraFile.fileSize > 0 ? cameraFile.fileSize : (catalogFiles.first(where: { $0.id == compositeID })?.fileSize ?? 0)
        
        // 1. Проверяем, не скачан ли уже файл в текущей сессии
        let alreadyImported = await coordinator.isAssetAlreadyImported(
            sourceFileID: compositeID,
            filename: filename,
            fileSize: fileSize
        )
        if alreadyImported {
            updateItemStatus(compositeID: compositeID, status: .imported)
            return
        }
        
        // 2. Создаем задание в координаторе, если еще нет
        let job: TransferJob
        if let existing = existingJob {
            job = existing
        } else {
            let source = connectedSource ?? CameraSource(
                id: "usb-\(camera.name ?? "nikon")",
                model: camera.name,
                transportType: .usb
            )
            do {
                job = try await coordinator.createTransferJob(
                    source: source,
                    filename: filename,
                    sourceFileID: compositeID,
                    expectedSize: fileSize
                )
            } catch {
                updateItemStatus(compositeID: compositeID, status: .failed(error: error.localizedDescription))
                return
            }
        }
        
        let queueItem = USBQueueItem(
            compositeID: compositeID,
            cameraFile: cameraFile,
            filename: filename,
            fileSize: fileSize,
            jobID: job.id,
            attempts: job.attempts
        )
        
        let didEnqueue = await transferQueue.enqueue(queueItem)
        if didEnqueue {
            updateItemStatus(compositeID: compositeID, status: .queued)
        }
        await updateQueueCounters()
    }
    
    /// Обработка очереди: запуск следующей загрузки в пределах лимита параллелизма
    public func processQueue(item: USBQueueItem? = nil) async {
        guard let camera = connectedCamera, !isDownloading else { return }
        
        let itemToProcess: USBQueueItem
        if let explicitItem = item {
            itemToProcess = explicitItem
        } else if let unstartedActive = await transferQueue.allActiveItems.first(where: { inFlightJobs[$0.compositeID] == nil }) {
            itemToProcess = unstartedActive
        } else if let nextItem = await transferQueue.dequeueNextIfAvailable() {
            itemToProcess = nextItem
        } else {
            await updateQueueCounters()
            return
        }
        
        let compositeID = itemToProcess.compositeID
        let jobID = itemToProcess.jobID
        let cameraFile = itemToProcess.cameraFile
        
        let coordJob = await coordinator.getJob(by: jobID)
        guard let validJob = coordJob, !validJob.state.isTerminal else {
            let next = await transferQueue.cancel(compositeID: compositeID)
            updateItemStatus(compositeID: compositeID, status: .notImported)
            await updateQueueCounters()
            await processQueue(item: next)
            return
        }
        
        let safeTargetURL = validJob.stagingURL ?? validJob.destinationURL
        let destinationDir = safeTargetURL.deletingLastPathComponent()
        let destinationName = safeTargetURL.lastPathComponent
        
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destinationDir,
            .saveAsFilename: destinationName,
            .overwrite: true
        ]
        
        self.downloadStartTimes[compositeID] = Date()
        self.inFlightJobs[compositeID] = jobID
        self.isDownloading = true
        updateItemStatus(compositeID: compositeID, status: .importing(progress: 0.0))
        await updateQueueCounters()
        
        camera.requestDownloadFile(
            cameraFile,
            options: options,
            downloadDelegate: self,
            didDownloadSelector: #selector(didDownloadFile(_:error:options:contextInfo:)),
            contextInfo: nil
        )
    }
    
    /// Отмена загрузки
    public func cancelTransfer(jobID: UUID) async {
        // 1. Поиск составного идентификатора: в выполняющихся (in-flight) либо в очереди ожидания (pending)
        let activeCompositeID = inFlightJobs.first(where: { $0.value == jobID })?.key
        var compositeID = activeCompositeID
        if compositeID == nil {
            compositeID = await transferQueue.findPendingCompositeID(by: jobID)
        }
        if compositeID == nil {
            compositeID = await transferQueue.findCompositeID(by: jobID)
        }
        
        // 2. Всегда уведомляем координатор об отмене задания
        await coordinator.cancelTransfer(jobID: jobID)
        
        guard let targetCompositeID = compositeID else {
            await updateQueueCounters()
            return
        }
        
        if activeCompositeID != nil {
            // Задание выполняется прямо сейчас (в полете):
            // Помечаем как отменяемое, вызываем физическую отмену ImageCaptureCore на macOS и iOS,
            // но НЕ сбрасываем активность сразу и НЕ освобождаем слот до завершения колбэка didDownloadFile!
            cancellingCompositeIDs.insert(targetCompositeID)
            updateItemStatus(compositeID: targetCompositeID, status: .notImported)
            #if os(macOS)
            connectedCamera?.cancelDownload()
            #else
            let cancelSelector = Selector(("cancelDownload"))
            if let cam = connectedCamera, cam.responds(to: cancelSelector) {
                cam.perform(cancelSelector)
            }
            #endif
            await updateQueueCounters()
        } else {
            // Задание находится в очереди ожидания (pending):
            // Удаляем из очереди, сбрасываем статус, слот не был занят
            _ = await transferQueue.cancel(compositeID: targetCompositeID)
            updateItemStatus(compositeID: targetCompositeID, status: .notImported)
            await updateQueueCounters()
            if !isDownloading {
                await processQueue()
            }
        }
    }
    
    private func updateQueueCounters() async {
        let active = await transferQueue.activeCount
        let pending = await transferQueue.pendingCount
        self.activeTransferCount = active
        self.pendingQueueCount = pending
        
        if active > 0 || pending > 0 {
            self.connectionState = .transferring(activeCount: active, pendingCount: pending)
        } else if isCatalogReady {
            self.connectionState = .ready(name: cameraName ?? "Nikon Z", totalItems: catalogFiles.count)
        }
    }
    
    private func updateItemStatus(compositeID: String, status: CameraFileImportStatus) {
        if let idx = catalogFiles.firstIndex(where: { $0.id == compositeID }) {
            catalogFiles[idx].status = status
        }
    }
    
    private func resetState() async {
        await transferQueue.clearAll()
        self.connectedCamera = nil
        self.cameraName = nil
        self.isConnected = false
        self.isDownloading = false
        self.isCatalogReady = false
        self.catalogFiles.removeAll()
        self.cameraFileMap.removeAll()
        self.inFlightJobs.removeAll()
        self.downloadStartTimes.removeAll()
        self.cancellingCompositeIDs.removeAll()
        self.connectionState = .disconnected
        self.pendingQueueCount = 0
        self.activeTransferCount = 0
    }
}

// MARK: - ICDeviceBrowserDelegate

extension USBCameraManager: @preconcurrency ICDeviceBrowserDelegate {
    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        
        let name = camera.name ?? "Nikon Z"
        self.connectedCamera = camera
        self.cameraName = name
        self.connectionState = .discovered(name: name)
        
        camera.delegate = self
        self.connectionState = .openingSession(name: name)
        camera.requestOpenSession()
        
        if let source = connectedSource {
            Task {
                await coordinator.transport(self, didDiscoverSource: source)
            }
        }
    }
    
    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if device == connectedCamera {
            handleDisconnection()
        }
    }
    
    private func handleDisconnection() {
        let sourceID = connectedSource?.id ?? "usb-camera"
        let interruptedJobs = Array(inFlightJobs.values)
        
        Task {
            // Прерываем все активные задания в координаторе
            for jid in interruptedJobs {
                await coordinator.interruptTransfer(jobID: jid, reason: "USB-кабель камеры отключен")
            }
            await coordinator.transport(self, didDisconnectSource: sourceID)
            await resetState()
        }
    }
}

// MARK: - ICCameraDeviceDelegate & ICCameraDeviceDownloadDelegate

extension USBCameraManager: @preconcurrency ICCameraDeviceDelegate, @preconcurrency ICCameraDeviceDownloadDelegate {
    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        let name = device.name ?? "Nikon Z"
        if let error = error {
            self.connectionState = .error(message: error.localizedDescription)
            return
        }
        
        self.isConnected = true
        self.connectionState = .sessionOpened(name: name)
        
        // Синхронизируем уже импортированные файлы с базы данных
        Task {
            let imported = await coordinator.getImportedSourceFileIDs()
            await transferQueue.registerExistingImportedIDs(Array(imported))
        }
    }
    
    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        self.isConnected = false
        self.connectionState = .disconnected
    }
    
    public func didRemove(_ device: ICDevice) {
        handleDisconnection()
    }
    
    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        self.connectionState = .accessDenied(reason: "Камера заблокирована или доступ ограничен системой")
    }
    
    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        if isConnected {
            self.connectionState = .sessionOpened(name: device.name ?? "Nikon Z")
        }
    }
    
    /// Добавление файлов камерой:
    /// - До вызова deviceDidBecomeReady: первоначальное оглавление карты памяти.
    /// - После вызова deviceDidBecomeReady: новые кадры, сделанные фотографом.
    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let camID = camera.name ?? "nikon"
        var newFilesAdded = 0
        
        for item in items {
            guard let file = item as? ICCameraFile else { continue }
            let filename = file.name ?? "DSC_0001.NEF"
            let fileSize = file.fileSize
            let creation = file.creationDate
            
            let compositeID = CameraFileItem.makeCompositeID(
                cameraID: camID,
                filename: filename,
                fileSize: fileSize,
                creationDate: creation
            )
            
            cameraFileMap[compositeID] = file
            
            let fileItem = CameraFileItem(
                cameraID: camID,
                filename: filename,
                fileSize: fileSize,
                creationDate: creation,
                cameraFile: file,
                isInitialCatalog: !isCatalogReady
            )
            
            if !catalogFiles.contains(where: { $0.id == compositeID }) {
                catalogFiles.append(fileItem)
                newFilesAdded += 1
            }
            
            // Если каталог уже готов — это новый снимок (live tethering)!
            if isCatalogReady {
                if importMode == .onlyNew || importMode == .allUnimported {
                    Task {
                        await scheduleDownload(for: file, compositeID: compositeID, existingJob: nil)
                        await processQueue()
                    }
                }
            }
        }
        
        if !isCatalogReady {
            connectionState = .enumeratingCatalog(name: camera.name ?? "Nikon Z", itemsFound: catalogFiles.count)
        }
    }
    
    /// Срабатывает, когда полное первоначальное оглавление карты памяти прочитано
    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        self.isCatalogReady = true
        let name = device.name ?? "Nikon Z"
        let total = catalogFiles.count
        self.connectionState = .ready(name: name, totalItems: total)
        
        Task {
            // Проверяем статус для каждого файла в каталоге
            let importedIDs = await coordinator.getImportedSourceFileIDs()
            for idx in catalogFiles.indices {
                if importedIDs.contains(catalogFiles[idx].id) {
                    catalogFiles[idx].status = .imported
                }
            }
            
            // В режиме «Все неимпортированные» запускаем загрузку оставшихся
            if importMode == .allUnimported {
                await importAllUnimported()
            }
        }
    }
    
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {
        guard let file = item as? ICCameraFile, let thumb = thumbnail else { return }
        let camID = camera.name ?? "nikon"
        let compositeID = CameraFileItem.makeCompositeID(
            cameraID: camID,
            filename: file.name ?? "",
            fileSize: file.fileSize,
            creationDate: file.creationDate
        )
        if let idx = catalogFiles.firstIndex(where: { $0.id == compositeID }) {
            catalogFiles[idx].thumbnail = thumb
        }
    }
    
    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        let removedIDs = Set(items.compactMap { item -> String? in
            guard let file = item as? ICCameraFile else { return nil }
            return CameraFileItem.makeCompositeID(
                cameraID: camera.name ?? "nikon",
                filename: file.name ?? "",
                fileSize: file.fileSize,
                creationDate: file.creationDate
            )
        })
        catalogFiles.removeAll(where: { removedIDs.contains($0.id) })
    }
    
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    
    @objc(didReceiveDownloadProgressForFile:downloadedBytes:maxBytes:)
    public func didReceiveDownloadProgress(for file: ICCameraFile, downloadedBytes: off_t, maxBytes: off_t) {
        let camID = connectedCamera?.name ?? "nikon"
        let compositeID = CameraFileItem.makeCompositeID(
            cameraID: camID,
            filename: file.name ?? "DSC_0001.NEF",
            fileSize: file.fileSize,
            creationDate: file.creationDate
        )
        
        if cancellingCompositeIDs.contains(compositeID) {
            return
        }
        
        let progress = maxBytes > 0 ? Double(downloadedBytes) / Double(maxBytes) : 0.0
        updateItemStatus(compositeID: compositeID, status: .importing(progress: progress))
        
        if let jobID = inFlightJobs[compositeID] {
            let startTime = downloadStartTimes[compositeID] ?? Date()
            let elapsed = max(Date().timeIntervalSince(startTime), 0.001)
            let speedMBs = (Double(downloadedBytes) / 1_048_576.0) / elapsed
            
            let coord = self.coordinator
            Task {
                await coord.updateJobProgress(
                    jobID: jobID,
                    transferredBytes: Int64(downloadedBytes),
                    totalBytes: Int64(maxBytes),
                    speedMBs: speedMBs
                )
            }
        }
    }
    
    @objc public func didDownloadFile(
        _ file: ICCameraFile,
        error: Error?,
        options: [String: Any],
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let camID = connectedCamera?.name ?? "nikon"
        let compositeID = CameraFileItem.makeCompositeID(
            cameraID: camID,
            filename: file.name ?? "DSC_0001.NEF",
            fileSize: file.fileSize,
            creationDate: file.creationDate
        )
        
        var targetCompositeID = compositeID
        if inFlightJobs[targetCompositeID] == nil {
            if let matched = inFlightJobs.first(where: { cameraFileMap[$0.key] == file })?.key {
                targetCompositeID = matched
            }
        }
        
        let startTime = downloadStartTimes.removeValue(forKey: targetCompositeID) ?? Date()
        let duration = max(Date().timeIntervalSince(startTime), 0.001)
        let fileSize = file.fileSize
        let jobID = inFlightJobs.removeValue(forKey: targetCompositeID)
        let isCancelled = cancellingCompositeIDs.remove(targetCompositeID) != nil
        let coord = self.coordinator
        
        Task {
            if isCancelled {
                let nextItem = await transferQueue.cancel(compositeID: targetCompositeID)
                updateItemStatus(compositeID: targetCompositeID, status: .notImported)
                self.isDownloading = false
                await updateQueueCounters()
                await processQueue(item: nextItem)
                return
            }
            
            if let err = error {
                let nextItem = await transferQueue.markFailed(compositeID: targetCompositeID)
                updateItemStatus(compositeID: targetCompositeID, status: .failed(error: err.localizedDescription))
                if let id = jobID {
                    await coord.failTransfer(jobID: id, error: .generic(err.localizedDescription))
                }
                self.isDownloading = false
                await updateQueueCounters()
                await processQueue(item: nextItem)
                return
            }
            
            if let id = jobID {
                if let currentJob = await coord.getJob(by: id), currentJob.state.isTerminal {
                    let nextItem = await transferQueue.markFailed(compositeID: targetCompositeID)
                    updateItemStatus(compositeID: targetCompositeID, status: .notImported)
                    self.isDownloading = false
                    await updateQueueCounters()
                    await processQueue(item: nextItem)
                    return
                }
                
                do {
                    let asset = try await coord.finalizeTransfer(
                        jobID: id,
                        actualSize: fileSize,
                        duration: duration
                    )
                    // Только после успешной финализации отмечаем файл импортированным в очереди
                    let nextItem = await transferQueue.markCompleted(compositeID: targetCompositeID)
                    updateItemStatus(compositeID: targetCompositeID, status: .imported)
                    self.isDownloading = false
                    await MainActor.run {
                        self.onFileIngested?(IngestedFile(from: asset))
                    }
                    await updateQueueCounters()
                    await processQueue(item: nextItem)
                } catch {
                    // При ошибке верификации/финализации освобождаем слот БЕЗ добавления в importedIDs
                    let nextItem = await transferQueue.markFailed(compositeID: targetCompositeID)
                    updateItemStatus(compositeID: targetCompositeID, status: .failed(error: error.localizedDescription))
                    self.isDownloading = false
                    await updateQueueCounters()
                    await processQueue(item: nextItem)
                }
            } else {
                let nextItem = await transferQueue.markCompleted(compositeID: targetCompositeID)
                self.isDownloading = false
                await updateQueueCounters()
                await processQueue(item: nextItem)
            }
        }
    }
}
