import Foundation

/// Соглашение по наименованию XMP sidecar файлов-компаньонов
public enum XMPSidecarNamingConvention: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Стандарт Adobe Lightroom Classic, Camera Raw, Bridge, Capture One: DSC_0001.xmp
    case standardBasename = "standard_basename"
    /// Формат darktable и Unix: DSC_0001.NEF.xmp
    case fullFilename = "full_filename"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .standardBasename:
            return "Базовое имя (.xmp) — Lightroom / ACR / Capture One"
        case .fullFilename:
            return "Полное имя (.NEF.xmp) — darktable / Unix"
        }
    }
    
    public func sidecarFilename(for sourceFilename: String) -> String {
        switch self {
        case .standardBasename:
            let base = (sourceFilename as NSString).deletingPathExtension
            return base + ".xmp"
        case .fullFilename:
            return sourceFilename + ".xmp"
        }
    }
}

/// Метаданные фотосессии (описание, авторство, заметки)
public struct SessionMetadata: Sendable, Codable, Hashable {
    public var sessionName: String
    public var author: String?
    public var copyright: String?
    public var comment: String?
    public var clientName: String?
    public var sessionDate: Date
    
    public init(
        sessionName: String,
        author: String? = nil,
        copyright: String? = nil,
        comment: String? = nil,
        clientName: String? = nil,
        sessionDate: Date = Date()
    ) {
        self.sessionName = sessionName
        self.author = author
        self.copyright = copyright
        self.comment = comment
        self.clientName = clientName
        self.sessionDate = sessionDate
    }
}

/// Запись об отдельном файле сессии для манифеста
public struct SessionManifestFileEntry: Sendable, Codable, Hashable {
    public let filename: String
    public let format: String
    public let fileSize: Int64
    public let rating: Int
    public let pickStatus: String
    public let sha256: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let exposureSummary: String?
    public let exportStatus: String
    public let destinationPath: String?
    public let xmpSidecarPath: String?
    
    public init(
        filename: String,
        format: String,
        fileSize: Int64,
        rating: Int,
        pickStatus: String,
        sha256: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        exposureSummary: String? = nil,
        exportStatus: String = "Успешно",
        destinationPath: String? = nil,
        xmpSidecarPath: String? = nil
    ) {
        self.filename = filename
        self.format = format
        self.fileSize = fileSize
        self.rating = rating
        self.pickStatus = pickStatus
        self.sha256 = sha256
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.exposureSummary = exposureSummary
        self.exportStatus = exportStatus
        self.destinationPath = destinationPath
        self.xmpSidecarPath = xmpSidecarPath
    }
}

/// Сводная статистика фотосессии
public struct SessionManifestStatistics: Sendable, Codable, Hashable {
    public let totalFiles: Int
    public let totalBytes: Int64
    public let rawCount: Int
    public let jpegCount: Int
    public let heifCount: Int
    public let pickedCount: Int
    public let rejectedCount: Int
    public let unflaggedCount: Int
    public let ratedCounts: [Int: Int]
    public let averageTransferSpeedMBs: Double?
    
    public init(
        totalFiles: Int,
        totalBytes: Int64,
        rawCount: Int,
        jpegCount: Int,
        heifCount: Int,
        pickedCount: Int,
        rejectedCount: Int,
        unflaggedCount: Int,
        ratedCounts: [Int: Int] = [:],
        averageTransferSpeedMBs: Double? = nil
    ) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.rawCount = rawCount
        self.jpegCount = jpegCount
        self.heifCount = heifCount
        self.pickedCount = pickedCount
        self.rejectedCount = rejectedCount
        self.unflaggedCount = unflaggedCount
        self.ratedCounts = ratedCounts
        self.averageTransferSpeedMBs = averageTransferSpeedMBs
    }
    
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

/// Манифест описания фотосессии
public struct SessionManifest: Sendable, Codable, Hashable {
    public static let currentVersion = "1.0"
    
    public let manifestVersion: String
    public let session: SessionMetadata
    public let generatedAt: Date
    public let statistics: SessionManifestStatistics
    public let files: [SessionManifestFileEntry]
    
    public init(
        manifestVersion: String = currentVersion,
        session: SessionMetadata,
        generatedAt: Date = Date(),
        statistics: SessionManifestStatistics,
        files: [SessionManifestFileEntry]
    ) {
        self.manifestVersion = manifestVersion
        self.session = session
        self.generatedAt = generatedAt
        self.statistics = statistics
        self.files = files
    }
    
