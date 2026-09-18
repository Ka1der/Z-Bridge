import Foundation

/// Уровень серьезности диагностического события
public enum DiagnosticLevel: String, Sendable, Codable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    
    public var icon: String {
        switch self {
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

/// Запись в журнале диагностики
public struct DiagnosticEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let level: DiagnosticLevel
    public let subsystem: String
    public let message: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DiagnosticLevel,
        subsystem: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.message = message
    }
    
    public var formattedLine: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return "[\(df.string(from: timestamp))] [\(level.rawValue)] [\(subsystem)] \(message)"
    }
}

/// Централизованный диагностический журнал с автоматическим маскированием паролей и секретов
public final class DiagnosticLogger: @unchecked Sendable {
    public static let shared = DiagnosticLogger()
    
    private let lock = NSLock()
    private var entries: [DiagnosticEntry] = []
    private let maxEntries: Int = 1000
    
    public init() {}
    
    /// Безопасная запись сообщения в журнал с фильтрацией конфиденциальных данных
    public func log(
        level: DiagnosticLevel = .info,
        subsystem: String = "App",
        message: String
    ) {
        let sanitized = sanitizeSecrets(in: message)
        let entry = DiagnosticEntry(level: level, subsystem: subsystem, message: sanitized)
        
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
    }
    
    /// Понятное русскоязычное описание ошибки переноса для пользователя
    public static func userFriendlyMessage(for error: TransferError) -> String {
        switch error {
        case .connectionLost(let msg):
            return "Связь с камерой прервана (\(msg)). Проверьте USB-кабель или сигнал Wi-Fi."
        case .fileNotFound(let file):
            return "Файл «\(file)» не найден на карте памяти камеры."
        case .verificationFailed(let msg):
            return "Файл поврежден при передаче (\(msg)). Исходный снимок на камере не пострадал, требуется повторный перенос."
        case .diskWriteFailed(let msg):
            return "Недостаточно свободного места на диске (\(msg)). Освободите память устройства."
        case .cancelled:
            return "Перенос файла отменен пользователем."
        case .timeout:
            return "Превышено время ожидания ответа от камеры. Проверьте питание и режим ожидания камеры."
        case .generic(let msg):
            return "Сбой переноса: \(msg)"
        }
    }
    
    public struct ErrorExplanation: Sendable {
        public let title: String
        public let message: String
        public let recoverySuggestion: String
        
        public init(title: String, message: String, recoverySuggestion: String) {
            self.title = title
            self.message = message
            self.recoverySuggestion = recoverySuggestion
        }
    }
    
    /// Структурированное объяснение с заголовком и рекомендациями
    public static func userFriendlyExplanation(for error: TransferError) -> ErrorExplanation {
        switch error {
        case .connectionLost(let msg):
            return ErrorExplanation(
                title: "Связь прервана",
                message: "Потеряно соединение с камерой (\(msg)).",
                recoverySuggestion: "Проверьте надежность подключения USB-кабеля или стабильность сигнала Wi-Fi."
            )
        case .fileNotFound(let file):
            return ErrorExplanation(
                title: "Файл не найден",
                message: "Файл «\(file)» отсутствует на носителе камеры.",
                recoverySuggestion: "Убедитесь, что карта памяти не извлечена и файл не был удален на камере."
            )
        case .verificationFailed(let msg):
            return ErrorExplanation(
                title: "Файл повреждён",
                message: "Контрольная сумма или размер не совпадают (\(msg)).",
                recoverySuggestion: "Повторите передачу кадра. Оригинальный файл на карте памяти камеры сохранен."
            )
        case .diskWriteFailed(let msg):
            return ErrorExplanation(
                title: "Недостаточно места на диске",
                message: "Не удалось записать файл на накопитель (\(msg)).",
                recoverySuggestion: "Очистите хранилище устройства и повторите операцию."
            )
        case .cancelled:
            return ErrorExplanation(
                title: "Передача отменена",
                message: "Операция была отменена пользователем.",
                recoverySuggestion: "При необходимости запустите импорт повторно."
            )
        case .timeout:
            return ErrorExplanation(
                title: "Таймаут ожидания",
                message: "Камера не ответила за отведенное время.",
                recoverySuggestion: "Проверьте питание камеры и отключите энергосберегающий режим засыпания."
            )
        case .generic(let msg):
            return ErrorExplanation(
                title: "Ошибка переноса",
                message: msg,
                recoverySuggestion: "Попробуйте переподключить камеру или перезапустить сессию."
            )
        }
    }
    
    /// Маскирование паролей, токенов и учетных записей
    public func sanitizeSecrets(in text: String) -> String {
        var result = text
        
        // Маскирование FTP PASS: PASS <anything>
        if let regex = try? NSRegularExpression(pattern: "(?i)PASS\\s+[^\\r\\n]+", options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "PASS ********")
        }
        
        // Маскирование password= / pass=
        if let regex = try? NSRegularExpression(pattern: "(?i)(password|pass|secret)=[^\\s&]+", options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1=********")
        }
        
        return result
    }
    
    /// Получение последних записей журнала
    public func getRecentEntries(limit: Int = 100) -> [DiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(limit))
    }
    
    /// Формирование полного отчета для экспорта без секретов
    public func exportDiagnosticReport(
        sessionName: String? = nil,
        cameraModel: String? = nil,
        totalAssets: Int = 0,
        networkIPs: [String] = []
    ) -> String {
        lock.lock()
        let allEntries = self.entries
        lock.unlock()
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = df.string(from: Date())
        
        var report = """
        ================================================================
        НИКОН Z-BRIDGE: ДИАГНОСТИЧЕСКИЙ ЖУРНАЛ (БЕЗ СЕКРЕТОВ)
        Создан: \(now)
        ================================================================
        СИСТЕМНАЯ ИНФОРМАЦИЯ:
        - ОС: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Активная сессия: \(sessionName ?? "Не выбрана")
        - Всего файлов в сессии: \(totalAssets)
        - Подключенная камера: \(cameraModel ?? "Нет подключения")
        - Сетевые адреса: \(networkIPs.isEmpty ? "Нет активных сетей" : networkIPs.joined(separator: ", "))
        ================================================================
        ЖУРНАЛ СОБЫТИЙ (Последние \(allEntries.count) записей):
        
        """
        
        for entry in allEntries {
            report += entry.formattedLine + "\n"
        }
        
        report += "\n======================== КОНЕЦ ОТЧЕТА ========================"
        return report
    }
    
    /// Очистка журнала
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
