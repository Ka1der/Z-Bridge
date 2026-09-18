import Foundation

/// Место назначения экспорта
public enum ExportDestination: Sendable, Codable, Hashable {
    case photoLibrary(albumName: String? = nil)
    case directory(url: URL, bookmarkData: Data? = nil)
    case externalDrive(url: URL, volumeName: String, bookmarkData: Data? = nil)
    case shareSheet
    
    public static var photoLibrary: ExportDestination {
        .photoLibrary(albumName: nil)
    }
    
    public static func directory(url: URL) -> ExportDestination {
        .directory(url: url, bookmarkData: nil)
    }
    
    public var displayName: String {
        switch self {
        case .photoLibrary(let album):
            if let album = album, !album.isEmpty {
                return "Фото: «\(album)»"
            }
            return "Медиатека «Фото»"
        case .directory(let url, _):
            return "Папка: \(url.lastPathComponent)"
        case .externalDrive(let url, let volumeName, _):
            return "Внешний SSD «\(volumeName)»: \(url.lastPathComponent)"
        case .shareSheet:
            return "Поделиться (Share Sheet)"
        }
    }
    
    public var targetURL: URL? {
        switch self {
        case .directory(let url, _): return url
        case .externalDrive(let url, _, _): return url
        default: return nil
        }
    }
    
    public var bookmarkData: Data? {
        switch self {
        case .directory(_, let data): return data
        case .externalDrive(_, _, let data): return data
        default: return nil
        }
    }
}

/// Выбор форматов оригиналов для экспорта
public enum ExportFormatSelection: String, CaseIterable, Identifiable, Sendable, Codable {
    case both = "RAW + JPEG/HEIF"
    case rawOnly = "Только RAW"
    case companionOnly = "Только JPEG / HEIF"
    
    public var id: String { rawValue }
    
    public func shouldExport(asset: MediaAsset) -> Bool {
        switch self {
        case .both:
            return true
        case .rawOnly:
            return asset.isRAW
        case .companionOnly:
            return !asset.isRAW
        }
    }
}

/// Стратегия разрешения конфликтов имён файлов
public enum NameConflictStrategy: String, CaseIterable, Identifiable, Sendable, Codable {
    case rename = "Переименовать (уникальный суффикс)"
    case overwrite = "Перезаписать существующий"
    case skip = "Пропустить файл"
    
    public var id: String { rawValue }
}

/// Статус экспорта конкретного файла в очереди
public enum ExportItemStatus: Sendable, Codable, Hashable {
    case pending
    case exporting(progress: Double)
    case success(destinationURL: URL)
    case failed(reason: String)
    case skipped
    
    public var isTerminal: Bool {
        switch self {
        case .success, .failed, .skipped: return true
        default: return false
        }
    }
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Отдельный элемент очереди экспорта
public struct ExportItem: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var asset: MediaAsset
    public var status: ExportItemStatus
    public var exportedBytes: Int64
    public var destinationURL: URL?
    public var errorMessage: String?
    
    public var filename: String {
        asset.filename
    }
    
    public var fileSize: Int64 {
        asset.fileSize
    }
    
    public init(
        id: UUID = UUID(),
        asset: MediaAsset,
        status: ExportItemStatus = .pending,
        exportedBytes: Int64 = 0,
        destinationURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.asset = asset
        self.status = status
        self.exportedBytes = exportedBytes
        self.destinationURL = destinationURL
        self.errorMessage = errorMessage
    }
}

/// Состояние выполнения экспорта
public enum ExportState: Sendable, Codable, Hashable {
    case pending
    case inProgress(progress: Double)
    case completed(exportedURLs: [URL])
    case failed(reason: String)
    case cancelled
    
    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
    
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

/// Результат экспорта
public struct ExportResult: Sendable, Codable, Hashable {
    public let totalCount: Int
    public let successCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    public let exportedURLs: [URL]
    public let exportedXMPURLs: [URL]
    public let manifestURL: URL?
    public let reportURL: URL?
    public let errorMessage: String?
    
    public var isAllSuccessful: Bool {
        failedCount == 0 && successCount == totalCount
    }
    
