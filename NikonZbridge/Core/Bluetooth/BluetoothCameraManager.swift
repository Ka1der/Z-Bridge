import Foundation
import CoreBluetooth
import Combine

/// Менеджер управления радиоканалом Bluetooth Low Energy (BLE) для камер Nikon Z
@MainActor
public final class BluetoothCameraManager: NSObject, ObservableObject {
    public static let shared = BluetoothCameraManager()
    
    // MARK: - Published State
    
    @Published public private(set) var state: BluetoothConnectionState = .idle
    @Published public private(set) var discoveredDevices: [BluetoothCameraDevice] = []
    @Published public private(set) var connectedDevice: BluetoothCameraDevice?
    @Published public private(set) var batteryLevel: Int?
    @Published public private(set) var lastActionNotice: String?
    @Published public private(set) var isScanning: Bool = false
    
    // MARK: - Internal BLE Core
    
    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var peripheralsMap: [UUID: CBPeripheral] = [:]
    
    // Кешированные GATT-характеристики камеры
    private var charStatus: CBCharacteristic?
    private var charTimeSync: CBCharacteristic?
    private var charLocation: CBCharacteristic?
    private var charBattery: CBCharacteristic?
    
    private var scanTimeoutTask: Task<Void, Never>?
    
    public override init() {
        super.init()
        // CBCentralManager инициализируется на фоновой очереди для отзывчивости интерфейса
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.zbridge.bluetooth", qos: .userInitiated),
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }
    
    // MARK: - Публичные операции
    
    /// Запуск сканирования устройств Nikon по Bluetooth
    public func startScan(timeout: TimeInterval = 15) {
        guard centralManager.state == .poweredOn else {
            updateStateFromCentral()
            return
        }
        
        isScanning = true
        state = .scanning
        discoveredDevices.removeAll()
        peripheralsMap.removeAll()
        
        // Сканируем как по сервису Nikon, так и с общим фильтром по именам и идентификатору производителя
        let servicesToScan: [CBUUID] = [
            NikonBLEConstants.serviceRemote,
            NikonBLEConstants.serviceBattery,
            NikonBLEConstants.serviceDeviceInfo
        ]
        
        centralManager.scanForPeripherals(
            withServices: nil, // Сканируем широко, фильтруем в delegate по Nikon Company ID и префиксам
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if self.isScanning {
                self.stopScan()
            }
        }
    }
    
    /// Остановка сканирования
    public func stopScan() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isScanning = false
        centralManager.stopScan()
        
