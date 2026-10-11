import Foundation
import Network
import Combine

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct Stage7VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 7: МАСТЕР ПОДКЛЮЧЕНИЯ И СОВМЕСТИМОСТЬ ===")
        
        let suite = Stage7ConnectionWizardVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 7 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage7ConnectionWizardVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage7Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("stage7_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        try await testCameraModelMatrixCompleteness()
        try await testSupportedTransportsResolutionPerModel()
        try await testModelSpecificStepByStepInstructions()
        try await testDirectUSBVersusUSBEthernetDistinction()
        try await testCompatibilityMatrixIntegrityAndUntestedFlag()
        try await testCompatibilityMatrixFilteringAndQueries()
        try await testConnectionReadinessCheckerAndEndpointMatching()
        try await testEndToEndTestProbeFileExecution()
    }
    
    // MARK: - 1. Полнота охвата моделей линейки Nikon Z
    func testCameraModelMatrixCompleteness() async throws {
        print("\n[1/8] Тест полноты охвата моделей линейки Nikon Z...")
        
        let allModels = NikonCameraModel.allCases
        verify(allModels.count >= 12, "Должны присутствовать не менее 12 моделей Nikon Z")
        
        let expectedNames = [
            "Nikon Z 9", "Nikon Z 8", "Nikon Z 6III", "Nikon Z f",
            "Nikon Z 7II", "Nikon Z 6II", "Nikon Z 7", "Nikon Z 6",
            "Nikon Z 5", "Nikon Z 50", "Nikon Z 30", "Nikon Z fc"
        ]
        
        for name in expectedNames {
            verify(allModels.contains { $0.fullName == name }, "Модель \(name) должна быть в реестре")
        }
        
        // Проверка поколений процессоров
        verify(NikonCameraModel.z9.processor == .expeed7, "Z9 - Expeed 7")
        verify(NikonCameraModel.z8.processor == .expeed7, "Z8 - Expeed 7")
        verify(NikonCameraModel.z6iii.processor == .expeed7, "Z6 III - Expeed 7")
        verify(NikonCameraModel.zf.processor == .expeed7, "Zf - Expeed 7")
        verify(NikonCameraModel.z7ii.processor == .dualExpeed6, "Z7 II - Dual Expeed 6")
        verify(NikonCameraModel.z6ii.processor == .dualExpeed6, "Z6 II - Dual Expeed 6")
        verify(NikonCameraModel.z7.processor == .expeed6, "Z7 - Expeed 6")
        verify(NikonCameraModel.z50.processor == .expeed6, "Z50 - Expeed 6")
        
        // Проверка специфических аппаратных портов
        verify(NikonCameraModel.z9.hasBuiltInRJ45 == true, "Z9 должна иметь встроенный RJ-45")
        verify(NikonCameraModel.z8.hasBuiltInRJ45 == false, "Z8 не имеет встроенного RJ-45")
        verify(NikonCameraModel.z8.hasDualUSBPorts == true, "Z8 имеет двойной порт USB-C")
        verify(NikonCameraModel.z50.usbPortType.contains("Micro-USB"), "Z50 использует Micro-USB")
        
        print("  ✓ Все модели Nikon Z с их характеристиками процессоров и портов верифицированы")
    }
    
    // MARK: - 2. Разрешение поддерживаемых транспортов по моделям
    func testSupportedTransportsResolutionPerModel() async throws {
        print("\n[2/8] Тест разрешения поддерживаемых транспортов по моделям...")
        
        // Z9
        let z9Transports = NikonCameraModel.z9.supportedTransports
        verify(z9Transports.contains(.builtInEthernet), "Z9 поддерживает встроенный Ethernet")
        verify(z9Transports.contains(.directUSB), "Z9 поддерживает прямой USB")
        verify(z9Transports.contains(.builtInWiFiFTP), "Z9 поддерживает Wi-Fi")
        verify(!z9Transports.contains(.usbToEthernet), "Z9 не требует USB-Ethernet адаптера")
        
        // Z8
        let z8Transports = NikonCameraModel.z8.supportedTransports
        verify(!z8Transports.contains(.builtInEthernet), "Z8 не имеет встроенного RJ45")
        verify(z8Transports.contains(.usbToEthernet), "Z8 поддерживает USB-C Ethernet адаптер")
        verify(z8Transports.contains(.directUSB), "Z8 поддерживает прямой USB")
        
        // Z7 II / Z6 II
        let z7iiTransports = NikonCameraModel.z7ii.supportedTransports
        verify(z7iiTransports.contains(.wt7Transmitter), "Z7 II поддерживает WT-7")
        verify(z7iiTransports.contains(.directUSB), "Z7 II поддерживает прямой USB")
        
        // Z50
        let z50Transports = NikonCameraModel.z50.supportedTransports
        verify(z50Transports.contains(.directUSB), "Z50 поддерживает прямой USB")
        verify(!z50Transports.contains(.builtInEthernet), "Z50 не поддерживает проводную сеть")
        
        print("  ✓ Поддерживаемые интерфейсы строго соответствуют аппаратуре каждой модели")
    }
    
    // MARK: - 3. Точные пошаговые инструкции под модель и транспорт
    func testModelSpecificStepByStepInstructions() async throws {
        print("\n[3/8] Тест генерации точных пошаговых инструкций для выбранной камеры...")
        
        // 1. Z8 + USB-Ethernet
        let z8WiredSteps = NikonCameraModel.z8.instructions(for: .usbToEthernet)
        verify(z8WiredSteps.count >= 3, "Инструкция Z8 USB-LAN должна содержать как минимум 3 шага")
        verify(z8WiredSteps.contains { $0.menuPathRu.contains("USB-LAN") }, "Путь должен содержать меню USB-LAN")
        verify(z8WiredSteps.contains { $0.tip?.contains("ВЕРХНЕМ") == true || $0.details.contains("порт") }, "Упоминание порта данных Z8")
        
        // 2. Z9 + Встроенный Ethernet
        let z9EthernetSteps = NikonCameraModel.z9.instructions(for: .builtInEthernet)
        verify(z9EthernetSteps.contains { $0.title.contains("RJ-45") }, "Упоминание разъёма RJ-45 Z9")
        verify(z9EthernetSteps.contains { $0.details.contains("2121") }, "Упоминание порта 2121")
        
        // 3. Z50 + Прямой USB
        let z50USBSteps = NikonCameraModel.z50.instructions(for: .directUSB)
        verify(z50USBSteps.contains { $0.tip?.contains("Micro-USB") == true || $0.details.contains("Micro-USB") }, "Предупреждение о кабеле Micro-USB на Z 50")
        
        // 4. Проверка двуязычности путей в меню (RU и EN)
        for step in z8WiredSteps {
            verify(!step.menuPathRu.isEmpty, "Путь на русском не пуст")
            verify(!step.menuPathEn.isEmpty, "Путь на английском не пуст")
            verify(!step.title.isEmpty, "Заголовок не пуст")
        }
        
        print("  ✓ Точные пошаговые инструкции с двуязычными путями меню сформированы")
    }
    
    // MARK: - 4. Разграничение прямого USB и USB-Ethernet
    func testDirectUSBVersusUSBEthernetDistinction() async throws {
        print("\n[4/8] Тест чёткого разграничения прямого USB и USB-Ethernet...")
        
        let usb = NikonConnectionTransport.directUSB
        let usbEthernet = NikonConnectionTransport.usbToEthernet
        let builtInEthernet = NikonConnectionTransport.builtInEthernet
        let wifi = NikonConnectionTransport.builtInWiFiFTP
        
        // Прямой USB: проводной, НЕ FTP (PTP/MTP), не требует настройки сети
        verify(usb.isWired == true, "Прямой USB является проводным")
        verify(usb.isFTP == false, "Прямой USB НЕ является FTP протоколом")
        
        // USB-Ethernet: проводной, работает по протоколу FTP, требует сетевой настройки
        verify(usbEthernet.isWired == true, "USB-Ethernet является проводным")
        verify(usbEthernet.isFTP == true, "USB-Ethernet использует FTP-протокол")
        
        // Встроенный Ethernet: проводной, FTP
        verify(builtInEthernet.isWired == true, "Встроенный Ethernet проводной")
        verify(builtInEthernet.isFTP == true, "Встроенный Ethernet использует FTP")
        
        // Wi-Fi: беспроводной, FTP
        verify(wifi.isWired == false, "Wi-Fi беспроводной")
        verify(wifi.isFTP == true, "Wi-Fi использует FTP")
        
        print("  ✓ Различия прямого USB (PTP) и USB-Ethernet (Host LAN FTP) строго разграничены")
    }
    
    // MARK: - 5. Целостность матрицы совместимости и обязательная пометка untested
    func testCompatibilityMatrixIntegrityAndUntestedFlag() async throws {
        print("\n[5/8] Тест матрицы совместимости и обязательной маркировки непроверенных сочетаний...")
        
        let matrix = NikonCompatibilityMatrix.shared
        let records = matrix.allRecords
        
        verify(!records.isEmpty, "Матрица совместимости не пуста")
        
        // Проверяем наличие статуса verified для флагманов
        let z9Ethernet = matrix.record(for: .z9, transport: .builtInEthernet)
        verify(z9Ethernet?.verificationStatus == .verified, "Z9 Ethernet проверен в железе")
        
        let z8USBLan = matrix.record(for: .z8, transport: .usbToEthernet)
        verify(z8USBLan?.verificationStatus == .verified, "Z8 USB-LAN проверен в железе")
        
        // Проверяем, что непроверенные сочетания ОБЯЗАТЕЛЬНО имеют статус .untested
        let z50WiFi = matrix.record(for: .z50, transport: .builtInWiFiFTP)
        verify(z50WiFi != nil, "Запись Z50 Wi-Fi существует")
        verify(z50WiFi?.verificationStatus == .untested, "Z50 Wi-Fi ОБЯЗАН быть помечен как .untested")
        verify(z50WiFi?.notes.contains("ВНИМАНИЕ") == true, "Запись содержит предупреждение для фотографа")
        
        let zfUSBLan = matrix.record(for: .zf, transport: .usbToEthernet)
        verify(zfUSBLan?.verificationStatus == .untested, "Zf USB-LAN помечен как .untested")
        
        // Проверяем заполненность всех полей
        for rec in records {
            verify(!rec.firmwareVersion.isEmpty, "Версия прошивки заполнена")
            verify(!rec.notes.isEmpty, "Примечания заполнены")
            verify(!rec.capabilities.isEmpty, "Список возможностей не пуст")
        }
        
        print("  ✓ Все непроверенные сочетания честно помечены статусом .untested")
    }
    
    // MARK: - 6. Фильтрация и поиск по матрице совместимости
    func testCompatibilityMatrixFilteringAndQueries() async throws {
        print("\n[6/8] Тест фильтрации и выборок матрицы совместимости...")
        
        let matrix = NikonCompatibilityMatrix.shared
        
        // Фильтр по модели
        let z8Records = matrix.records(for: .z8)
        verify(z8Records.count == 3, "Для Z8 должны быть 3 записи (USB, USB-Ethernet, Wi-Fi)")
        for rec in z8Records {
            verify(rec.model == .z8, "Все записи относятся к Z8")
        }
        
        // Фильтр по статусу
        let verifiedRecords = matrix.records(with: .verified)
        verify(!verifiedRecords.isEmpty, "Список проверенных в железе не пуст")
        
        let untestedRecords = matrix.records(with: .untested)
        verify(!untestedRecords.isEmpty, "Список непроверенных не пуст (честная спецификация)")
        for rec in untestedRecords {
            verify(rec.verificationStatus == .untested, "Статус строго .untested")
        }
        
        // Фильтр по транспорту
        let ethernetRecords = matrix.records(for: .usbToEthernet)
        verify(!ethernetRecords.isEmpty, "Записи USB-Ethernet присутствуют")
        
        print("  ✓ Выборки и фильтрация матрицы совместимости работают корректно")
    }
    
    // MARK: - 7. ConnectionReadinessChecker и сопоставление сетевых адресов
    func testConnectionReadinessCheckerAndEndpointMatching() async throws {
        print("\n[7/8] Тест сопоставления IP-адресов под выбранный транспорт и проверки готовности...")
        
        let checker = ConnectionReadinessChecker.shared
        
        let wifiIface = NetworkAddressInfo(
            interfaceName: "en0",
            ipAddress: "192.168.1.50",
            type: .wifi
        )
        let ethIface = NetworkAddressInfo(
            interfaceName: "en5",
            ipAddress: "192.168.8.2",
            type: .usbCable
        )
        let interfaces = [wifiIface, ethIface]
        
        // 1. Сопоставление для проводного транспорта (USB-Ethernet) -> должен выбрать 192.168.8.2
        let wiredMatch = checker.resolveBestEndpoint(for: .usbToEthernet, availableInterfaces: interfaces)
        verify(wiredMatch.ip == "192.168.8.2", "Для проводного транспорта должен быть выбран Ethernet IP")
        verify(wiredMatch.interface?.interfaceName == "en5", "Интерфейс en5")
        
        // 2. Сопоставление для Wi-Fi -> должен выбрать 192.168.1.50
        let wifiMatch = checker.resolveBestEndpoint(for: .builtInWiFiFTP, availableInterfaces: interfaces)
        verify(wifiMatch.ip == "192.168.1.50", "Для Wi-Fi транспорта должен быть выбран Wi-Fi IP")
        verify(wifiMatch.interface?.interfaceName == "en0", "Интерфейс en0")
        
        // 3. Сопоставление для прямого USB -> nil (не требует IP)
        let usbMatch = checker.resolveBestEndpoint(for: .directUSB, availableInterfaces: interfaces)
        verify(usbMatch.ip == nil, "Прямой USB не требует IP")
        
        // 4. Комплексная проверка готовности при остановленном сервере
        let readinessNotReady = checker.checkReadiness(
            model: .z8,
            transport: .usbToEthernet,
            isServerRunning: false,
            serverPort: 2121,
            isUSBConnected: false,
            storageDirectory: tempBaseURL,
            activeInterfaces: interfaces
        )
        verify(readinessNotReady.isReady == false, "При остановленном сервере система не готова")
        verify(readinessNotReady.issues.contains { $0.contains("FTP-сервер") }, "Обнаружена проблема остановленного сервера")
        verify(!readinessNotReady.recommendations.isEmpty, "Предоставлены рекомендации")
        
        // 5. Комплексная проверка готовности в штатном режиме
        let readinessReady = checker.checkReadiness(
            model: .z8,
            transport: .usbToEthernet,
            isServerRunning: true,
            serverPort: 2121,
            isUSBConnected: false,
            storageDirectory: tempBaseURL,
            activeInterfaces: interfaces
        )
        verify(readinessReady.isReady == true, "Все компоненты активны -> система готова")
        verify(readinessReady.matchedIPAddress == "192.168.8.2", "Выбран корректный IP")
        
        print("  ✓ Сопоставление сетевых маршрутов и диагностика готовности подтверждены")
    }
    
    // MARK: - 8. Сквозное исполнение пробного тестового файла (Test Probe)
    func testEndToEndTestProbeFileExecution() async throws {
        print("\n[8/8] Тест генерации и сквозного сохранения пробного файла (Test Probe)...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let coordinator = TransferCoordinator(storageManager: storage)
        let session = CaptureSession(name: "Тестовая Сессия Мастера", folderURL: tempBaseURL)
        let source = CameraSource(id: "test-probe-cam", model: "Nikon Z8", transportType: .usb)
        
        let ingested = try await ConnectionReadinessChecker.shared.sendTestProbeFile(
            coordinator: coordinator,
            session: session,
            source: source
        )
        
        // Проверяем результат
        verify(ingested.filename.hasPrefix("PROBE_"), "Имя файла пробника")
        verify(ingested.fileSize > 100_000, "Размер файла пробника больше 100 КБ")
        verify(FileManager.default.fileExists(atPath: ingested.fileURL.path), "Пробный файл физически записан на диск")
        
        // Проверяем регистрацию ассета
        verify(ingested.mediaAsset != nil, "Ассет зарегистрирован в MediaAsset")
        verify(ingested.mediaAsset?.verificationResult.isValid == true, "Верификация пробного файла успешна")
        
        // Проверяем, что в журнале диагностики появилась запись
        let recent = DiagnosticLogger.shared.getRecentEntries(limit: 10)
        verify(recent.contains { $0.message.contains("Пробный проверочный кадр") }, "Запись о пробном кадре внесена в журнал")
        
        print("  ✓ Сквозной тест пробного кадра (генерация, staging, move, верификация, SQLite) пройден")
    }
}