    public init(
        totalCount: Int,
        successCount: Int,
        failedCount: Int,
        skippedCount: Int = 0,
        exportedURLs: [URL] = [],
        exportedXMPURLs: [URL] = [],
        manifestURL: URL? = nil,
        reportURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.totalCount = totalCount
        self.successCount = successCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.exportedURLs = exportedURLs
        self.exportedXMPURLs = exportedXMPURLs
        self.manifestURL = manifestURL
        self.reportURL = reportURL
        self.errorMessage = errorMessage
    }
}

/// Задание на экспорт набора файлов
public struct ExportJob: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let assetIDs: [UUID]
    public var items: [ExportItem]
    public let destination: ExportDestination
    public let formatSelection: ExportFormatSelection
    public let conflictStrategy: NameConflictStrategy
    public let includeXMPSidecars: Bool
    public let sidecarNamingConvention: XMPSidecarNamingConvention
    public let includeSessionManifest: Bool
    public let sessionMetadata: SessionMetadata?
    public var state: ExportState
    public var result: ExportResult?
    public var totalBytes: Int64
    public var exportedBytes: Int64
    public let createdAt: Date
    public var completedAt: Date?
    
    public var progressPercentage: Double {
        guard totalBytes > 0 else {
            let total = items.count
            guard total > 0 else { return 0.0 }
            let done = items.filter { $0.status.isTerminal }.count
            return Double(done) / Double(total)
        }
        return min(1.0, max(0.0, Double(exportedBytes) / Double(totalBytes)))
    }
    
    public var successItemsCount: Int {
        items.filter { $0.status.isSuccess }.count
    }
    
    public var failedItemsCount: Int {
        items.filter { $0.status.isFailed }.count
    }
    
    public func failedItems() -> [ExportItem] {
        items.filter { $0.status.isFailed }
    }
    
    public init(
        id: UUID = UUID(),
        assetIDs: [UUID] = [],
        items: [ExportItem] = [],
        destination: ExportDestination,
        formatSelection: ExportFormatSelection = .both,
        conflictStrategy: NameConflictStrategy = .rename,
        includeXMPSidecars: Bool = true,
        sidecarNamingConvention: XMPSidecarNamingConvention = .standardBasename,
        includeSessionManifest: Bool = true,
        sessionMetadata: SessionMetadata? = nil,
        state: ExportState = .pending,
        result: ExportResult? = nil,
        totalBytes: Int64 = 0,
        exportedBytes: Int64 = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.assetIDs = assetIDs.isEmpty ? items.map(\.asset.id) : assetIDs
        self.items = items
        self.destination = destination
        self.formatSelection = formatSelection
        self.conflictStrategy = conflictStrategy
        self.includeXMPSidecars = includeXMPSidecars
        self.sidecarNamingConvention = sidecarNamingConvention
        self.includeSessionManifest = includeSessionManifest
        self.sessionMetadata = sessionMetadata
        self.state = state
        self.result = result
        self.totalBytes = totalBytes > 0 ? totalBytes : items.reduce(0) { $0 + $1.fileSize }
        self.exportedBytes = exportedBytes
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
    
    public init(
        destination: ExportDestination,
        items: [ExportItem] = [],
        formatSelection: ExportFormatSelection = .both,
        conflictStrategy: NameConflictStrategy = .rename,
        includeXMPSidecars: Bool = true,
        sidecarNamingConvention: XMPSidecarNamingConvention = .standardBasename,
        includeSessionManifest: Bool = true,
        sessionMetadata: SessionMetadata? = nil,
        id: UUID = UUID(),
        state: ExportState = .pending,
        result: ExportResult? = nil
    ) {
        self.id = id
        self.assetIDs = items.map(\.asset.id)
        self.items = items
        self.destination = destination
        self.formatSelection = formatSelection
        self.conflictStrategy = conflictStrategy
        self.includeXMPSidecars = includeXMPSidecars
        self.sidecarNamingConvention = sidecarNamingConvention
        self.includeSessionManifest = includeSessionManifest
        self.sessionMetadata = sessionMetadata
        self.state = state
        self.result = result
        self.totalBytes = items.reduce(0) { $0 + $1.fileSize }
        self.exportedBytes = 0
        self.createdAt = Date()
        self.completedAt = nil
    }
}
