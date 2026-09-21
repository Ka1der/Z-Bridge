import Foundation

/// Формат медиафайла
public enum MediaFormat: Sendable, Codable, Hashable {
    case raw(fileExtension: String) // e.g. nef, nrw
    case jpeg
    case heif
    case video(fileExtension: String)
    case unknown(fileExtension: String)
    
    public init(fileExtension: String) {
        let ext = fileExtension.lowercased()
        switch ext {
        case "nef", "nrw":
            self = .raw(fileExtension: ext)
        case "jpg", "jpeg":
            self = .jpeg
        case "heic", "heif", "hif":
            self = .heif
        case "mov", "mp4":
            self = .video(fileExtension: ext)
        default:
            self = .unknown(fileExtension: ext)
        }
    }
    
    public var isRAW: Bool {
        if case .raw = self { return true }
        return false
    }
    
    public var isJPEG: Bool {
        if case .jpeg = self { return true }
        return false
    }
    
    public var isHEIF: Bool {
        if case .heif = self { return true }
        return false
    }
    
    public var displayName: String {
        switch self {
        case .raw(let ext): return ext.uppercased()
        case .jpeg: return "JPG"
        case .heif: return "HEIF"
        case .video(let ext): return ext.uppercased()
        case .unknown(let ext): return ext.uppercased()
        }
    }
}

/// Результат проверки целостности сохраненного файла
public enum AssetVerificationResult: Sendable, Codable, Hashable {
    case valid(checksum: String?)
    case corrupted(reason: String)
    case skipped
    
    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

/// Статус отбора снимка (флаг)
public enum PickStatus: Int, Sendable, Codable, CaseIterable, Hashable {
    case unflagged = 0
    case picked = 1
    case rejected = 2
    
    public var label: String {
        switch self {
        case .unflagged: return "Без флага"
        case .picked: return "Отобран"
        case .rejected: return "Отклонён"
        }
    }
    
    public var iconName: String {
        switch self {
        case .unflagged: return "flag"
        case .picked: return "flag.fill"
        case .rejected: return "xmark"
        }
    }
}

/// Основные метаданные снимка (EXIF / камера)
public struct AssetMetadata: Sendable, Codable, Hashable {
    public var cameraModel: String?
    public var lensModel: String?
    public var exposureTime: Double?
    public var fNumber: Double?
    public var iso: Int?
    public var focalLength: Double?
    public var captureDate: Date?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    
    public var quickExposureSummary: String? {
        var parts: [String] = []
        if let exp = exposureTime {
            parts.append(exp < 1.0 ? "1/\(Int(round(1.0 / exp)))" : "\(exp)s")
        }
        if let fNum = fNumber {
            parts.append(String(format: "f/%.1f", fNum))
        }
        if let iso = iso {
            parts.append("ISO \(iso)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }
    
    public init(
        cameraModel: String? = nil,
        lensModel: String? = nil,
        exposureTime: Double? = nil,
        fNumber: Double? = nil,
        iso: Int? = nil,
        focalLength: Double? = nil,
        captureDate: Date? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.exposureTime = exposureTime
        self.fNumber = fNumber
        self.iso = iso
        self.focalLength = focalLength
        self.captureDate = captureDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Сохранённый оригинальный медиафайл в сессии
public struct MediaAsset: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let sessionID: UUID
    public let filename: String
    public let fileURL: URL
    public let format: MediaFormat
    public let fileSize: Int64
    public let metadata: AssetMetadata
    public let verificationResult: AssetVerificationResult
    public let sha256Checksum: String?
    public var isMissing: Bool
    public let receivedAt: Date
    public let transferDuration: TimeInterval
    public var rating: Int // 0..5
    public var pickStatus: PickStatus
    
    public var transferSpeedMBs: Double {
        guard transferDuration > 0 else { return 0 }
        return (Double(fileSize) / 1_048_576.0) / transferDuration
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df
    }()
    
    public var formattedTime: String {
        Self.timeFormatter.string(from: receivedAt)
    }
    
    public var formattedDateTime: String {
        Self.dateTimeFormatter.string(from: metadata.captureDate ?? receivedAt)
    }
    
    public var formattedSpeed: String {
        guard transferSpeedMBs > 0 else { return "—" }
        return String(format: "%.0f МБ/с", transferSpeedMBs)
    }
    
    public var isRAW: Bool {
        format.isRAW
    }
    
    public var isJPEG: Bool {
        format.isJPEG
    }
    
    public var isHEIF: Bool {
        format.isHEIF
    }
    
    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        filename: String,
        fileURL: URL,
        format: MediaFormat,
        fileSize: Int64 = 0,
        metadata: AssetMetadata = AssetMetadata(),
        verificationResult: AssetVerificationResult = .skipped,
        sha256Checksum: String? = nil,
        isMissing: Bool = false,
        receivedAt: Date = Date(),
        transferDuration: TimeInterval = 0,
        rating: Int = 0,
        pickStatus: PickStatus = .unflagged
    ) {
        self.id = id
        self.sessionID = sessionID
        self.filename = filename
        self.fileURL = fileURL
        self.format = format
        self.fileSize = fileSize
        self.metadata = metadata
        self.verificationResult = verificationResult
        if let sum = sha256Checksum {
            self.sha256Checksum = sum
        } else if case .valid(let sum) = verificationResult {
            self.sha256Checksum = sum
        } else {
            self.sha256Checksum = nil
        }
        self.isMissing = isMissing
        self.receivedAt = receivedAt
        self.transferDuration = transferDuration
        self.rating = max(0, min(5, rating))
        self.pickStatus = pickStatus
    }
    
    public func withUpdatedURL(_ newURL: URL) -> MediaAsset {
        MediaAsset(
            id: id,
            sessionID: sessionID,
            filename: filename,
            fileURL: newURL,
            format: format,
            fileSize: fileSize,
            metadata: metadata,
            verificationResult: verificationResult,
            sha256Checksum: sha256Checksum,
            isMissing: isMissing,
            receivedAt: receivedAt,
            transferDuration: transferDuration,
            rating: rating,
            pickStatus: pickStatus
        )
    }
}
