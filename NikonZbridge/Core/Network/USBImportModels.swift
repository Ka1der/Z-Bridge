import Foundation
import ImageCaptureCore
import CoreGraphics

/// Состояния жизненного цикла прямого USB-подключения к камере
public enum USBCameraConnectionState: Equatable, Sendable {
    case disconnected
    case discovered(name: String)
    case openingSession(name: String)
    case sessionOpened(name: String)
    case enumeratingCatalog(name: String, itemsFound: Int)
    case ready(name: String, totalItems: Int)
    case transferring(activeCount: Int, pendingCount: Int)
    case accessDenied(reason: String)
    case error(message: String)
    
    public var isConnected: Bool {
        switch self {
        case .sessionOpened, .enumeratingCatalog, .ready, .transferring:
            return true
        default:
            return false
        }
    }
    
    public var isCatalogReady: Bool {
        switch self {
        case .ready, .transferring:
            return true
        default:
            return false
        }
    }
    
    public var isConnecting: Bool {
        switch self {
        case .discovered, .openingSession:
            return true
        default:
            return false
        }
    }
    
    public var cameraName: String? {
        switch self {
        case .discovered(let name),
             .openingSession(let name),
             .sessionOpened(let name),
             .enumeratingCatalog(let name, _),
             .ready(let name, _):
            return name
        default:
            return nil
        }
    }
    
    public var displayTitle: String {
        switch self {
        case .disconnected:
            return "USB кабель не подключен"
        case .discovered(let name):
            return "Обнаружена: \(name)"
        case .openingSession(let name):
            return "\(name): Открытие сессии..."
        case .sessionOpened(let name):
            return "\(name): Сессия открыта"
        case .enumeratingCatalog(let name, let count):
            return "\(name): Оглавление (\(count) файлов)..."
        case .ready(let name, let total):
            return "\(name): Готова (\(total) файлов)"
        case .transferring(let active, let pending):
            return "USB импорт: \(active) акт., \(pending) в очереди"
        case .accessDenied(let reason):
            return "Доступ к камере ограничен: \(reason)"
        case .error(let msg):
            return "Ошибка USB: \(msg)"
        }
    }
}

/// Режимы импорта фотографий с камеры по USB
public enum USBImportMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case onlyNew = "Только новые снимки"
    case selected = "Выбранные вручную"
    case allUnimported = "Все неимпортированные"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .onlyNew: return "camera.badge.ellipsis"
        case .selected: return "checkmark.circle"
        case .allUnimported: return "arrow.down.circle"
        }
    }
    
    public var descriptionText: String {
        switch self {
        case .onlyNew:
            return "Автоматически скачиваются только новые снимки, сделанные после подключения камеры (live tethering)"
        case .selected:
            return "Скачиваются только файлы, явно выбранные фотографом в браузере карты памяти"
        case .allUnimported:
            return "Пакетная загрузка всех файлов с карты памяти, которые ещё не сохранены в текущую сессию"
        }
    }
}

/// Статус импорта конкретного файла с камеры
public enum CameraFileImportStatus: Equatable, Sendable {
    case notImported
    case queued
    case importing(progress: Double)
    case imported
    case failed(error: String)
    
    public var isTerminal: Bool {
        switch self {
        case .imported, .failed: return true
        default: return false
        }
    }
}

/// Модель файла, находящегося на карте памяти камеры
public struct CameraFileItem: Identifiable, @unchecked Sendable {
    /// Надежный составной идентификатор объекта: cameraID_filename_fileSize_creationTimestamp
    public let id: String
    public let cameraFile: ICCameraFile?
    public let cameraID: String
    public let filename: String
    public let fileSize: Int64
    public let creationDate: Date?
    public let isRAW: Bool
    public let isInitialCatalog: Bool
    public var status: CameraFileImportStatus
    public var thumbnail: CGImage?
    public var rating: Int = 0
    public var colorTag: Int? = nil
    
