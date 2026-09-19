import Foundation
import CryptoKit

/// Менеджер безопасного хранения оригиналов на диске:
/// - Использование временных файлов (.staging/*.tmp)
/// - Бесконфликтное разрешение имен (без перезаписи)
/// - Контроль дискового пространства и валидация путей
/// - Атомарный перенос файлов в окончательное расположение
/// - Защита активных заданий от удаления
public actor StorageManager {
    public static let shared = StorageManager()
    
    public private(set) var activeSession: CaptureSession
    public private(set) var sessions: [CaptureSession] = []
    public let diskGuard: DiskSpaceGuard
    
    public var currentSessionURL: URL {
        activeSession.folderURL
    }
    
    public nonisolated let baseStorageURL: URL
    
    public init(
        customBaseURL: URL? = nil,
        diskGuard: DiskSpaceGuard = DiskSpaceGuard()
    ) {
        let base = (customBaseURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())).resolvingSymlinksInPath().standardizedFileURL
        let sessionsRoot = base.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        self.baseStorageURL = sessionsRoot
        self.diskGuard = diskGuard
        
        let initialName = CaptureSession.defaultSessionName()
        let initialFolder = sessionsRoot.appendingPathComponent(initialName, isDirectory: true)
        
        let session = CaptureSession(
            name: initialName,
            folderURL: initialFolder
        )
        self.activeSession = session
        self.sessions = [session]
    }
    
    // MARK: - Управление сессиями
    
    /// Синхронизация сессий (например, из БД при bootstrap)
    public func syncSessions(from list: [CaptureSession], activeSessionID: UUID? = nil) {
        guard !list.isEmpty else { return }
        self.sessions = list
        if let activeID = activeSessionID, let found = list.first(where: { $0.id == activeID }) {
            self.activeSession = found
        } else if let first = list.first {
            self.activeSession = first
        }
    }
    
    /// Регистрация существующей сессии (например, при загрузке из БД или импорте с диска)
    public func registerSession(_ session: CaptureSession, setActive: Bool = false) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        if setActive {
            self.activeSession = session
        }
    }
    
    /// Разрешение уникального имени и изолированной директории для сессии без коллизий
    private func resolveUniqueSessionFolder(for desiredName: String) -> (name: String, folderURL: URL) {
        func isOccupied(candidateName: String, candidateURL: URL) -> Bool {
            let candPath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
            // 1. Проверяем существование директории на диске
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return true
            }
            // 2. Проверяем, зарегистрирована ли сессия с таким именем или путем
            for session in sessions {
                if session.name.caseInsensitiveCompare(candidateName) == .orderedSame {
                    return true
                }
                let sessionPath = session.folderURL.resolvingSymlinksInPath().standardizedFileURL.path
                if sessionPath.caseInsensitiveCompare(candPath) == .orderedSame {
                    return true
                }
            }
            return false
        }
        
        let initialURL = baseStorageURL.appendingPathComponent(desiredName, isDirectory: true)
        if !isOccupied(candidateName: desiredName, candidateURL: initialURL) {
            return (desiredName, initialURL)
        }
        
        var counter = 1
        while true {
            let candidateName = "\(desiredName)_\(counter)"
            let candidateURL = baseStorageURL.appendingPathComponent(candidateName, isDirectory: true)
            if !isOccupied(candidateName: candidateName, candidateURL: candidateURL) {
                return (candidateName, candidateURL)
            }
            counter += 1
            if counter > 10000 {
                let suffix = UUID().uuidString.prefix(6)
                let fallbackName = "\(desiredName)_\(suffix)"
                let fallbackURL = baseStorageURL.appendingPathComponent(fallbackName, isDirectory: true)
                return (fallbackName, fallbackURL)
            }
        }
    }
    
    /// Начать новую сессию с гарантированно изолированной директорией (без перезаписи и общих папок)
    @discardableResult
    public func createNewSession(named sessionName: String? = nil) throws -> CaptureSession {
        let name = sessionName ?? CaptureSession.defaultSessionName()
        let sanitizedName = try sanitizeFilename(name)
        let (uniqueName, folderURL) = resolveUniqueSessionFolder(for: sanitizedName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        let newSession = CaptureSession(
            name: uniqueName,
            folderURL: folderURL
        )
        self.activeSession = newSession
        self.sessions.append(newSession)
        return newSession
    }
    
    /// Переключить активную сессию
    @discardableResult
    public func switchSession(to sessionID: UUID) -> CaptureSession? {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return nil
        }
        self.activeSession = session
        return session
    }
    
    /// Переименование сессии на диске с проверкой коллизий
    public func renameSession(id: UUID, newName: String) throws -> CaptureSession {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            throw TransferError.generic("Сессия не найдена")
        }
        
        let sanitized = try sanitizeFilename(newName)
        var session = sessions[index]
        let oldFolder = session.folderURL
        let newFolder = baseStorageURL.appendingPathComponent(sanitized, isDirectory: true)
        
        let newFolderPath = newFolder.resolvingSymlinksInPath().standardizedFileURL.path
        let oldFolderPath = oldFolder.resolvingSymlinksInPath().standardizedFileURL.path
        let isSameFolder = newFolderPath.caseInsensitiveCompare(oldFolderPath) == .orderedSame
        
        // Проверяем конфликт с другими зарегистрированными сессиями
        let conflictWithOther = sessions.contains { other in
            other.id != id && (
                other.name.caseInsensitiveCompare(sanitized) == .orderedSame ||
                other.folderURL.resolvingSymlinksInPath().standardizedFileURL.path.caseInsensitiveCompare(newFolderPath) == .orderedSame
            )
        }
        if conflictWithOther {
            throw TransferError.generic("Сессия с именем '\(sanitized)' уже существует")
        }
        
        if !isSameFolder {
            if FileManager.default.fileExists(atPath: newFolder.path) {
                throw TransferError.generic("Папка с именем '\(sanitized)' уже существует")
            }
            try FileManager.default.moveItem(at: oldFolder, to: newFolder)
        }
        
        session.name = sanitized
        session.folderURL = newFolder
        session.updatedAt = Date()
        sessions[index] = session
        
        if activeSession.id == id {
            self.activeSession = session
        }
        
        return session
    }
    
    // MARK: - Валидация и безопасность путей (Этап 2)
    
    /// Проверка имени файла на недопустимые символы и path traversal
    public func sanitizeFilename(_ filename: String) throws -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TransferError.generic("Имя файла не может быть пустым")
        }
        
        // Защита от выхода за пределы папки (path traversal)
        if trimmed.contains("..") || trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains("\0") {
            throw TransferError.generic("Недопустимое имя файла: содержит запрещенные символы или попытку выхода из директории: \(filename)")
        }
        
        let sanitized = (trimmed as NSString).lastPathComponent
        guard !sanitized.isEmpty && sanitized != "." && sanitized != ".." else {
            throw TransferError.generic("Некорректное имя файла: \(filename)")
        }
        
        return sanitized
    }
    
    /// Проверка, что путь файла строго находится внутри директории сессии
    public func validatePathInsideSession(url: URL, session: CaptureSession) throws {
        let sessionPath = session.folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        
        guard targetPath.hasPrefix(sessionPath) else {
            throw TransferError.generic("Безопасность: путь файла (\(targetPath)) выходит за пределы хранилища сессии (\(sessionPath))")
        }
    }
    
    /// Создание пути для временного staging-файла (.staging/transfer_<id>.tmp)
    public func createStagingURL(for filename: String, in session: CaptureSession, jobID: UUID) throws -> URL {
        let sanitized = try sanitizeFilename(filename)
        let stagingDir = session.folderURL.appendingPathComponent(".staging", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: stagingDir.path) {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        }
        
        let tempName = "transfer_\(jobID.uuidString.prefix(8))_\(sanitized).tmp"
        let tempURL = stagingDir.appendingPathComponent(tempName)
        try validatePathInsideSession(url: tempURL, session: session)
        return tempURL
    }
    
    /// Разрешение конфликтов имен без перезаписи оригинала
    /// Если DSC_0001.NEF уже существует, генерируется DSC_0001_1.NEF, DSC_0001_2.NEF и т.д.
    public func resolveUniqueDestinationURL(for filename: String, in session: CaptureSession) throws -> URL {
        let sanitized = try sanitizeFilename(filename)
        let folder = session.folderURL
        
        let destinationURL = folder.appendingPathComponent(sanitized)
        try validatePathInsideSession(url: destinationURL, session: session)
        
        // Если файла нет — используем исходное имя
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        // Если файл существует — разрешаем коллизию добавлением суффикса
        let ns = sanitized as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        
        var counter = 1
        while true {
            let candidateName = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
            let candidateURL = folder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
            if counter > 10000 {
                // Защита от бесконечного цикла
                let uuidSuffix = UUID().uuidString.prefix(6)
                let fallbackName = ext.isEmpty ? "\(base)_\(uuidSuffix)" : "\(base)_\(uuidSuffix).\(ext)"
                return folder.appendingPathComponent(fallbackName)
            }
        }
    }
    
    /// Атомарный перенос временного файла в окончательное расположение
    public func commitStagingFile(stagingURL: URL, to finalURL: URL) throws {
        // Убеждаемся, что директория назначения существует
        let parentDir = finalURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // Если в точке назначения уже что-то появилось (гонка), удалять нельзя
        if FileManager.default.fileExists(atPath: finalURL.path) {
            throw TransferError.generic("Файл в точке назначения уже существует: \(finalURL.lastPathComponent)")
        }
        
        try FileManager.default.moveItem(at: stagingURL, to: finalURL)
    }
    
    /// Удаление временного файла в случае ошибки или отмены
    public func removeStagingFile(at stagingURL: URL) {
        if FileManager.default.fileExists(atPath: stagingURL.path) {
            try? FileManager.default.removeItem(at: stagingURL)
        }
    }
    
    /// Очистка всех остаточных staging файлов сессии (после аварий или сбоев)
    public func cleanupStagingFiles(in session: CaptureSession) {
        let stagingDir = session.folderURL.appendingPathComponent(".staging", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "tmp" || file.lastPathComponent.hasPrefix("transfer_") {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    // MARK: - Проверка целостности и хеширование
    
    /// Вычисление контрольной суммы SHA-256 локального файла для последующей проверки и поиска дубликатов.
    /// ВНИМАНИЕ: Локально вычисленная сумма не является доказательством совпадения с камерой,
    /// если камера не передает собственную контрольную сумму в протоколе.
    public func computeLocalSHA256(for fileURL: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        while true {
            guard let data = try? fileHandle.read(upToCount: 1024 * 1024), !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Проверка целостности файла (размер, соответствие ожидаемому размеру, magic bytes заголовка)
    public func verifyFile(at fileURL: URL, expectedSize: Int64? = nil) -> AssetVerificationResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .corrupted(reason: "Файл не существует на диске")
        }
        
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else {
            return .corrupted(reason: "Не удалось прочитать атрибуты файла")
        }
        
        guard size > 0 else {
            return .corrupted(reason: "Размер файла равен 0 байт")
        }
        
        if let expected = expectedSize, expected > 0, size != expected {
            return .corrupted(reason: "Несовпадение записанного размера: получено \(size) байт, ожидалось \(expected)")
        }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return .corrupted(reason: "Не удалось открыть файл для чтения заголовка")
        }
        defer { try? fileHandle.close() }
        
        guard let headerData = try? fileHandle.read(upToCount: 16), headerData.count >= 4 else {
            return .corrupted(reason: "Заголовок файла поврежден или не читается")
        }
        
        var ext = fileURL.pathExtension.lowercased()
        if ext == "tmp" {
            ext = fileURL.deletingPathExtension().pathExtension.lowercased()
        }
        
        if ext == "nef" || ext == "nrw" {
            let bytes = [UInt8](headerData)
            let isLittleEndianTIFF = bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00
            let isBigEndianTIFF = bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A
            if !isLittleEndianTIFF && !isBigEndianTIFF {
                return .corrupted(reason: "Некорректная сигнатура TIFF/NEF в заголовке")
            }
        } else if ext == "jpg" || ext == "jpeg" {
            let bytes = [UInt8](headerData)
            if bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF {
                return .corrupted(reason: "Некорректная сигнатура JPEG в заголовке")
            }
        }
        
        let checksum = computeLocalSHA256(for: fileURL)
        return .valid(checksum: checksum)
    }
    
    // MARK: - Безопасная очистка сессии с защитой активных заданий
    
    /// Очистить файлы сессии с проверкой отсутствия активных заданий и защитой общих директорий
    public func clearSessionFiles(sessionID: UUID, activeJobCount: Int) throws {
        guard activeJobCount == 0 else {
            throw TransferError.generic("Невозможно удалить файлы сессии: в данный момент выполняется \(activeJobCount) активных переносов")
        }
        
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            throw TransferError.generic("Сессия не найдена")
        }
        
        let targetPath = session.folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        let isFolderShared = sessions.contains(where: {
            $0.id != sessionID &&
            $0.folderURL.resolvingSymlinksInPath().standardizedFileURL.path.caseInsensitiveCompare(targetPath) == .orderedSame
        })
        
        if !isFolderShared {
            let basePath = baseStorageURL.resolvingSymlinksInPath().standardizedFileURL.path
            if targetPath.hasPrefix(basePath) && targetPath != basePath {
                try? FileManager.default.removeItem(at: session.folderURL)
                try? FileManager.default.createDirectory(at: session.folderURL, withIntermediateDirectories: true)
            }
        }
    }
    
    /// Удаление всей сессии с диска с защитой от случайного удаления общих папок других сессий
    public func deleteSessionDirectory(sessionID: UUID, activeJobCount: Int) throws {
        guard activeJobCount == 0 else {
            throw TransferError.generic("Невозможно удалить сессию: в данный момент выполняется \(activeJobCount) активных переносов")
        }
        
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            throw TransferError.generic("Сессия не найдена")
        }
        
        let targetPath = session.folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        let isFolderShared = sessions.contains(where: {
            $0.id != sessionID &&
            $0.folderURL.resolvingSymlinksInPath().standardizedFileURL.path.caseInsensitiveCompare(targetPath) == .orderedSame
        })
        
        if !isFolderShared {
            let basePath = baseStorageURL.resolvingSymlinksInPath().standardizedFileURL.path
            if targetPath.hasPrefix(basePath) && targetPath != basePath {
                try? FileManager.default.removeItem(at: session.folderURL)
            }
        }
        
        sessions.removeAll(where: { $0.id == sessionID })
        if activeSession.id == sessionID, let next = sessions.first {
            self.activeSession = next
        }
    }
    
    /// Для обратной совместимости
    public func prepareDestinationURL(for filename: String, in session: CaptureSession) -> URL {
        (try? resolveUniqueDestinationURL(for: filename, in: session)) ?? session.folderURL.appendingPathComponent(filename)
    }
    
    public func prepareDestinationURL(for filename: String) -> URL {
        prepareDestinationURL(for: filename, in: activeSession)
    }
    
    public func clearCurrentSession() {
        try? clearSessionFiles(sessionID: activeSession.id, activeJobCount: 0)
    }
}
