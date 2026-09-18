import Foundation

/// Фотосессия: логическая группа снимков с отдельной директорией хранения на диске и состоянием в каталоге
public struct CaptureSession: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    public var folderURL: URL
    public var isClosed: Bool
    public var isActive: Bool
    public var author: String?
    public var copyright: String?
    public var comment: String?
    
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        folderURL: URL,
        isClosed: Bool = false,
        isActive: Bool = false,
        author: String? = nil,
        copyright: String? = nil,
        comment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderURL = folderURL.resolvingSymlinksInPath().standardizedFileURL
        self.isClosed = isClosed
        self.isActive = isActive
        self.author = author
        self.copyright = copyright
        self.comment = comment
    }
    
    /// Генерация стандартного имени сессии на основе даты и времени
    public static func defaultSessionName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Session_" + formatter.string(from: date)
    }
}
