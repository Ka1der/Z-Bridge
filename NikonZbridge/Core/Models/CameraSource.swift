import Foundation

/// Тип физического или сетевого транспорта для подключения к камере
public enum CameraTransportType: String, Sendable, Codable, Hashable {
    /// Прямое подключение по кабелю USB-C (MTP / PTP через ImageCaptureCore)
    case usb
    /// Сетевое подключение к встроенному FTP-серверу (Wi-Fi или проводной адаптер USB-LAN)
    case ftp
    
    /// Позволяет ли транспорт приложению запрашивать скачивание файла по своей инициативе (Pull)
    public var canInitiateDownload: Bool {
        switch self {
        case .usb: return true
        case .ftp: return false
        }
    }
    
    /// Поддерживает ли транспорт автоматический повтор загрузки приложением при ошибке
    public var supportsAppRetry: Bool {
        switch self {
        case .usb: return true
        case .ftp: return false
        }
    }
    
    public var displayName: String {
        switch self {
        case .usb: return "USB (Кабель)"
        case .ftp: return "FTP (Сеть)"
        }
    }
}

/// Источник снимков (подключенная камера)
public struct CameraSource: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public var model: String?
    public let transportType: CameraTransportType
    public var customName: String?
    
    public var displayName: String {
        if let custom = customName, !custom.isEmpty {
            return custom
        }
        if let model = model, !model.isEmpty {
            return "\(model) (\(transportType.displayName))"
        }
        return "Nikon Z (\(transportType.displayName))"
    }
    
    public init(
        id: String,
        model: String? = nil,
        transportType: CameraTransportType,
        customName: String? = nil
    ) {
        self.id = id
        self.model = model
        self.transportType = transportType
        self.customName = customName
    }
}
