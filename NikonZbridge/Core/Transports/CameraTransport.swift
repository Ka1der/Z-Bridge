import Foundation

/// Делегат событий транспорта камеры для координатора переноса
public protocol CameraTransportDelegate: AnyObject, Sendable {
    /// Обнаружен источник (камера подключилась)
    func transport(_ transport: CameraTransport, didDiscoverSource source: CameraSource) async
    
    /// Камера отключилась
    func transport(_ transport: CameraTransport, didDisconnectSource sourceID: String) async
    
    /// Запрос на создание задания для входящего файла (перед началом записи на диск).
    /// Координатор возвращает TransferJob с жестко зафиксированным destinationURL и sessionID.
    func transport(
        _ transport: CameraTransport,
        didReceiveFileOffer filename: String,
        from source: CameraSource,
        expectedSize: Int64?
    ) async -> TransferJob
    
    /// Прогресс передачи байт
    func transport(
        _ transport: CameraTransport,
        didUpdateProgress jobID: UUID,
        transferredBytes: Int64,
        totalBytes: Int64?,
        speedMBs: Double
    ) async
    
    /// Поток байт завершен, требуется финализация и проверка целостности в координаторе
    func transport(
        _ transport: CameraTransport,
        didCompleteTransfer jobID: UUID,
        actualSize: Int64,
        duration: TimeInterval
    ) async
    
    /// Ошибка при передаче файла
    func transport(
        _ transport: CameraTransport,
        didFailTransfer jobID: UUID,
        error: TransferError
    ) async
    
    /// Прерывание соединения во время передачи файла
    func transport(
        _ transport: CameraTransport,
        didInterruptTransfer jobID: UUID,
        reason: String
    ) async
}

/// Унифицированный интерфейс транспорта подключения к камере
public protocol CameraTransport: AnyObject, Sendable {
    /// Тип транспорта (USB или FTP)
    var transportType: CameraTransportType { get }
    
    /// Подключена ли камера в данный момент
    var isConnected: Bool { get }
    
    /// Информация о подключенном источнике
    var connectedSource: CameraSource? { get }
    
    /// Делегат для уведомления координатора
    var delegate: CameraTransportDelegate? { get set }
    
    /// Запуск прослушивания / поиска устройств
    func start() async throws
    
    /// Остановка работы транспорта
    func stop() async
    
    /// Запрос на скачивание файла по инициативе приложения (Pull).
    /// Доступен для USB, для FTP вызывает ошибку unsupported.
    func requestDownload(fileID: String, into job: TransferJob) async throws
    
    /// Уведомление о смене активной сессии для синхронизации дедупликации и статусов файлов
    func didChangeActiveSession(_ session: CaptureSession) async
    
    /// Принудительное обновление оглавления носителя (если поддерживается транспортом)
    func refreshCatalog() async
}

extension CameraTransport {
    /// Реализация по умолчанию для транспортов без поддержки Pull-запросов
    public func requestDownload(fileID: String, into job: TransferJob) async throws {
        throw TransferError.generic("Транспорт \(transportType.displayName) не поддерживает скачивание по запросу приложения (только Push)")
    }
    
    /// Реализация по умолчанию для транспортов, не требующих отдельной синхронизации сессий
    public func didChangeActiveSession(_ session: CaptureSession) async {}
    
    /// Реализация по умолчанию для транспортов без отдельной процедуры обновления оглавления
    public func refreshCatalog() async {}
}