    public init(
        cameraID: String,
        filename: String,
        fileSize: Int64,
        creationDate: Date? = nil,
        cameraFile: ICCameraFile? = nil,
        isInitialCatalog: Bool = false,
        status: CameraFileImportStatus = .notImported,
        thumbnail: CGImage? = nil,
        rating: Int = 0,
        colorTag: Int? = nil
    ) {
        self.cameraID = cameraID
        self.filename = filename
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.cameraFile = cameraFile
        self.isInitialCatalog = isInitialCatalog
        self.status = status
        self.thumbnail = thumbnail
        self.rating = rating
        self.colorTag = colorTag
        
        let ext = (filename as NSString).pathExtension.lowercased()
        self.isRAW = (ext == "nef" || ext == "nrw")
        
        let datePart = creationDate.map { String(Int64($0.timeIntervalSince1970)) } ?? "0"
        self.id = "\(cameraID)_\(filename)_\(fileSize)_\(datePart)"
    }
    
    public static func makeCompositeID(
        cameraID: String,
        filename: String,
        fileSize: Int64,
        creationDate: Date?
    ) -> String {
        let datePart = creationDate.map { String(Int64($0.timeIntervalSince1970)) } ?? "0"
        return "\(cameraID)_\(filename)_\(fileSize)_\(datePart)"
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// Режим фильтрации по формату файлов на карте памяти
public enum CameraFileFormatFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Все"
    case rawOnly = "Только RAW"
    case companionOnly = "Только Companion/JPEG"
    
    public var id: String { rawValue }
    
    public func matches(isRAW: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .rawOnly:
            return isRAW
        case .companionOnly:
            return !isRAW
        }
    }
}

/// Режим отображения содержимого карты памяти в окне импорта с камеры
public enum CameraBrowserViewMode: String, CaseIterable, Identifiable, Sendable {
    case list = "Список"
    case gallery = "Галерея"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .list: return "list.bullet"
        case .gallery: return "rectangle.bottomhalf.filled"
        }
    }
}

/// Статистика оглавления карты памяти
public struct CameraCatalogStats: Equatable, Sendable {
    public let totalCount: Int
    public let totalBytes: Int64
    public let unimportedCount: Int
    public let unimportedBytes: Int64
    public let importedCount: Int
    public let importedBytes: Int64
    public let inProgressCount: Int
    public let failedCount: Int
    
    public init(
        totalCount: Int = 0,
        totalBytes: Int64 = 0,
        unimportedCount: Int = 0,
        unimportedBytes: Int64 = 0,
        importedCount: Int = 0,
        importedBytes: Int64 = 0,
        inProgressCount: Int = 0,
        failedCount: Int = 0
    ) {
        self.totalCount = totalCount
        self.totalBytes = totalBytes
        self.unimportedCount = unimportedCount
        self.unimportedBytes = unimportedBytes
        self.importedCount = importedCount
        self.importedBytes = importedBytes
        self.inProgressCount = inProgressCount
        self.failedCount = failedCount
    }
    
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public var formattedUnimportedSize: String {
        ByteCountFormatter.string(fromByteCount: unimportedBytes, countStyle: .file)
    }
    
    public static func calculate(from files: [CameraFileItem]) -> CameraCatalogStats {
        var total = 0
        var totalB: Int64 = 0
        var unimp = 0
        var unimpB: Int64 = 0
        var imp = 0
        var impB: Int64 = 0
        var prog = 0
        var failed = 0
        
        for file in files {
            total += 1
            totalB += file.fileSize
            switch file.status {
            case .notImported:
                unimp += 1
                unimpB += file.fileSize
            case .queued, .importing:
                prog += 1
            case .imported:
                imp += 1
                impB += file.fileSize
            case .failed:
                failed += 1
            }
        }
        
        return CameraCatalogStats(
            totalCount: total,
            totalBytes: totalB,
            unimportedCount: unimp,
            unimportedBytes: unimpB,
            importedCount: imp,
            importedBytes: impB,
            inProgressCount: prog,
            failedCount: failed
        )
    }
}

