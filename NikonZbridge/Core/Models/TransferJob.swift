import Foundation

/// Ошибки процесса передачи
public enum TransferError: Error, Sendable, Codable, Hashable {
    case connectionLost(String)
    case fileNotFound(String)
    case verificationFailed(String)
    case diskWriteFailed(String)
    case cancelled
    case timeout
    case generic(String)
    
    public var localizedDescription: String {
        switch self {
        case .connectionLost(let msg): return "Соединение разорвано: \(msg)"
        case .fileNotFound(let file): return "Файл не найден на камере: \(file)"
        case .verificationFailed(let msg): return "Ошибка проверки целостности: \(msg)"
        case .diskWriteFailed(let msg): return "Ошибка записи на диск: \(msg)"
        case .cancelled: return "Передача отменена"
        case .timeout: return "Превышено время ожидания"
        case .generic(let msg): return msg
        }
    }
}

/// Состояние процесса переноса файла
public enum TransferState: Sendable, Codable, Hashable {
    /// Ожидание начала передачи
    case pending
    /// Выполнение передачи данных
    case inProgress(progress: Double, bytesTransferred: Int64, totalBytes: Int64?)
    /// Проверка целостности полученного файла (хэш, сигнатура формата)
    case verifying
    /// Успешное завершение переноса и регистрации ассета
    case completed(assetID: UUID)
    /// Ошибка передачи
    case failed(error: TransferError)
    /// Отмена пользователем
    case cancelled
    /// Прерывание (например, разрыв соединения или выключение камеры)
    case interrupted(reason: String)
    
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .interrupted:
            return true
        case .pending, .inProgress, .verifying:
            return false
        }
    }
    
    public var isSuccess: Bool {
        if case .completed = self { return true }
        return false
    }
    
    public var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
    
    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
    
    public var isVerifying: Bool {
        if case .verifying = self { return true }
        return false
    }
    
    public var isFailed: Bool {
        if case .failed = self { return true }
        if case .interrupted = self { return true }
        return false
    }
    
    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
    
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
    
    public var label: String {
        switch self {
        case .pending: return "Ожидание"
        case .inProgress: return "Выполнение"
        case .verifying: return "Проверка"
        case .completed: return "Завершено"
        case .failed: return "Ошибка"
        case .cancelled: return "Отменено"
        case .interrupted: return "Прервано"
        }
    }
}

/// Задание на перенос одного файла с камеры
public struct TransferJob: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let source: CameraSource
    public let sourceFileID: String
    /// Назначение сохранения на диске. Жестко фиксируется в момент создания задания и НЕ меняется при смене активной сессии.
    public var destinationURL: URL
    /// Путь к временному staging-файлу, в который ведется активная потоковая запись (.staging/*.tmp)
    public var stagingURL: URL?
    /// Сессия, к которой жестко привязано задание.
    public let sessionID: UUID
    
    public var state: TransferState
    public var progress: Double
    public var transferredBytes: Int64
    public var totalBytes: Int64?
    public var attempts: Int
    public var maxAttempts: Int
    public var error: TransferError?
    public let createdAt: Date
    public var updatedAt: Date
    
    public var filename: String {
        destinationURL.lastPathComponent
    }
    
    public var progressPercent: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return min(max((Double(transferredBytes) / Double(total)) * 100.0, 0.0), 100.0)
    }
    
    public init(
        id: UUID = UUID(),
        source: CameraSource,
        sourceFileID: String,
        destinationURL: URL,
        stagingURL: URL? = nil,
        sessionID: UUID,
        state: TransferState = .pending,
        progress: Double = 0.0,
        transferredBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        attempts: Int = 0,
        maxAttempts: Int? = nil,
        error: TransferError? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.sourceFileID = sourceFileID
        self.destinationURL = destinationURL
        self.stagingURL = stagingURL
        self.sessionID = sessionID
        self.state = state
        self.progress = progress
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.attempts = attempts
        self.maxAttempts = maxAttempts ?? (source.transportType.supportsAppRetry ? 3 : 1)
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Создание копии задания с обновленным прогрессом
    public func updatingProgress(transferredBytes: Int64, totalBytes: Int64?, progress: Double) -> TransferJob {
        var copy = self
        copy.transferredBytes = transferredBytes
        copy.totalBytes = totalBytes ?? self.totalBytes
        copy.progress = min(max(progress, 0.0), 1.0)
        copy.state = .inProgress(progress: copy.progress, bytesTransferred: transferredBytes, totalBytes: copy.totalBytes)
        copy.updatedAt = Date()
        return copy
    }
    
    /// Переход в состояние верификации
    public func markingVerifying() -> TransferJob {
        var copy = self
        copy.state = .verifying
        copy.updatedAt = Date()
        return copy
    }
    
    /// Успешное завершение
    public func completing(with assetID: UUID) -> TransferJob {
        var copy = self
        copy.state = .completed(assetID: assetID)
        copy.progress = 1.0
        copy.updatedAt = Date()
        return copy
    }
    
    /// Фиксация ошибки
    public func failing(error: TransferError) -> TransferJob {
        var copy = self
        copy.state = .failed(error: error)
        copy.error = error
        copy.updatedAt = Date()
        return copy
    }
    
    /// Прерывание
    public func interrupting(reason: String) -> TransferJob {
        var copy = self
        copy.state = .interrupted(reason: reason)
        copy.error = .connectionLost(reason)
        copy.updatedAt = Date()
        return copy
    }
    
    /// Отмена
    public func cancelling() -> TransferJob {
        var copy = self
        copy.state = .cancelled
        copy.error = .cancelled
        copy.updatedAt = Date()
        return copy
    }
}
