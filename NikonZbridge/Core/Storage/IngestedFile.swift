import Foundation

/// Представление файла, принятого от камеры Nikon Z (адаптер совместимости для UI поверх MediaAsset)
public struct IngestedFile: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let filename: String
    public let fileURL: URL
    public let fileSize: Int64
    public let receivedAt: Date
    public let transferDuration: TimeInterval
    public let mediaAsset: MediaAsset?
    public var rating: Int
    public var pickStatus: PickStatus
    
    public var transferSpeedMBs: Double {
        guard transferDuration > 0 else { return 0 }
        return (Double(fileSize) / 1_048_576.0) / transferDuration
    }
    
    public var isRAW: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ext == "nef" || ext == "nrw"
    }
    
    public var isJPEG: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ext == "jpg" || ext == "jpeg"
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    
    public var formattedTime: String {
        Self.timeFormatter.string(from: receivedAt)
    }
    
    public var formattedSpeed: String {
        guard transferSpeedMBs > 0 else { return "—" }
        return String(format: "%.0f МБ/с", transferSpeedMBs)
    }
    
    public init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL,
        fileSize: Int64,
        receivedAt: Date = Date(),
        transferDuration: TimeInterval,
        mediaAsset: MediaAsset? = nil,
        rating: Int = 0,
        pickStatus: PickStatus = .unflagged
    ) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.receivedAt = receivedAt
        self.transferDuration = transferDuration
        self.mediaAsset = mediaAsset
        self.rating = mediaAsset?.rating ?? max(0, min(5, rating))
        self.pickStatus = mediaAsset?.pickStatus ?? pickStatus
    }
    
    public init(from asset: MediaAsset) {
        self.id = asset.id
        self.filename = asset.filename
        self.fileURL = asset.fileURL
        self.fileSize = asset.fileSize
        self.receivedAt = asset.receivedAt
        self.transferDuration = asset.transferDuration
        self.mediaAsset = asset
        self.rating = asset.rating
        self.pickStatus = asset.pickStatus
    }
}
