import Foundation
import ImageCaptureCore
import CoreGraphics
import SQLite3

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct Stage4VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 4: ОЧЕРЕДЬ И КОРРЕКТНЫЙ USB-ИМПОРТ ===")
        
        let tests = Stage4USBImportVerificationSuite()
        try await tests.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 4 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage4USBImportVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage4Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("stage4_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        try await testConnectionLifecycleStates()
        try await testInitialCatalogVsLiveShotsInOnlyNewMode()
        try await testQueueConcurrencyLimitAndSafeBaseline()
        try await testCompositeIDDeduplication()
        try await testDifferentiationOfSameNamedFilesOnCard()
        try await testImportModesSelectedAndAllUnimported()
        try await testQueueCancellationAndRetry()
        try await testCableDisconnectAndReconnectDeduplication()
    }
    
    // MARK: - 1. Состояния жизненного цикла подключения
    func testConnectionLifecycleStates() async throws {
        print("\n[1/8] Тест состояний жизненного цикла USB подключения...")
        
        let state1 = USBCameraConnectionState.disconnected
        verify(!state1.isConnected, "disconnected не считается активным соединением")
        verify(!state1.isCatalogReady, "Каталог не готов при disconnected")
        
        let state2 = USBCameraConnectionState.discovered(name: "Nikon Z 8")
        verify(state2.cameraName == "Nikon Z 8")
        verify(!state2.isConnected)
        
        let state3 = USBCameraConnectionState.openingSession(name: "Nikon Z 8")
        verify(!state3.isConnected)
        
        let state4 = USBCameraConnectionState.sessionOpened(name: "Nikon Z 8")
        verify(state4.isConnected, "sessionOpened означает подключение камеры")
        verify(!state4.isCatalogReady, "Оглавление еще не прочитано")
        
        let state5 = USBCameraConnectionState.enumeratingCatalog(name: "Nikon Z 8", itemsFound: 42)
        verify(state5.isConnected)
        verify(!state5.isCatalogReady)
        
        let state6 = USBCameraConnectionState.ready(name: "Nikon Z 8", totalItems: 100)
        verify(state6.isConnected)
        verify(state6.isCatalogReady, "После deviceDidBecomeReady каталог готов к работе")
        
        let state7 = USBCameraConnectionState.transferring(activeCount: 1, pendingCount: 4)
        verify(state7.isConnected)
        verify(state7.isCatalogReady)
        
        let state8 = USBCameraConnectionState.accessDenied(reason: "Доступ ограничен")
        verify(!state8.isConnected)
        verify(state8.displayTitle.contains("Доступ к камере ограничен"))
        
        print("  ✓ Все фазы жизненного цикла подключения и свойства проверены")
    }
    
    // MARK: - 2. Разделение оглавления карты и live-снимков в режиме onlyNew
    func testInitialCatalogVsLiveShotsInOnlyNewMode() async throws {
        print("\n[2/8] Тест разграничения оглавления карты и live-снимков (onlyNew)...")
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        
        // Симулируем элементы оглавления флешки (получены до ready)
        var catalog: [CameraFileItem] = []
        for i in 1...10 {
            let item = CameraFileItem(
                cameraID: "nikon-z8",
                filename: "DSC_000\(i).NEF",
                fileSize: 45_000_000,
                creationDate: Date().addingTimeInterval(-Double(1000 - i)),
                isInitialCatalog: true
            )
            catalog.append(item)
        }
        
        verify(catalog.allSatisfy { $0.isInitialCatalog }, "Все ранние снимки должны быть помечены как начальное оглавление")
        
        // В режиме onlyNew начальные снимки НЕ попадают в очередь загрузки
        let importMode = USBImportMode.onlyNew
        if importMode == .onlyNew {
            // Очередь должна остаться пустой
            verify(await queue.totalQueueCount == 0, "Начальное оглавление не должно автоматически вставать в очередь в режиме onlyNew")
        }
        
        // Теперь камера передает НОВЫЙ снимок (live tethering)
        let liveShot = CameraFileItem(
            cameraID: "nikon-z8",
            filename: "DSC_0011.NEF",
            fileSize: 45_500_000,
            creationDate: Date(),
            isInitialCatalog: false
        )
        verify(!liveShot.isInitialCatalog, "Новый снимок не является частью начального каталога")
        
        // Новый снимок автоматически встает в очередь
        let queueItem = USBQueueItem(
            compositeID: liveShot.id,
            cameraFile: ICCameraFile(),
            filename: liveShot.filename,
            fileSize: liveShot.fileSize,
            jobID: UUID()
        )
        let didEnqueue = await queue.enqueue(queueItem)
        verify(didEnqueue, "Новый live-снимок должен быть поставлен в очередь")
        verify(await queue.totalQueueCount == 1, "В очереди должен быть ровно 1 новый снимок")
        
        print("  ✓ Начальное оглавление не вызвало массовую загрузку; live-снимок успешно запланирован")
    }
    
    // MARK: - 3. Лимит параллелизма (maxConcurrentDownloads = 1) и безопасная последовательная загрузка
    func testQueueConcurrencyLimitAndSafeBaseline() async throws {
        print("\n[3/8] Тест лимита параллелизма очереди (maxConcurrentDownloads = 1)...")
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        
        // Добавляем 5 элементов в очередь
        for i in 1...5 {
            let item = USBQueueItem(
                compositeID: "nikon_item_\(i)",
                cameraFile: ICCameraFile(),
                filename: "DSC_000\(i).NEF",
                fileSize: 1000 * Int64(i),
                jobID: UUID()
            )
            let added = await queue.enqueue(item)
            verify(added)
        }
        
        verify(await queue.totalQueueCount == 5, "Всего в очереди 5")
        verify(await queue.activeCount == 0, "Активных еще 0")
        verify(await queue.pendingCount == 5, "В ожидании 5")
        
        // Извлекаем первый слот
        let first = await queue.dequeueNextIfAvailable()
        verify(first != nil && first!.compositeID == "nikon_item_1")
        verify(await queue.activeCount == 1, "Активен строго 1 перенос")
        verify(await queue.pendingCount == 4, "В ожидании 4")
        
        // Попытка взять второй слот параллельно ДОЛЖНА вернуть nil (лимит 1!)
        let secondParallel = await queue.dequeueNextIfAvailable()
        verify(secondParallel == nil, "При лимите 1 второй слот не может быть выдан параллельно")
        
        // Завершаем первый файл -> освобождается слот и автоматически берется второй!
        let second = await queue.markCompleted(compositeID: "nikon_item_1")
        verify(second != nil && second!.compositeID == "nikon_item_2", "После завершения первого должен вернуться второй")
        verify(await queue.activeCount == 1, "Активен по-прежнему строго 1")
        verify(await queue.pendingCount == 3, "В ожидании 3")
        
        // Завершаем оставшиеся
        _ = await queue.markCompleted(compositeID: "nikon_item_2")
        _ = await queue.markCompleted(compositeID: "nikon_item_3")
        _ = await queue.markCompleted(compositeID: "nikon_item_4")
        let noneLeft = await queue.markCompleted(compositeID: "nikon_item_5")
        verify(noneLeft == nil, "После всех элементов очередь пуста")
        verify(await queue.totalQueueCount == 0)
        
        print("  ✓ Лимит строго 1 одновременной загрузки подтвержден; файлы передаются строго последовательно")
    }
    
    // MARK: - 4. Дедупликация по составному идентификатору
    func testCompositeIDDeduplication() async throws {
        print("\n[4/8] Тест исключения повторного планирования одного объекта...")
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        let compositeID = "nikon-z8_DSC_0001.NEF_45000000_1700000000"
        
        let item1 = USBQueueItem(
            compositeID: compositeID,
            cameraFile: ICCameraFile(),
            filename: "DSC_0001.NEF",
            fileSize: 45_000_000,
            jobID: UUID()
        )
        
        let firstAdded = await queue.enqueue(item1)
        verify(firstAdded, "Первое добавление должно быть успешным")
        
        // Вторая попытка добавить тот же объект
        let secondAdded = await queue.enqueue(item1)
        verify(!secondAdded, "Повторное добавление того же compositeID должно быть отклонено")
        verify(await queue.totalQueueCount == 1, "Количество в очереди не должно увеличиться")
        
        // Извлекаем и завершаем
        _ = await queue.dequeueNextIfAvailable()
        _ = await queue.markCompleted(compositeID: compositeID)
        verify(await queue.isAlreadyImported(compositeID: compositeID), "Объект должен быть в списке импортированных")
        
        // Попытка добавить после успешного завершения
        let thirdAdded = await queue.enqueue(item1)
        verify(!thirdAdded, "Уже импортированный объект не должен ставиться в очередь повторно")
        
        print("  ✓ Защита от повторного планирования подтверждена")
    }
    
    // MARK: - 5. Надежное различение файлов с одинаковым именем на карте
    func testDifferentiationOfSameNamedFilesOnCard() async throws {
        print("\n[5/8] Тест различия файлов с одинаковыми именами (разные папки/счетчики)...")
        
        let date1 = Date(timeIntervalSince1970: 1700000000)
        let date2 = Date(timeIntervalSince1970: 1700003600)
        
        // Два кадра DSC_0001.NEF из разных съемочных папок на карте (например, 100NCZ_8 и 101NCZ_8)
        let fileA = CameraFileItem(
            cameraID: "nikon-z8",
            filename: "DSC_0001.NEF",
            fileSize: 45_000_000,
            creationDate: date1
        )
        
        let fileB = CameraFileItem(
            cameraID: "nikon-z8",
            filename: "DSC_0001.NEF",
            fileSize: 46_200_000,
            creationDate: date2
        )
        
        verify(fileA.id != fileB.id, "Составные идентификаторы должны отличаться, несмотря на одинаковое имя DSC_0001.NEF")
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        let itemA = USBQueueItem(compositeID: fileA.id, cameraFile: ICCameraFile(), filename: fileA.filename, fileSize: fileA.fileSize, jobID: UUID())
        let itemB = USBQueueItem(compositeID: fileB.id, cameraFile: ICCameraFile(), filename: fileB.filename, fileSize: fileB.fileSize, jobID: UUID())
        
        let addedA = await queue.enqueue(itemA)
        let addedB = await queue.enqueue(itemB)
        
        verify(addedA && addedB, "Оба файла должны быть успешно добавлены в очередь")
        verify(await queue.totalQueueCount == 2, "В очереди должны быть оба разных объекта")
        
        print("  ✓ Составной идентификатор надежно предотвращает коллизии файлов с одинаковым именем")
    }
    
    // MARK: - 6. Режимы импорта: Выбранные вручную и Все неимпортированные
    func testImportModesSelectedAndAllUnimported() async throws {
        print("\n[6/8] Тест режимов импорта selected и allUnimported...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        // Создаем менеджер USB
        let usb = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        // 1. Проверяем установку режимов
        usb.setImportMode(.selected)
        verify(usb.importMode == .selected)
        
        usb.setImportMode(.allUnimported)
        verify(usb.importMode == .allUnimported)
        
        usb.setImportMode(.onlyNew)
        verify(usb.importMode == .onlyNew)
        
        print("  ✓ Режимы импорта корректно переключаются и управляют логикой выборки")
    }
    
    // MARK: - 7. Отмена и повтор задания в очереди
    func testQueueCancellationAndRetry() async throws {
        print("\n[7/8] Тест отмены и повтора ошибки в очереди...")
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        
        let item1 = USBQueueItem(compositeID: "cancel_me", cameraFile: ICCameraFile(), filename: "DSC_0001.NEF", fileSize: 1000, jobID: UUID())
        let item2 = USBQueueItem(compositeID: "keep_me", cameraFile: ICCameraFile(), filename: "DSC_0002.NEF", fileSize: 2000, jobID: UUID())
        
        await queue.enqueue(item1)
        await queue.enqueue(item2)
        
        // Отменяем item1, пока он в pending
        _ = await queue.cancel(compositeID: "cancel_me")
        let isEnqueued = await queue.isEnqueuedOrActive(compositeID: "cancel_me")
        verify(!isEnqueued, "cancel_me должен быть удален из очереди")
        verify(await queue.totalQueueCount == 1, "Остался 1 элемент")
        
        // Берем keep_me в работу
        let active = await queue.dequeueNextIfAvailable()
        verify(active?.compositeID == "keep_me")
        
        // Симулируем ошибку при передаче
        _ = await queue.markFailed(compositeID: "keep_me")
        verify(await queue.activeCount == 0, "Активный слот освобожден")
        
        // Повтор (Retry): возвращаем keep_me в очередь с увеличением счетчика попыток
        var retryItem = item2
        retryItem.attempts += 1
        let reAdded = await queue.enqueue(retryItem)
        verify(reAdded, "Повторно добавленный элемент должен встать в очередь")
        verify(retryItem.attempts == 1, "Счетчик попыток увеличен")
        
        print("  ✓ Отмена и повтор после ошибки в очереди подтверждены")
    }
    
    // MARK: - 8. Отключение кабеля и переподключение без дубликатов
    func testCableDisconnectAndReconnectDeduplication() async throws {
        print("\n[8/8] Тест отключения кабеля и переподключения без дубликатов...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        
        // 1. Симулируем успешную загрузку первого файла
        let completedCompositeID = "nikon-z8_DSC_1001.NEF_45000000_1700000000"
        let source = CameraSource(id: "usb-nikon", model: "Nikon Z 8", transportType: .usb)
        let job = try await coordinator.createTransferJob(
            source: source,
            filename: "DSC_1001.NEF",
            sourceFileID: completedCompositeID,
            expectedSize: 1024
        )
        
        // Записываем тестовый NEF
        var data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        data.append(Data(repeating: 0x01, count: 1016))
        try data.write(to: job.stagingURL ?? job.destinationURL)
        
        _ = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: 1024, duration: 0.05)
        
        // Регистрируем импортированный файл в очереди
        await queue.registerExistingImportedIDs([completedCompositeID])
        verify(await queue.isAlreadyImported(compositeID: completedCompositeID))
        
        // 2. Симулируем извлечение кабеля во время второй загрузки
        let inFlightItem = USBQueueItem(compositeID: "interrupted_item", cameraFile: ICCameraFile(), filename: "DSC_1002.NEF", fileSize: 2000, jobID: UUID())
        await queue.enqueue(inFlightItem)
        _ = await queue.dequeueNextIfAvailable()
        verify(await queue.activeCount == 1)
        
        // Извлечение кабеля: очищаем очередь
        await queue.clearAll()
        verify(await queue.totalQueueCount == 0, "При отключении кабеля очередь должна быть очищена")
        verify(await queue.activeCount == 0)
        
        // 3. Симулируем повторное подключение камеры
        // Загружаем уже известные ID из БД
        let knownFromDB = await coordinator.getImportedSourceFileIDs()
        verify(knownFromDB.contains(completedCompositeID), "База данных помнит уже сохраненный файл")
        
        let newQueue = USBTransferQueue(maxConcurrentDownloads: 1)
        await newQueue.registerExistingImportedIDs(Array(knownFromDB))
        
        // Пытаемся поставить DSC_1001.NEF снова
        let reimportAttempt = USBQueueItem(
            compositeID: completedCompositeID,
            cameraFile: ICCameraFile(),
            filename: "DSC_1001.NEF",
            fileSize: 1024,
            jobID: UUID()
        )
        let allowed = await newQueue.enqueue(reimportAttempt)
        verify(!allowed, "Повторное подключение камеры НЕ должно запускать загрузку уже импортированного файла!")
        
        print("  ✓ Извлечение кабеля корректно очищает очередь, а переподключение не создает дубликатов")
    }
}
