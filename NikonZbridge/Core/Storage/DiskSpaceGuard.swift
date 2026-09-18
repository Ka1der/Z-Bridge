import Foundation

/// Защитник свободного дискового пространства: предотвращает запись при критически малом остатке памяти
public final class DiskSpaceGuard: Sendable {
    /// Минимальный резервный объем диска по умолчанию (250 МБ)
    public static let defaultReserveBytes: Int64 = 250 * 1024 * 1024
    
    public let reserveBytes: Int64
    
    public init(reserveBytes: Int64 = defaultReserveBytes) {
        self.reserveBytes = reserveBytes
    }
    
    /// Получение объема доступного свободного места на томе для указанного URL
    public func availableFreeBytes(at url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                return important
            }
            if let available = values.volumeAvailableCapacity, available > 0 {
                return Int64(available)
            }
        } catch {
            // Fallback через statvfs
            var stat = statvfs()
            if statvfs(url.path, &stat) == 0 {
                return Int64(stat.f_bavail) * Int64(stat.f_frsize)
            }
        }
        
        // Дополнительный fallback к домашнему каталогу
        var stat = statvfs()
        let homePath = NSHomeDirectory()
        if statvfs(homePath, &stat) == 0 {
            return Int64(stat.f_bavail) * Int64(stat.f_frsize)
        }
        
        return 0
    }
    
    /// Проверка, достаточно ли места на диске для сохранения файла заданного размера
    public func hasEnoughSpace(at url: URL, requiredBytes: Int64 = 0) -> Bool {
        let freeBytes = availableFreeBytes(at: url)
        return freeBytes >= (requiredBytes + reserveBytes)
    }
    
    /// Статическая проверка свободного места на носителе с настраиваемым запасом
    public static func hasSufficientSpace(for requiredBytes: Int64, destinationURL: URL, safetyMargin: Int64 = defaultReserveBytes) -> Bool {
        let guardInstance = DiskSpaceGuard(reserveBytes: safetyMargin)
        return guardInstance.hasEnoughSpace(at: destinationURL, requiredBytes: requiredBytes)
    }
    
    /// Проверка перед началом записи; выбрасывает ошибку, если места недостаточно
    public func validateSpaceBeforeTransfer(at destinationURL: URL, expectedBytes: Int64 = 0) throws {
        let freeBytes = availableFreeBytes(at: destinationURL)
        let needed = expectedBytes + reserveBytes
        guard freeBytes >= needed else {
            let freeMB = freeBytes / (1024 * 1024)
            let reserveMB = reserveBytes / (1024 * 1024)
            throw TransferError.diskWriteFailed(
                "Недостаточно свободного места на диске: свободно \(freeMB) МБ, требуется минимум \(reserveMB) МБ резерва"
            )
        }
    }
}
