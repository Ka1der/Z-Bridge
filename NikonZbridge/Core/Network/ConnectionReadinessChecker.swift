import Foundation
import Network

/// Результат проверки готовности тракта подключения
public struct ReadinessCheckResult: Sendable {
    public let isReady: Bool
    public let networkInterfaceName: String?
    public let matchedIPAddress: String?
    public let port: UInt16
    public let issues: [String]
    public let recommendations: [String]
    
    public init(
        isReady: Bool,
        networkInterfaceName: String?,
        matchedIPAddress: String?,
        port: UInt16,
        issues: [String],
        recommendations: [String]
    ) {
        self.isReady = isReady
        self.networkInterfaceName = networkInterfaceName
        self.matchedIPAddress = matchedIPAddress
        self.port = port
        self.issues = issues
        self.recommendations = recommendations
    }
}

/// Сервис проверки готовности и сетевого тракта для выбранной конфигурации
public final class ConnectionReadinessChecker: Sendable {
    public static let shared = ConnectionReadinessChecker()
    
    public init() {}
    
    /// Сопоставление подходящего сетевого интерфейса и IP-адреса под выбранный транспорт
    public func resolveBestEndpoint(
        for transport: NikonConnectionTransport,
        availableInterfaces: [NetworkAddressInfo]
    ) -> (interface: NetworkAddressInfo?, ip: String?) {
        guard transport.isFTP else {
            return (nil, nil)
        }
        
        if transport == .builtInEthernet || transport == .usbToEthernet {
            // Для проводного подключения ищем Ethernet-интерфейс (usbCable)
            let wired = availableInterfaces.first { addr in
                let name = addr.interfaceName.lowercased()
                return addr.type == .usbCable || name.contains("eth") || name.contains("usb") || name.contains("lan")
            }
            if let wired = wired {
                return (wired, wired.ipAddress)
            }
        }
        
        if transport == .builtInWiFiFTP {
            // Для беспроводного подключения ищем Wi-Fi
            let wifi = availableInterfaces.first { addr in
                addr.type == .wifi || addr.interfaceName.lowercased().contains("wlan")
            }
            if let wifi = wifi {
                return (wifi, wifi.ipAddress)
            }
        }
        
        // Резервный выбор: первый доступный IPv4 адрес
        if let fallback = availableInterfaces.first {
            return (fallback, fallback.ipAddress)
        }
        
        return (nil, nil)
    }
    
    /// Комплексная проверка готовности к приёму снимков
    public func checkReadiness(
        model: NikonCameraModel,
        transport: NikonConnectionTransport,
        isServerRunning: Bool,
        serverPort: UInt16,
        isUSBConnected: Bool,
        storageDirectory: URL,
        activeInterfaces: [NetworkAddressInfo]
    ) -> ReadinessCheckResult {
        var issues: [String] = []
        var recommendations: [String] = []
        
        // 1. Проверка доступности хранилища для записи
        let fileManager = FileManager.default
        if !fileManager.isWritableFile(atPath: storageDirectory.path) {
            issues.append("Каталог сессии защищен от записи или недоступен")
            recommendations.append("Проверьте права доступа к папке «\(storageDirectory.lastPathComponent)»")
        }
        
        // 2. Проверка транспорта
        var matchedIP: String? = nil
        var ifaceName: String? = nil
        
        if transport == .directUSB {
            if !isUSBConnected {
                issues.append("Кабель камеры не обнаружен в порту Mac/iPad")
                recommendations.append("Соедините камеру \(model.fullName) надежным кабелем USB-C и включите питание камеры")
            }
        } else {
            // FTP транспорты (Ethernet, Wi-Fi, WT-7)
            if !isServerRunning {
                issues.append("Встроенный FTP-сервер приложения не запущен")
                recommendations.append("Запустите FTP-сервер кнопкой «Запустить приём»")
            }
            
            let (bestIface, bestIP) = resolveBestEndpoint(for: transport, availableInterfaces: activeInterfaces)
            matchedIP = bestIP
            ifaceName = bestIface?.interfaceName
            
            if matchedIP == nil {
                issues.append("Не найден активный сетевой адрес для транспорта «\(transport.title)»")
                if transport.isWired {
                    recommendations.append("Подключите кабель Ethernet / сетевой адаптер USB-C к Mac/iPad")
                } else {
                    recommendations.append("Подключите Mac/iPad к сети Wi-Fi или включите точку доступа")
                }
            }
        }
        
        let isReady = issues.isEmpty
        return ReadinessCheckResult(
            isReady: isReady,
            networkInterfaceName: ifaceName,
            matchedIPAddress: matchedIP,
            port: serverPort,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    /// Создание и безопасная регистрация пробного проверочного файла (Test Probe)
    /// Позволяет фотографу убедиться, что файловая система, staging, верификация и БД функционируют на 100%
    public func sendTestProbeFile(
        coordinator: TransferCoordinator,
        session: CaptureSession,
        source: CameraSource
    ) async throws -> IngestedFile {
        let probeFileName = "PROBE_\(UUID().uuidString.prefix(8)).JPG"
        
        // Минимальный валидный JPEG заголовок (SOI + APP0 + EOI)
        var sampleData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])
        // Добавляем тестовый заполнитель (128 КБ)
        sampleData.append(Data(repeating: 0x5A, count: 131_072))
        // Завершающий маркер JPEG EOI
        sampleData.append(contentsOf: [0xFF, 0xD9])
        
        let job = try await coordinator.createTransferJob(
            source: source,
            filename: probeFileName,
            sourceFileID: probeFileName,
            expectedSize: Int64(sampleData.count)
        )
        
        guard let stagingURL = job.stagingURL else {
            throw TransferError.diskWriteFailed("Не удалось создать временный staging-файл")
        }
        
        // 1. Записываем пробные данные во временный файл
        try sampleData.write(to: stagingURL, options: .atomic)
        
        // 2. Финализируем через штатный координатор (верификация заголовков, атомарный move в сессию, запись в SQLite)
        let asset = try await coordinator.finalizeTransfer(
            jobID: job.id,
            actualSize: Int64(sampleData.count),
            duration: 0.05
        )
        
        let ingested = IngestedFile(
            id: asset.id,
            filename: asset.filename,
            fileURL: asset.fileURL,
            fileSize: asset.fileSize,
            receivedAt: asset.receivedAt,
            transferDuration: 0.05,
            mediaAsset: asset
        )
        
        DiagnosticLogger.shared.log(
            level: .info,
            subsystem: "Readiness",
            message: "Пробный проверочный кадр «\(probeFileName)» успешно сохранен и верифицирован (\(asset.fileSize) байт)"
        )
        
        return ingested
    }
}