    public init(
        session: SessionMetadata,
        files: [SessionManifestFileEntry],
        generatedAt: Date = Date(),
        averageTransferSpeedMBs: Double? = nil
    ) {
        var raw = 0
        var jpeg = 0
        var heif = 0
        var picked = 0
        var rejected = 0
        var unflagged = 0
        var rated: [Int: Int] = [:]
        var totalBytes: Int64 = 0
        
        for file in files {
            totalBytes += file.fileSize
            let fmt = file.format.uppercased()
            if fmt.contains("RAW") || fmt.contains("NEF") { raw += 1 }
            else if fmt.contains("JPG") || fmt.contains("JPEG") { jpeg += 1 }
            else if fmt.contains("HEIF") || fmt.contains("HIF") { heif += 1 }
            
            let status = file.pickStatus.lowercased()
            if status.contains("pick") || status.contains("отобран") || status.contains("выбран") { picked += 1 }
            else if status.contains("reject") || status.contains("отклон") { rejected += 1 }
            else { unflagged += 1 }
            
            rated[file.rating, default: 0] += 1
        }
        
        let stats = SessionManifestStatistics(
            totalFiles: files.count,
            totalBytes: totalBytes,
            rawCount: raw,
            jpegCount: jpeg,
            heifCount: heif,
            pickedCount: picked,
            rejectedCount: rejected,
            unflaggedCount: unflagged,
            ratedCounts: rated,
            averageTransferSpeedMBs: averageTransferSpeedMBs
        )
        
        self.init(
            manifestVersion: SessionManifest.currentVersion,
            session: session,
            generatedAt: generatedAt,
            statistics: stats,
            files: files
        )
    }
    
    /// Машиночитаемый JSON манифест
    public func generateJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Человекочитаемый отчет в формате Markdown
    public func generateMarkdownReport() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let dateStr = dateFormatter.string(from: session.sessionDate)
        let genStr = dateFormatter.string(from: generatedAt)
        
        var md = """
        # Отчёт фотосессии: \(session.sessionName)
        
        **Дата съёмки:** \(dateStr)  
        **Экспортировано:** \(genStr)  
        """
        
        if let author = session.author, !author.isEmpty {
            md += "\n**Автор / Фотограф:** \(author)  "
        }
        if let copyright = session.copyright, !copyright.isEmpty {
            md += "\n**Авторские права:** \(copyright)  "
        }
        if let client = session.clientName, !client.isEmpty {
            md += "\n**Клиент:** \(client)  "
        }
        if let comment = session.comment, !comment.isEmpty {
            md += "\n**Заметки / Комментарий:** \(comment)  "
        }
        
        md += """
        
        
        ---
        
        ## Сводная статистика сессии
        
        | Параметр | Значение |
        |---|---|
        | Всего файлов | \(statistics.totalFiles) |
        | Общий объём | \(statistics.formattedTotalSize) |
        | RAW оригиналы (.NEF/.NRW) | \(statistics.rawCount) |
        | JPEG изображения | \(statistics.jpegCount) |
        | HEIF изображения (.HIF) | \(statistics.heifCount) |
        | Отобранные кадры (Pick) | \(statistics.pickedCount) |
        | Отклонённые кадры (Reject) | \(statistics.rejectedCount) |
        | Без флага | \(statistics.unflaggedCount) |
        """
        
        if let speed = statistics.averageTransferSpeedMBs, speed > 0 {
            md += "\n| Средняя скорость передачи | \(String(format: "%.1f", speed)) МБ/с |"
        }
        
        md += """
        
        
        ### Распределение по рейтингу
        | Рейтинг | Количество кадров |
        |---|---|
        | ★★★★★ (5 звёзд) | \(statistics.ratedCounts[5] ?? 0) |
        | ★★★★☆ (4 звезды) | \(statistics.ratedCounts[4] ?? 0) |
        | ★★★☆☆ (3 звезды) | \(statistics.ratedCounts[3] ?? 0) |
        | ★★☆☆☆ (2 звезды) | \(statistics.ratedCounts[2] ?? 0) |
        | ★☆☆☆☆ (1 звезда) | \(statistics.ratedCounts[1] ?? 0) |
        | Без рейтинга (0) | \(statistics.ratedCounts[0] ?? 0) |
        
        ---
        
        ## Перечень файлов
        
        | Файл | Формат | Размер | Рейтинг | Флаг | Камера / Параметры | Статус |
        |---|---|---|---|---|---|---|
        """
        
        for file in files {
            let stars = file.rating > 0 ? String(repeating: "★", count: file.rating) : "—"
            let sizeStr = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
            let exp = file.exposureSummary ?? "—"
            let cam = file.cameraModel ?? "Nikon"
            md += "\n| `\(file.filename)` | \(file.format) | \(sizeStr) | \(stars) | \(file.pickStatus) | \(cam) (\(exp)) | \(file.exportStatus) |"
        }
        
        md += "\n\n_Создано приложением Z-Bridge (Этап 12: XMP и метаданные сессии)_\n"
        return md
    }
    
    /// Краткая текстовая сводка
    public func generateTextSummary() -> String {
        return """
        Сессия: \(session.sessionName)
        Дата: \(session.sessionDate)
        Автор: \(session.author ?? "Не указан")
        Копирайт: \(session.copyright ?? "Не указан")
        Файлов: \(statistics.totalFiles) (\(statistics.formattedTotalSize))
        Отобрано (Pick): \(statistics.pickedCount)
        Отклонено (Reject): \(statistics.rejectedCount)
        5 звёзд: \(statistics.ratedCounts[5] ?? 0)
        4 звезды: \(statistics.ratedCounts[4] ?? 0)
        3 звезды: \(statistics.ratedCounts[3] ?? 0)
        """
    }
}
