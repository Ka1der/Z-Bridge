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
    
    public init(
        cameraID: String,
        filename: String,
        fileSize: Int64,
        creationDate: Date? = nil,
        cameraFile: ICCameraFile? = nil,
        isInitialCatalog: Bool = false,
        status: CameraFileImportStatus = .notImported,
        thumbnail: CGImage? = nil
    ) {
        self.cameraID = cameraID
        self.filename = filename
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.cameraFile = cameraFile
        self.isInitialCatalog = isInitialCatalog
        self.status = status
        self.thumbnail = thumbnail
        
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
