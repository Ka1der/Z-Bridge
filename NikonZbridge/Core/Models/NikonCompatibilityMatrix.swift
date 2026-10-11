import Foundation

/// Источник сведений о совместимости
public enum CompatibilityInfoSource: String, Sendable, Codable, CaseIterable {
    case officialManual = "Официальное руководство Nikon"
    case fieldTested = "Проверено на реальной съёмке"
    case communityVerified = "Подтверждено фотографами"
    case protocolSpec = "Спецификация протокола (PTP/FTP)"
}

/// Статус аппаратной проверки конфигурации
public enum HardwareVerificationStatus: String, Sendable, Codable, CaseIterable {
    /// Полностью протестировано на реальной камере с подтверждением стабильности
    case verified = "Проверено в железе"
    /// Соответствует спецификациям протокола, протестировано на эмуляторе/совместимых камерах
    case protocolCompliant = "Совместимо по протоколу"
    /// Аппаратное сочетание не тестировалось в лаборатории — требуется внимание
    case untested = "Не проверено в железе"
    
    public var icon: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .protocolCompliant: return "doc.text.magnifyingglass"
        case .untested: return "exclamationmark.triangle.fill"
        }
    }
    
    public var isFullyVerified: Bool {
        self == .verified
    }
}

/// Поддерживаемые возможности при данном подключении
public enum CameraCapability: String, Sendable, Codable, CaseIterable, Identifiable {
    case autoSendOnShoot = "Автоотправка при съёмке"
    case rawJpegPairing = "Связывание RAW + JPEG"
    case cardBrowser = "Просмотр и выборка с карты памяти"
    case streamingFTP = "Потоковый приём по FTP"
    case autoRetry = "Автоповтор при ошибке"
    case usbPowerDelivery = "Питание и зарядка по USB"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .autoSendOnShoot: return "bolt.horizontal.fill"
        case .rawJpegPairing: return "square.stack.3d.forward.dottedline"
        case .cardBrowser: return "sdcard"
        case .streamingFTP: return "arrow.down.to.line"
        case .autoRetry: return "arrow.clockwise"
        case .usbPowerDelivery: return "battery.100.bolt"
        }
    }
}

/// Запись в матрице совместимости Nikon Z
public struct CompatibilityRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let model: NikonCameraModel
    public let firmwareVersion: String
    public let transport: NikonConnectionTransport
    public let capabilities: [CameraCapability]
    public let infoSource: CompatibilityInfoSource
    public let verificationStatus: HardwareVerificationStatus
    public let notes: String
    
    public init(
        id: UUID = UUID(),
        model: NikonCameraModel,
        firmwareVersion: String,
        transport: NikonConnectionTransport,
        capabilities: [CameraCapability],
        infoSource: CompatibilityInfoSource,
        verificationStatus: HardwareVerificationStatus,
        notes: String
    ) {
        self.id = id
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.transport = transport
        self.capabilities = capabilities
        self.infoSource = infoSource
        self.verificationStatus = verificationStatus
        self.notes = notes
    }
}

/// Централизованная база знаний и таблица совместимости Nikon Z
public final class NikonCompatibilityMatrix: Sendable {
    public static let shared = NikonCompatibilityMatrix()
    
    public let allRecords: [CompatibilityRecord]
    
    public init() {
        self.allRecords = Self.generateMatrixRecords()
    }
    
    /// Фильтрация по модели камеры
    public func records(for model: NikonCameraModel) -> [CompatibilityRecord] {
        allRecords.filter { $0.model == model }
    }
    
    /// Фильтрация по транспорту
    public func records(for transport: NikonConnectionTransport) -> [CompatibilityRecord] {
        allRecords.filter { $0.transport == transport }
    }
    
    /// Фильтрация по статусу аппаратной проверки
    public func records(with status: HardwareVerificationStatus) -> [CompatibilityRecord] {
        allRecords.filter { $0.verificationStatus == status }
    }
    
    /// Получение записи для конкретной пары модель + транспорт
    public func record(for model: NikonCameraModel, transport: NikonConnectionTransport) -> CompatibilityRecord? {
        allRecords.first { $0.model == model && $0.transport == transport }
    }
    
