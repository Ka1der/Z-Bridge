import Foundation
@preconcurrency import ImageCaptureCore

/// Элемент очереди передачи по USB
public struct USBQueueItem: Sendable {
    public let compositeID: String
    public let cameraFile: ICCameraFile
    public let filename: String
    public let fileSize: Int64
    public let jobID: UUID
    public let enqueuedAt: Date
    public var attempts: Int
    
    public init(
        compositeID: String,
        cameraFile: ICCameraFile,
        filename: String,
        fileSize: Int64,
        jobID: UUID,
        enqueuedAt: Date = Date(),
        attempts: Int = 0
    ) {
        self.compositeID = compositeID
        self.cameraFile = cameraFile
        self.filename = filename
        self.fileSize = fileSize
        self.jobID = jobID
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
    }
}

/// Потокобезопасная очередь загрузок по USB с контролем числа параллельных скачиваний и дедупликацией
public actor USBTransferQueue {
    /// Безопасный лимит одновременных передач (по умолчанию 1 — строго последовательный PTP конвейер)
    public let maxConcurrentDownloads: Int
    
    private var pendingQueue: [USBQueueItem] = []
    private var activeTransfers: [String: USBQueueItem] = [:]
    
    /// Множество идентификаторов объектов, которые уже находятся в очереди или передаются
    private var queuedIDs: Set<String> = []
    
    /// Множество идентификаторов объектов, уже успешно импортированных в рамках текущей сессии
    private var importedIDs: Set<String> = []
    
    public init(maxConcurrentDownloads: Int = 1) {
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
    }
    
    public var activeCount: Int {
        activeTransfers.count
    }
    
    public var pendingCount: Int {
        pendingQueue.count
    }
    
    public var totalQueueCount: Int {
        activeTransfers.count + pendingQueue.count
    }
    
    /// Проверка, запланирован ли уже объект для скачивания
    public func isEnqueuedOrActive(compositeID: String) -> Bool {
        queuedIDs.contains(compositeID) || activeTransfers[compositeID] != nil
    }
    
    /// Проверка, был ли объект уже успешно импортирован
    public func isAlreadyImported(compositeID: String) -> Bool {
        importedIDs.contains(compositeID)
    }
    
    /// Регистрация уже существующих в сессии/БД объектов для исключения повторного скачивания
    public func registerExistingImportedIDs(_ ids: [String]) {
        for id in ids {
            importedIDs.insert(id)
        }
    }
    
    /// Добавление элемента в очередь с проверкой дедупликации
    /// Возвращает true, если элемент успешно добавлен, и false, если это дубликат
    @discardableResult
    public func enqueue(_ item: USBQueueItem) -> Bool {
        // Защита от дубликатов: не планируем, если уже в очереди, активно передается или уже импортирован
        guard !queuedIDs.contains(item.compositeID),
              !importedIDs.contains(item.compositeID),
              activeTransfers[item.compositeID] == nil else {
            return false
        }
        
        queuedIDs.insert(item.compositeID)
        pendingQueue.append(item)
        return true
    }
    
    /// Добавление пакета элементов в очередь
    public func enqueueBatch(_ items: [USBQueueItem]) -> Int {
        var count = 0
        for it in items {
            if enqueue(it) {
                count += 1
            }
        }
        return count
    }
    
    /// Извлечение следующего элемента для скачивания, если есть свободные слоты
    public func dequeueNextIfAvailable() -> USBQueueItem? {
        guard activeTransfers.count < maxConcurrentDownloads, !pendingQueue.isEmpty else {
            return nil
        }
        let item = pendingQueue.removeFirst()
        activeTransfers[item.compositeID] = item
        return item
    }
    
    /// Завершение скачивания: помечаем как импортированный, освобождаем слот и возвращаем следующий элемент
    public func markCompleted(compositeID: String) -> USBQueueItem? {
        activeTransfers.removeValue(forKey: compositeID)
        queuedIDs.remove(compositeID)
        importedIDs.insert(compositeID)
        return dequeueNextIfAvailable()
    }
    
    /// Ошибка скачивания: удаляем из активных и возвращаем следующий элемент
    public func markFailed(compositeID: String) -> USBQueueItem? {
        activeTransfers.removeValue(forKey: compositeID)
        queuedIDs.remove(compositeID)
        return dequeueNextIfAvailable()
    }
    
    /// Отмена конкретного задания
    public func cancel(compositeID: String) -> USBQueueItem? {
        if let idx = pendingQueue.firstIndex(where: { $0.compositeID == compositeID }) {
            pendingQueue.remove(at: idx)
            queuedIDs.remove(compositeID)
            return nil
        }
        if activeTransfers.removeValue(forKey: compositeID) != nil {
            queuedIDs.remove(compositeID)
            return dequeueNextIfAvailable()
        }
        return nil
    }
    
    /// Полная очистка очереди (например, при извлечении кабеля)
    public func clearAll() {
        pendingQueue.removeAll()
        activeTransfers.removeAll()
        queuedIDs.removeAll()
    }
    
    /// Получить активное задание по compositeID
    public func getActiveItem(for compositeID: String) -> USBQueueItem? {
        activeTransfers[compositeID]
    }
    
    /// Получить активный compositeID по jobID
    public func findActiveCompositeID(by jobID: UUID) -> String? {
        activeTransfers.first(where: { $0.value.jobID == jobID })?.key
    }
    
    /// Получить compositeID по jobID среди ожидающих элементов очереди
    public func findPendingCompositeID(by jobID: UUID) -> String? {
        pendingQueue.first(where: { $0.jobID == jobID })?.compositeID
    }
    
    /// Получить compositeID по jobID среди активных и ожидающих элементов
    public func findCompositeID(by jobID: UUID) -> String? {
        if let active = activeTransfers.first(where: { $0.value.jobID == jobID }) {
            return active.key
        }
        return pendingQueue.first(where: { $0.jobID == jobID })?.compositeID
    }
    
    /// Проверка, находится ли элемент в очереди ожидания
    public func isPending(compositeID: String) -> Bool {
        pendingQueue.contains(where: { $0.compositeID == compositeID })
    }
    
    /// Список всех активных элементов, занимающих слоты передачи
    public var allActiveItems: [USBQueueItem] {
        Array(activeTransfers.values)
    }
}
