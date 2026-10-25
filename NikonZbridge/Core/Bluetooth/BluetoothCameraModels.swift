import Foundation
import CoreBluetooth

/// Состояние Bluetooth-подсистемы и соединения с камерой
public enum BluetoothConnectionState: String, Sendable, Equatable {
    case poweredOff = "Bluetooth выключен"
    case unauthorized = "Нет разрешения Bluetooth"
    case unsupported = "Bluetooth не поддерживается"
    case idle = "Готов к поиску"
    case scanning = "Поиск камер Nikon Z..."
    case connecting = "Подключение..."
    case connected = "Подключено по Bluetooth"
    case ready = "На связи (BLE)"
    
    public var isConnectingOrConnected: Bool {
        self == .connecting || self == .connected || self == .ready
    }
}

/// Идентификаторы и GATT-константы протокола Nikon BLE
public enum NikonBLEConstants {
    /// Bluetooth SIG Company Identifier компании Nikon Corporation
    public static let companyIdentifier: UInt16 = 0x0399
    
    /// Основной сервис удалённого управления камерой Nikon LSS/Remote
    public static let serviceRemote = CBUUID(string: "0000DE00-3DD4-4255-8D62-6DC7B9BD5561")
    
    /// Характеристика сопряжения и аутентификации
    public static let charPairing = CBUUID(string: "00002000-3DD4-4255-8D62-6DC7B9BD5561")
    
    /// Характеристика имени клиентского устройства
    public static let charClientName = CBUUID(string: "00002002-3DD4-4255-8D62-6DC7B9BD5561")
    
    /// Характеристика синхронизации точного времени
    public static let charTimeSync = CBUUID(string: "00002006-3DD4-4255-8D62-6DC7B9BD5561")
    
    /// Характеристика передачи геоданных (GPS / NMEA)
    public static let charLocation = CBUUID(string: "00002007-3DD4-4255-8D62-6DC7B9BD5561")
    
    /// Характеристика статуса затвора и телеметрии камеры
    public static let charStatus = CBUUID(string: "00002008-3DD4-4255-8D62-6DC7B9BD5561")
    
    /// Стандартный сервис батареи (Bluetooth SIG)
    public static let serviceBattery = CBUUID(string: "180F")
    public static let charBatteryLevel = CBUUID(string: "2A19")
    
    /// Стандартный сервис информации об устройстве
    public static let serviceDeviceInfo = CBUUID(string: "180A")
    public static let charModelNumber = CBUUID(string: "2A24")
    public static let charManufacturer = CBUUID(string: "2A29")
    public static let charFirmwareRevision = CBUUID(string: "2A26")
}

/// Модель обнаруженной или сопряженной камеры Nikon по Bluetooth Low Energy
public struct BluetoothCameraDevice: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public var modelName: String
    public var rssi: Int
    public var isNikonVerified: Bool
    public var batteryLevel: Int?
    public var lastSeen: Date
    
    public init(
        id: UUID,
        name: String,
        modelName: String = "Nikon Z",
        rssi: Int = -70,
        isNikonVerified: Bool = true,
        batteryLevel: Int? = nil,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.rssi = rssi
        self.isNikonVerified = isNikonVerified
        self.batteryLevel = batteryLevel
        self.lastSeen = lastSeen
    }
    
    /// Количество делений сигнала (1–4)
    public var signalBars: Int {
        if rssi >= -60 { return 4 }
        if rssi >= -75 { return 3 }
        if rssi >= -85 { return 2 }
        return 1
    }
    
    /// Читаемое описание уровня сигнала
    public var signalDescription: String {
        switch signalBars {
        case 4: return "Отличный (\(rssi) dBm)"
        case 3: return "Хороший (\(rssi) dBm)"
        case 2: return "Средний (\(rssi) dBm)"
        default: return "Слабый (\(rssi) dBm)"
        }
    }
    
    public static func == (lhs: BluetoothCameraDevice, rhs: BluetoothCameraDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