    /// Генерация эталонной базы совместимости линейки Nikon Z
    private static func generateMatrixRecords() -> [CompatibilityRecord] {
        var records: [CompatibilityRecord] = []
        
        // MARK: - Nikon Z 9
        records.append(CompatibilityRecord(
            model: .z9,
            firmwareVersion: "v5.00 / v4.10",
            transport: .builtInEthernet,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Встроенный разъём 1000BASE-T RJ-45. Скорость до 110 МБ/с. Максимальная надежность для спорта и студии."
        ))
        records.append(CompatibilityRecord(
            model: .z9,
            firmwareVersion: "v5.00 / v4.10",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Поддерживается режим MTP/PTP через ImageCaptureCore. Чтение карты памяти и живой импорт."
        ))
        records.append(CompatibilityRecord(
            model: .z9,
            firmwareVersion: "v5.00 / v4.10",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Wi-Fi 5 ГГц (802.11ac). Высокая скорость при чистом радиоэфире."
        ))
        
        // MARK: - Nikon Z 8
        records.append(CompatibilityRecord(
            model: .z8,
            firmwareVersion: "v2.01 / v2.00",
            transport: .usbToEthernet,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Поддерживаются адаптеры USB-C Gigabit Ethernet (чипы RTL8153/AX88179) в ВЕРХНЕМ порту (Data). Проверено на Anker и Apple."
        ))
        records.append(CompatibilityRecord(
            model: .z8,
            firmwareVersion: "v2.01 / v2.00",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Прямой кабель в верхний порт. Нижний порт может одновременно использоваться для питания USB-PD."
        ))
        records.append(CompatibilityRecord(
            model: .z8,
            firmwareVersion: "v2.01 / v2.00",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Wi-Fi 2.4/5 ГГц с встроенным клиентом FTP. Стабильная автопередача при съемке."
        ))
        
        // MARK: - Nikon Z 6III
        records.append(CompatibilityRecord(
            model: .z6iii,
            firmwareVersion: "v1.00",
            transport: .usbToEthernet,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Процессор Expeed 7 с поддержкой режима USB-LAN через USB-C порт данных."
        ))
        records.append(CompatibilityRecord(
            model: .z6iii,
            firmwareVersion: "v1.00",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Прямое подключение по USB-C SuperSpeed 10 Гбит/с."
        ))
        records.append(CompatibilityRecord(
            model: .z6iii,
            firmwareVersion: "v1.00",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Wi-Fi 5 ГГц с расширенной поддержкой фоновой передачи."
        ))
        
        // MARK: - Nikon Z f
        records.append(CompatibilityRecord(
            model: .zf,
            firmwareVersion: "v1.10 / v1.00",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Порт USB-C Type-C (SuperSpeed USB). Полная совместимость с ImageCaptureCore."
        ))
        records.append(CompatibilityRecord(
            model: .zf,
            firmwareVersion: "v1.10 / v1.00",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Встроенный модуль Wi-Fi 2.4/5 ГГц. Передача RAW и JPEG."
        ))
        records.append(CompatibilityRecord(
            model: .zf,
            firmwareVersion: "v1.10",
            transport: .usbToEthernet,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .protocolSpec,
            verificationStatus: .untested,
            notes: "ВНИМАНИЕ: Поддержка USB-LAN адаптеров на Z f заявлена спецификацией Expeed 7, но требует проверки совместимости конкретного чипсета адаптера."
        ))
        
        // MARK: - Nikon Z 7II & Z 6II
        records.append(CompatibilityRecord(
            model: .z7ii,
            firmwareVersion: "v1.60 / v1.40",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "USB-C разъем. Питание USB-PD при использовании оригинального аккумулятора EN-EL15c."
        ))
        records.append(CompatibilityRecord(
            model: .z7ii,
            firmwareVersion: "v1.60",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Встроенный Wi-Fi с поддержкой профиля связи с ПК / FTP-сервером."
        ))
        records.append(CompatibilityRecord(
            model: .z7ii,
            firmwareVersion: "v1.60",
            transport: .wt7Transmitter,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Требуется передатчик WT-7. Полноценный Gigabit Ethernet и мощный дальнобойный Wi-Fi."
        ))
        
        records.append(CompatibilityRecord(
            model: .z6ii,
            firmwareVersion: "v1.60 / v1.40",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "USB-C разъем. Надежный импорт по PTP."
        ))
        records.append(CompatibilityRecord(
            model: .z6ii,
            firmwareVersion: "v1.60",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Встроенный Wi-Fi. Рекомендуется диапазон 5 ГГц при наличии."
        ))
        records.append(CompatibilityRecord(
            model: .z6ii,
            firmwareVersion: "v1.60",
            transport: .wt7Transmitter,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Подключение внешнего модуля WT-7 через нижнее штативное гнездо и разъем USB."
        ))
        
        // MARK: - Nikon Z 7 & Z 6 (1st Gen)
        records.append(CompatibilityRecord(
            model: .z7,
            firmwareVersion: "v3.60",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "USB-C разъем. Прошивка v3.60 обеспечивает максимальную стабильность передачи RAW 45.7 МП."
        ))
        records.append(CompatibilityRecord(
            model: .z7,
            firmwareVersion: "v3.60",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .communityVerified,
            verificationStatus: .verified,
            notes: "Wi-Fi профиль связи с компьютером (FTP)."
        ))
        records.append(CompatibilityRecord(
            model: .z6,
            firmwareVersion: "v3.60",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "USB-C. Отличная скорость передачи 24.5 МП файлов (NEF без потерь)."
        ))
        records.append(CompatibilityRecord(
            model: .z6,
            firmwareVersion: "v3.60",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .communityVerified,
            verificationStatus: .verified,
            notes: "Wi-Fi связь с ПК."
        ))
        
        // MARK: - Nikon Z 5
        records.append(CompatibilityRecord(
            model: .z5,
            firmwareVersion: "v1.40",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "USB-C разъем. Два слота SD UHS-II. Поддерживается питание по USB во время работы."
        ))
        records.append(CompatibilityRecord(
            model: .z5,
            firmwareVersion: "v1.40",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Только Wi-Fi 2.4 ГГц. Скорость беспроводной передачи умеренная (рекомендуется передавать JPEG либо использовать USB)."
        ))
        
        // MARK: - Nikon Z 5II & Z 5IIC (EXPEED 7)
        records.append(CompatibilityRecord(
            model: .z5ii,
            firmwareVersion: "v1.00",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "USB-C SuperSpeed 3.2. Поддержка прямого импорта PTP и питания USB-PD."
        ))
        records.append(CompatibilityRecord(
            model: .z5ii,
            firmwareVersion: "v1.00",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Wi-Fi 2.4/5 ГГц с встроенным FTP-клиентом."
        ))
        records.append(CompatibilityRecord(
            model: .z5ii,
            firmwareVersion: "v1.00",
            transport: .usbToEthernet,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Поддержка адаптеров USB-C Ethernet в меню сети."
        ))
        
        records.append(CompatibilityRecord(
            model: .z5iic,
            firmwareVersion: "v1.00",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Компактный корпус FX, разъем USB-C SuperSpeed 3.2."
        ))
        records.append(CompatibilityRecord(
            model: .z5iic,
            firmwareVersion: "v1.00",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Встроенный двухдиапазонный Wi-Fi 2.4/5 ГГц (FTP)."
        ))
        records.append(CompatibilityRecord(
            model: .z5iic,
            firmwareVersion: "v1.00",
            transport: .usbToEthernet,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Поддержка адаптеров USB-C Ethernet."
        ))
        
        // MARK: - Nikon Z 50II, Z 50, Z 30, Z fc (DX)
        records.append(CompatibilityRecord(
            model: .z50ii,
            firmwareVersion: "v1.00",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Разъем USB-C SuperSpeed. Процессор EXPEED 7 с поддержкой быстрого импорта."
        ))
        records.append(CompatibilityRecord(
            model: .z50ii,
            firmwareVersion: "v1.00",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Wi-Fi 2.4/5 ГГц."
        ))
        
        records.append(CompatibilityRecord(
            model: .z50,
            firmwareVersion: "v2.50",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "ВНИМАНИЕ: На Z 50 используется разъем Micro-USB (Micro-B). Обязательно используйте кабель с линиями данных (Data), кабели только для зарядки не распознаются."
        ))
        records.append(CompatibilityRecord(
            model: .z50,
            firmwareVersion: "v2.50",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .streamingFTP],
            infoSource: .protocolSpec,
            verificationStatus: .untested,
            notes: "ВНИМАНИЕ: На Z 50 встроенный Wi-Fi ориентирован в первую очередь на SnapBridge. Подключение напрямую к стороннему FTP требует ручного профиля ПК и не верифицировано в железе."
        ))
        
        records.append(CompatibilityRecord(
            model: .z30,
            firmwareVersion: "v1.10",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .officialManual,
            verificationStatus: .verified,
            notes: "Разъем USB-C. Поддержка непрерывного питания во время работы."
        ))
        records.append(CompatibilityRecord(
            model: .z30,
            firmwareVersion: "v1.10",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Wi-Fi 2.4 ГГц."
        ))
        
        records.append(CompatibilityRecord(
            model: .zfc,
            firmwareVersion: "v1.50",
            transport: .directUSB,
            capabilities: [.autoSendOnShoot, .rawJpegPairing, .cardBrowser, .autoRetry, .usbPowerDelivery],
            infoSource: .fieldTested,
            verificationStatus: .verified,
            notes: "Разъем USB-C. Полная поддержка прямого tethering-импорта."
        ))
        records.append(CompatibilityRecord(
            model: .zfc,
            firmwareVersion: "v1.50",
            transport: .builtInWiFiFTP,
            capabilities: [.autoSendOnShoot, .streamingFTP],
            infoSource: .officialManual,
            verificationStatus: .protocolCompliant,
            notes: "Wi-Fi 2.4 ГГц."
        ))
        
        return records
    }
}