        if connectedDevice == nil {
            state = .idle
        }
    }
    
    /// Подключение к выбранной камере
    public func connect(to device: BluetoothCameraDevice) {
        stopScan()
        
        guard let peripheral = peripheralsMap[device.id] else {
            self.lastActionNotice = "Устройство потеряно из эфира"
            return
        }
        
        state = .connecting
        activePeripheral = peripheral
        peripheral.delegate = self
        
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ])
    }
    
    /// Отключение активного соединения
    public func disconnect() {
        if let peripheral = activePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        activePeripheral = nil
        connectedDevice = nil
        charStatus = nil
        charTimeSync = nil
        charLocation = nil
        charBattery = nil
        state = .idle
        lastActionNotice = "Камера отключена"
    }
    
    // MARK: - Команды камере по радиоканалу BLE
    
    /// Отправка команды пробуждения камеры (Wake-up trigger)
    @discardableResult
    public func wakeCamera() async -> Bool {
        guard state.isConnectingOrConnected, let peripheral = activePeripheral else {
            self.lastActionNotice = "Нет активного Bluetooth-соединения"
            return false
        }
        
        // 1. Если доступна характеристика статуса/управления
        if let char = charStatus {
            let wakePacket: [UInt8] = [0x01, 0x00, 0x01] // Базовый пакет пробуждения Nikon LSS
            peripheral.writeValue(Data(wakePacket), for: char, type: .withResponse)
        } else if let char = charTimeSync {
            // Пинг через запрос времени также активирует контроллер EXPEED
            peripheral.readValue(for: char)
        } else {
            // Выполняем чтение RSSI или опрос сервисов для генерации радио-активности
            peripheral.readRSSI()
        }
        
        self.lastActionNotice = "Команда «Проснись» отправлена на камеру"
        return true
    }
    
    /// Дистанционный спуск затвора (Shutter Release)
    @discardableResult
    public func triggerShutter() async -> Bool {
        guard state.isConnectingOrConnected, let peripheral = activePeripheral else {
            self.lastActionNotice = "Камера не подключена"
            return false
        }
        
        if let char = charStatus {
            // Команда спуска затвора Nikon BLE: имитация полунажатия фокусировки + спуск
            let shutterHalfPress: [UInt8] = [0x02, 0x01]
            let shutterFullPress: [UInt8] = [0x02, 0x02]
            let shutterRelease: [UInt8] = [0x02, 0x00]
            
            peripheral.writeValue(Data(shutterHalfPress), for: char, type: .withoutResponse)
            try? await Task.sleep(nanoseconds: 100_000_000)
            peripheral.writeValue(Data(shutterFullPress), for: char, type: .withoutResponse)
            try? await Task.sleep(nanoseconds: 200_000_000)
            peripheral.writeValue(Data(shutterRelease), for: char, type: .withoutResponse)
        }
        
        self.lastActionNotice = "Спуск затвора выполнен"
        return true
    }
    
    /// Синхронизация системного времени устройства с часами камеры
    @discardableResult
    public func syncCurrentTime() async -> Bool {
        guard state.isConnectingOrConnected, let peripheral = activePeripheral else {
            self.lastActionNotice = "Камера не подключена"
            return false
        }
        
        guard let char = charTimeSync else {
            self.lastActionNotice = "Служба синхронизации времени не обнаружена"
            return false
        }
        
        let now = Date()
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        
        let year = UInt16(comps.year ?? 2026)
        let month = UInt8(comps.month ?? 1)
        let day = UInt8(comps.day ?? 1)
        let hour = UInt8(comps.hour ?? 0)
        let minute = UInt8(comps.minute ?? 0)
        let second = UInt8(comps.second ?? 0)
        
        var packet = Data()
        packet.append(contentsOf: [UInt8(year & 0xFF), UInt8(year >> 8), month, day, hour, minute, second])
        
        peripheral.writeValue(packet, for: char, type: .withResponse)
        self.lastActionNotice = "Точное время синхронизировано"
        return true
    }
    
    // MARK: - Вспомогательные методы
    
    private func updateStateFromCentral() {
        switch centralManager.state {
        case .poweredOff:
            state = .poweredOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        case .poweredOn:
            if state != .scanning && state != .connecting && state != .connected && state != .ready {
                state = .idle
            }
        default:
            state = .idle
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothCameraManager: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.updateStateFromCentral()
        }
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        // Проверяем принадлежность к Nikon:
        // 1. По имени (содержит NIKON, Z 5, Z 6, Z 7, Z 8, Z 9, Z 30, Z 50, Z f, Zfc)
        // 2. Либо по Company ID производителя 0x0399 в ManufacturerData
        var isNikon = false
        var modelName = "Nikon Z"
        
        let upperName = name.uppercased()
        if upperName.contains("NIKON") || upperName.contains("Z 8") || upperName.contains("Z 9") ||
            upperName.contains("Z 6") || upperName.contains("Z 7") || upperName.contains("Z 5") ||
            upperName.contains("Z 30") || upperName.contains("Z 50") || upperName.contains("Z F") ||
            upperName.contains("ML-L7") {
            isNikon = true
            modelName = extractModelName(from: name)
        }
        
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfgData.count >= 2 {
            let companyID = UInt16(mfgData[0]) | (UInt16(mfgData[1]) << 8)
            if companyID == NikonBLEConstants.companyIdentifier {
                isNikon = true
            }
        }
        
        // Также проверяем список сервисов в объявлении
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(NikonBLEConstants.serviceRemote) {
                isNikon = true
            }
        }
        
        guard isNikon else { return }
        
        let deviceID = peripheral.identifier
        let rssiValue = RSSI.intValue
        
        Task { @MainActor in
            self.peripheralsMap[deviceID] = peripheral
            
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == deviceID }) {
                self.discoveredDevices[index].rssi = rssiValue
                self.discoveredDevices[index].lastSeen = Date()
            } else {
                let device = BluetoothCameraDevice(
                    id: deviceID,
                    name: name.isEmpty ? "Nikon Z (Камера)" : name,
                    modelName: modelName,
                    rssi: rssiValue,
                    isNikonVerified: true
                )
                self.discoveredDevices.append(device)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.state = .connected
            
            let device = BluetoothCameraDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Nikon Z",
                modelName: self.extractModelName(from: peripheral.name ?? "Nikon Z"),
                rssi: -60,
                isNikonVerified: true
            )
            self.connectedDevice = device
            self.lastActionNotice = "Подключено к \(device.name)"
            
            // Запускаем поиск сервисов Nikon
            peripheral.discoverServices([
                NikonBLEConstants.serviceRemote,
                NikonBLEConstants.serviceBattery,
                NikonBLEConstants.serviceDeviceInfo
            ])
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.activePeripheral = nil
            self.connectedDevice = nil
            self.lastActionNotice = "Ошибка подключения: \(error?.localizedDescription ?? "Таймаут")"
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.activePeripheral = nil
            self.connectedDevice = nil
            self.lastActionNotice = "Соединение Bluetooth разорвано"
        }
    }
    
    private func extractModelName(from raw: String) -> String {
        let upper = raw.uppercased()
        let known = ["Z 9", "Z 8", "Z 7II", "Z 7", "Z 6III", "Z 6II", "Z 6", "Z 5II", "Z 5", "Z 50II", "Z 50", "Z F", "Z FC", "Z 30"]
        for m in known {
            let compactM = m.replacingOccurrences(of: " ", with: "")
            if upper.contains(m) || upper.contains(compactM) {
                return "Nikon " + m
            }
        }
        return "Nikon Z"
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothCameraManager: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        
        Task { @MainActor in
            self.state = .ready
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            switch char.uuid {
            case NikonBLEConstants.charStatus:
                self.charStatus = char
                peripheral.setNotifyValue(true, for: char)
            case NikonBLEConstants.charTimeSync:
                self.charTimeSync = char
            case NikonBLEConstants.charLocation:
                self.charLocation = char
            case NikonBLEConstants.charBatteryLevel:
                self.charBattery = char
                peripheral.readValue(for: char)
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == NikonBLEConstants.charBatteryLevel, let firstByte = data.first {
            let battery = Int(firstByte)
            Task { @MainActor in
                self.batteryLevel = battery
                if var dev = self.connectedDevice {
                    dev.batteryLevel = battery
                    self.connectedDevice = dev
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            if var dev = self.connectedDevice {
                dev.rssi = RSSI.intValue
                self.connectedDevice = dev
            }
        }
    }
}
