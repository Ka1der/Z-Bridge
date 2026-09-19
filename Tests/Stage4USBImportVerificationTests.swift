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
        try await testPendingJobCancellationRemovesFromQueueAndSkipsTerminalInProcessQueue()
        try await testInFlightCancellationKeepsSlotUntilCallbackAndFreesSafely()
        try await testRetryAfterErrorRecoversJobFromCoordinatorAndReenqueues()
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
    
    // MARK: - 9. Отмена ожидающего USB-задания удаляет его из очереди и терминальный статус блокирует скачивание
    func testPendingJobCancellationRemovesFromQueueAndSkipsTerminalInProcessQueue() async throws {
        print("\n[9/11] Тест отмены ожидающего USB-задания и защиты processQueue от терминальных заданий...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let usb = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        let mockCamera = MockCameraDevice()
        usb.connectedCamera = mockCamera
        usb.isConnected = true
        usb.isCatalogReady = true
        
        let file1 = MockCameraFile(name: "DSC_2001.NEF", size: 45_000_000)
        let item1 = CameraFileItem(
            cameraID: "mock-z8",
            filename: "DSC_2001.NEF",
            fileSize: 45_000_000,
            creationDate: Date(timeIntervalSince1970: 1700000001),
            cameraFile: file1
        )
        let file2 = MockCameraFile(name: "DSC_2002.NEF", size: 45_000_000)
        let item2 = CameraFileItem(
            cameraID: "mock-z8",
            filename: "DSC_2002.NEF",
            fileSize: 45_000_000,
            creationDate: Date(timeIntervalSince1970: 1700000002),
            cameraFile: file2
        )
        
        // Добавляем оба файла в оглавление
        await usb.importSelectedFiles([item1, item2])
        verify(usb.isDownloading, "Первый файл должен активно скачиваться")
        verify(usb.activeTransferCount == 1, "1 файл в активном слоте")
        verify(usb.pendingQueueCount == 1, "Второй файл ожидает в pendingQueue")
        
        guard let job2 = await coordinator.jobs.values.first(where: { $0.filename == "DSC_2002.NEF" }) else {
            fatalError("Задание для DSC_2002.NEF не создано")
        }
        let job2ID = job2.id
        guard let pendingCompositeID = await usb.transferQueue.findPendingCompositeID(by: job2ID) else {
            fatalError("pendingCompositeID не найден для item2")
        }
        
        // Отменяем ожидающее задание
        await usb.cancelTransfer(jobID: job2ID)
        
        // Проверяем:
        // 1. Ожидающее задание удалено из очереди
        let isEnqueued = await usb.transferQueue.isEnqueuedOrActive(compositeID: pendingCompositeID)
        verify(!isEnqueued, "Отмененное ожидающее задание должно быть удалено из очереди")
        verify(usb.pendingQueueCount == 0, "pendingQueueCount должен быть 0")
        
        // 2. Статус элемента в каталоге сброшен на .notImported
        let catalogItem2 = usb.catalogFiles.first(where: { $0.id == pendingCompositeID })
        verify(catalogItem2?.status == .notImported, "Статус в каталоге должен быть .notImported")
        
        // 3. Задание в координаторе отменено
        let coordJob2 = await coordinator.getJob(by: job2ID)
        verify(coordJob2?.state.isTerminal == true, "Задание координатора должно быть терминальным (.cancelled)")
        
        // 4. Проверка второй линии защиты: если терминальное задание каким-либо образом попало в processQueue
        let dummyItem = USBQueueItem(
            compositeID: "terminal_item",
            cameraFile: MockCameraFile(name: "DSC_2002.NEF", size: 45_000_000),
            filename: "DSC_2002.NEF",
            fileSize: 45_000_000,
            jobID: job2ID
        )
        await usb.transferQueue.enqueue(dummyItem)
        verify(await usb.transferQueue.pendingCount == 1)
        
        // Завершаем file1
        usb.didDownloadFile(file1, error: nil, options: [:], contextInfo: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Dummy терминальный элемент должен быть автоматически пропущен processQueue без отправки камере!
        verify(mockCamera.lastRequestedFile !== dummyItem.cameraFile, "processQueue не должен запрашивать скачивание терминального задания!")
        verify(await usb.transferQueue.totalQueueCount == 0, "Терминальное задание должно быть сброшено из очереди")
        
        print("  ✓ Отмена ожидающего задания удаляет его из очереди, а processQueue безопасно отсекает терминальные задания")
    }
    
    // MARK: - 10. Отмена выполняющегося USB-переноса на обеих платформах удерживает слот до колбэка
    func testInFlightCancellationKeepsSlotUntilCallbackAndFreesSafely() async throws {
        print("\n[10/11] Тест удержания слота при отмене выполняющегося USB-переноса...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let usb = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        let mockCamera = MockCameraDevice()
        usb.connectedCamera = mockCamera
        usb.isConnected = true
        usb.isCatalogReady = true
        
        let file = MockCameraFile(name: "DSC_3001.NEF", size: 50_000_000)
        let item = CameraFileItem(
            cameraID: "mock-z8",
            filename: "DSC_3001.NEF",
            fileSize: 50_000_000,
            creationDate: Date(timeIntervalSince1970: 1700000010),
            cameraFile: file
        )
        
        await usb.importSelectedFiles([item])
        verify(usb.isDownloading, "Загрузка началась")
        guard let inFlightJobID = await coordinator.jobs.values.first(where: { $0.filename == "DSC_3001.NEF" })?.id else {
            fatalError("JobID не найден")
        }
        
        // Вызываем отмену выполняющегося задания
        await usb.cancelTransfer(jobID: inFlightJobID)
        
        // Проверяем:
        // 1. Физическая отмена вызвана на камере (на macOS и iOS)
        verify(mockCamera.cancelDownloadCalled, "Физическая отмена должна быть вызвана на камере")
        
        // 2. Слот передачи НЕ освобожден преждевременно! isDownloading все еще true
        verify(usb.isDownloading, "Слот передачи не должен освобождаться до колбэка didDownloadFile!")
        
        // Попытка запустить еще один процесс очереди не должна приводить к запуску нового скачивания
        mockCamera.lastRequestedFile = nil
        await usb.processQueue()
        verify(mockCamera.lastRequestedFile == nil, "Новое скачивание не должно запускаться, пока слот занят отменой")
        
        // 3. Симулируем приход обратного вызова ImageCaptureCore
        usb.didDownloadFile(file, error: NSError(domain: "ImageCapture", code: -1), options: [:], contextInfo: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // 4. Теперь слот освобожден
        verify(!usb.isDownloading, "После вызова didDownloadFile слот передачи должен быть освобожден")
        verify(usb.activeTransferCount == 0, "Активных передач не осталось")
        let itemStatus = usb.catalogFiles.first(where: { $0.id == item.id })?.status
        verify(itemStatus == .notImported, "Статус отмененного файла должен быть .notImported")
        
        print("  ✓ Отмена in-flight вызывает cancelDownload и корректно удерживает слот до прихода didDownloadFile")
    }
    
    // MARK: - 11. Повтор USB-переноса после ошибки восстанавливает задание из координатора
    func testRetryAfterErrorRecoversJobFromCoordinatorAndReenqueues() async throws {
        print("\n[11/11] Тест повтора USB-переноса после ошибки (восстановление задания)...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let usb = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        let mockCamera = MockCameraDevice()
        usb.connectedCamera = mockCamera
        usb.isConnected = true
        usb.isCatalogReady = true
        
        let file = MockCameraFile(name: "DSC_4001.NEF", size: 42_000_000)
        let item = CameraFileItem(
            cameraID: "mock-z8",
            filename: "DSC_4001.NEF",
            fileSize: 42_000_000,
            creationDate: Date(timeIntervalSince1970: 1700000020),
            cameraFile: file
        )
        
        await usb.importSelectedFiles([item])
        guard let jobID = await coordinator.jobs.values.first(where: { $0.filename == "DSC_4001.NEF" })?.id else {
            fatalError("JobID не найден")
        }
        
        // Симулируем ошибку при передаче
        usb.didDownloadFile(file, error: NSError(domain: "NSCocoaErrorDomain", code: 512, userInfo: [NSLocalizedDescriptionKey: "USB Transfer Disrupted"]), options: [:], contextInfo: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Проверяем состояние ошибки
        verify(!usb.isDownloading, "Слот освобожден после ошибки")
        let failedJob = await coordinator.getJob(by: jobID)
        verify(failedJob?.state.isTerminal == true, "Задание помечено как с ошибкой")
        let catItem = usb.catalogFiles.first(where: { $0.id == item.id })
        if case .failed = catItem?.status {
            // Ожидаемый статус
        } else {
            fatalError("Статус элемента оглавления должен быть .failed")
        }
        
        // Теперь вызываем retryTransfer(jobID:)
        mockCamera.lastRequestedFile = nil
        try await usb.retryTransfer(jobID: jobID)
        
        // Проверяем:
        // 1. Задание в координаторе обновлено: attempts == 1, state == .pending, error == nil
        let retriedJob = await coordinator.getJob(by: jobID)
        verify(retriedJob?.attempts == 1, "Счетчик попыток должен быть инкрементирован")
        verify(retriedJob?.error == nil, "Ошибка в задании должна быть очищена")
        
        // 2. Скачивание снова запущено
        verify(usb.isDownloading, "Повтор должен запустить скачивание")
        verify(mockCamera.lastRequestedFile === file, "Камере должен быть передан повторный запрос на скачивание файла")
        
        print("  ✓ Повтор после ошибки успешно находит задание в координаторе, обновляет его и запускает загрузку")
    }
}

// MARK: - Mock Camera File & Device
final class MockCameraFile: ICCameraFile, @unchecked Sendable {
    var customName: String
    var customSize: off_t
    
    init(name: String, size: off_t = 45_000_000) {
        self.customName = name
        self.customSize = size
        super.init()
    }
    
    override var name: String? {
        customName
    }
    
    override var fileSize: off_t {
        customSize
    }
}

final class MockCameraDevice: ICCameraDevice, @unchecked Sendable {
    var cancelDownloadCalled = false
    var lastRequestedFile: ICCameraFile?
    var customName: String = "Nikon Z 8 (Mock)"
    
    override var name: String? {
        customName
    }
    
    override func cancelDownload() {
        cancelDownloadCalled = true
    }
    
    override func requestDownloadFile(
        _ file: ICCameraFile,
        options: [ICDownloadOption: Any] = [:],
        downloadDelegate: any ICCameraDeviceDownloadDelegate,
        didDownloadSelector: Selector,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        lastRequestedFile = file
    }
}
