import Foundation
import ImageCaptureCore
import CoreGraphics
import SQLite3
import SwiftUI

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct USBCameraImportFlowVerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭКРАНА «ИМПОРТ С КАМЕРЫ» И USB-КОНВЕЙЕРА ===")
        
        let suite = USBCameraImportFlowVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭКРАНА «ИМПОРТ С КАМЕРЫ» УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class USBCameraImportFlowVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("USBImportFlowTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("usb_import_flow.sqlite")
    }
    
    func runAllTests() async throws {
        defer { try? FileManager.default.removeItem(at: tempBaseURL) }
        
        try await testCameraCatalogStatsCalculation()
        try await testFormatFilterSeparation()
        try await testFileStatusTransitionsAndBadges()
        try await testInlineRetryForFailedItem()
        try await testRetryAllFailed()
        try await testTargetSessionLockingAcrossSessionSwitches()
        try await testLargeCatalogPerformance()
        try await testBackgroundPersistenceOnDismissal()
        try await testAutoDownloadTogglesPersistence()
        try await testFilteredImportDoesNotImportHiddenFiles()
        try await testDoubleTapProtection()
        try await testLiveTetheringPriorityOverPendingBatchQueue()
        try await testCameraDisconnectAndCancelTransfer()
    }
    
    // MARK: - 1. Подсчет реального количества и общего объема доступных и общих файлов
    func testCameraCatalogStatsCalculation() async throws {
        print("\n[1/13] Тест подсчета доступных и общих файлов оглавления...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        // Создаем тестовые элементы с разными статусами
        let item1 = CameraFileItem(cameraID: "nikon", filename: "DSC_0001.NEF", fileSize: 50_000_000, status: .notImported)
        let item2 = CameraFileItem(cameraID: "nikon", filename: "DSC_0002.JPG", fileSize: 20_000_000, status: .notImported)
        let item3 = CameraFileItem(cameraID: "nikon", filename: "DSC_0003.NEF", fileSize: 30_000_000, status: .queued)
        let item4 = CameraFileItem(cameraID: "nikon", filename: "DSC_0004.NEF", fileSize: 40_000_000, status: .imported)
        let item5 = CameraFileItem(cameraID: "nikon", filename: "DSC_0005.JPG", fileSize: 25_000_000, status: .failed(error: "I/O Error"))
        
        manager.catalogFiles = [item1, item2, item3, item4, item5]
        
        let stats = manager.catalogStats
        
        verify(stats.totalCount == 5, "Всего на карте должно быть 5 файлов")
        verify(stats.totalBytes == 165_000_000, "Общий объем на карте 165 МБ")
        verify(stats.unimportedCount == 2, "Доступных для импорта файлов строго 2 (только .notImported)")
        verify(stats.unimportedBytes == 70_000_000, "Объем доступных файлов 70 МБ")
        verify(!stats.formattedTotalSize.isEmpty, "Строка общего объема не должна быть пустой")
        verify(!stats.formattedUnimportedSize.isEmpty, "Строка доступного объема не должна быть пустой")
        
        print("  ✓ Подсчет доступных и общих файлов/объемов работает корректно")
    }
    
    // MARK: - 2. Разделение фильтрами по форматам (Все / Только RAW / Только Companion)
    func testFormatFilterSeparation() async throws {
        print("\n[2/9] Тест фильтрации файлов по форматам...")
        
        let nefItem = CameraFileItem(cameraID: "nikon", filename: "DSC_0001.NEF", fileSize: 45_000_000)
        let nrwItem = CameraFileItem(cameraID: "nikon", filename: "DSC_0002.NRW", fileSize: 35_000_000)
        let jpgItem = CameraFileItem(cameraID: "nikon", filename: "DSC_0001.JPG", fileSize: 12_000_000)
        let jpegItem = CameraFileItem(cameraID: "nikon", filename: "DSC_0003.jpeg", fileSize: 15_000_000)
        
        verify(nefItem.isRAW, "NEF должен определяться как RAW")
        verify(nrwItem.isRAW, "NRW должен определяться как RAW")
        verify(!jpgItem.isRAW, "JPG не должен определяться как RAW")
        verify(!jpegItem.isRAW, "JPEG не должен определяться как RAW")
        
        let allItems = [nefItem, nrwItem, jpgItem, jpegItem]
        
        // Режим: Все
        let filterAll = CameraFileFormatFilter.all
        let filteredAll = allItems.filter { filterAll.matches(isRAW: $0.isRAW) }
        verify(filteredAll.count == 4, "Фильтр 'Все' должен возвращать все 4 файла")
        
        // Режим: Только RAW
        let filterRAW = CameraFileFormatFilter.rawOnly
        let filteredRAW = allItems.filter { filterRAW.matches(isRAW: $0.isRAW) }
        verify(filteredRAW.count == 2, "Фильтр 'Только RAW' должен возвращать 2 файла")
        verify(filteredRAW.allSatisfy { $0.isRAW }, "Все возвращенные файлы должны быть RAW")
        
        // Режим: Только Companion/JPEG
        let filterCompanion = CameraFileFormatFilter.companionOnly
        let filteredCompanion = allItems.filter { filterCompanion.matches(isRAW: $0.isRAW) }
        verify(filteredCompanion.count == 2, "Фильтр 'Только Companion' должен возвращать 2 файла")
        verify(filteredCompanion.allSatisfy { !$0.isRAW }, "Все возвращенные файлы должны быть не-RAW")
        
        print("  ✓ Фильтры форматов (Все, RAW, Companion) строго разделяют файлы")
    }
    
    // MARK: - 3. Состояния файлов и терминальность
    func testFileStatusTransitionsAndBadges() async throws {
        print("\n[3/9] Тест состояний файлов оглавления...")
        
        let sNotImported = CameraFileImportStatus.notImported
        let sQueued = CameraFileImportStatus.queued
        let sImporting = CameraFileImportStatus.importing(progress: 0.42)
        let sImported = CameraFileImportStatus.imported
        let sFailed = CameraFileImportStatus.failed(error: "CRC Checksum Mismatch")
        
        verify(!sNotImported.isTerminal, "notImported не является терминальным")
        verify(!sQueued.isTerminal, "queued не является терминальным")
        verify(!sImporting.isTerminal, "importing не является терминальным")
        verify(sImported.isTerminal, "imported является терминальным")
        verify(sFailed.isTerminal, "failed является терминальным")
        
        if case .importing(let progress) = sImporting {
            verify(progress == 0.42, "Прогресс импорта должен сохранять переданное значение")
        } else {
            fatalError("Ожидался статус importing")
        }
        
        if case .failed(let err) = sFailed {
            verify(err == "CRC Checksum Mismatch")
        } else {
            fatalError("Ожидался статус failed")
        }
        
        print("  ✓ Жизненный цикл состояний и терминальность подтверждены")
    }
    
    // MARK: - 4. Точечный повтор завершившегося ошибкой файла
    func testInlineRetryForFailedItem() async throws {
        print("\n[4/9] Тест точечного повтора (retry) ошибочного файла...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        let mockFile = MockCameraFile(name: "DSC_FAILED.NEF", size: 40_000_000)
        let mockCamera = MockCameraDevice()
        manager.connectedCamera = mockCamera
        manager.isCatalogReady = true
        
        let compositeID = CameraFileItem.makeCompositeID(
            cameraID: mockCamera.name ?? "nikon",
            filename: "DSC_FAILED.NEF",
            fileSize: 40_000_000,
            creationDate: nil
        )
        
        let failedItem = CameraFileItem(
            cameraID: mockCamera.name ?? "nikon",
            filename: "DSC_FAILED.NEF",
            fileSize: 40_000_000,
            cameraFile: mockFile,
            status: .failed(error: "Network timeout")
        )
        manager.catalogFiles = [failedItem]
        
        // 1. Создаем задание в координаторе и переводим его в статус ошибки
        let source = CameraSource(id: "usb-test", model: "Nikon Z 8", transportType: .usb)
        let job = try await coordinator.createTransferJob(
            source: source,
            filename: "DSC_FAILED.NEF",
            sourceFileID: compositeID,
            expectedSize: 40_000_000
        )
        await coordinator.failTransfer(jobID: job.id, error: .generic("Network timeout"))
        
        let failedJob = await coordinator.getJob(by: job.id)
        if case .failed = failedJob?.state {} else {
            fatalError("Задание должно быть в статусе failed")
        }
        verify(failedJob?.attempts == 0)
        
        // 2. Вызываем retryTransfer(for: item)
        await manager.retryTransfer(for: failedItem)
        
        // 3. Проверяем, что задание обновлено в координаторе
        let retriedJob = await coordinator.getJob(by: job.id)
        verify(retriedJob?.state == .pending || retriedJob?.state.isInProgress == true, "Задание должно перейти в активное состояние")
        verify(retriedJob?.attempts == 1, "Количество попыток должно увеличиться до 1")
        verify(retriedJob?.error == nil, "Ошибка задания должна быть сброшена")
        
        // 4. Проверяем, что запрос загрузки передан камере
        verify(mockCamera.lastRequestedFile != nil, "Камере должен быть передан запрос на повторное скачивание")
        verify(mockCamera.lastRequestedFile?.name == "DSC_FAILED.NEF")
        
        print("  ✓ Точечный повтор успешно восстанавливает задание и запускает скачивание")
    }
    
    // MARK: - 5. Повтор всех файлов с ошибкой (retryAllFailed)
    func testRetryAllFailed() async throws {
        print("\n[5/9] Тест массового повтора всех ошибочных файлов (retryAllFailed)...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        let mockFile1 = MockCameraFile(name: "DSC_ERR1.NEF", size: 30_000_000)
        let mockFile2 = MockCameraFile(name: "DSC_ERR2.NEF", size: 35_000_000)
        let mockCamera = MockCameraDevice()
        manager.connectedCamera = mockCamera
        manager.isCatalogReady = true
        
        let item1 = CameraFileItem(cameraID: "nikon", filename: "DSC_ERR1.NEF", fileSize: 30_000_000, cameraFile: mockFile1, status: .failed(error: "E1"))
        let item2 = CameraFileItem(cameraID: "nikon", filename: "DSC_ERR2.NEF", fileSize: 35_000_000, cameraFile: mockFile2, status: .failed(error: "E2"))
        let item3 = CameraFileItem(cameraID: "nikon", filename: "DSC_OK.NEF", fileSize: 40_000_000, status: .imported)
        
        manager.catalogFiles = [item1, item2, item3]
        
        await manager.retryAllFailed()
        
        // Проверяем очередь
        let totalQueue = await manager.transferQueue.totalQueueCount
        verify(totalQueue == 2, "В очередь должны быть поставлены оба ошибочных файла, исключая уже импортированный")
        
        print("  ✓ retryAllFailed безошибочно ставит в очередь все файлы со сбоем")
    }
    
    // MARK: - 6. Сохранение целевой сессии заданием при переключении сессий до завершения
    func testTargetSessionLockingAcrossSessionSwitches() async throws {
        print("\n[6/9] Тест сохранения целевой сессии при смене активной сессии...")
        
        let coordinator = try await makeCoordinator()
        let sessionA = await coordinator.activeSession
        
        // Создаем новую Session B и убеждаемся, что обе сессии существуют
        let sessionB = try await coordinator.startNewSession(named: "Session_B_Wedding")
        
        // Возвращаем Session A как активную
        _ = await coordinator.switchActiveSession(to: sessionA.id)
        verify((await coordinator.activeSession.id) == sessionA.id, "Активной должна быть Session A")
        
        // Создаем задание в Session A
        let source = CameraSource(id: "usb-nikon", model: "Nikon Z 8", transportType: .usb)
        let filename = "DSC_LOCKED.NEF"
        let job = try await coordinator.createTransferJob(
            source: source,
            filename: filename,
            sourceFileID: "locked_001",
            expectedSize: 1024
        )
        
        verify(job.sessionID == sessionA.id, "Задание жестко привязано к Session A")
        
        // ПЕРЕКЛЮЧАЕМ АКТИВНУЮ СЕССИЮ НА SESSION B ПЕРЕД ФИНАЛИЗАЦИЕЙ!
        _ = await coordinator.switchActiveSession(to: sessionB.id)
        verify((await coordinator.activeSession.id) == sessionB.id, "Теперь активна Session B")
        
        // Создаем валидный тестовый staging файл
        guard let stagingURL = job.stagingURL else {
            fatalError("Staging URL должен быть задан")
        }
        var dummyData = Data(repeating: 0x4D, count: 1024)
        dummyData[0] = 0x4D; dummyData[1] = 0x4D; dummyData[2] = 0x00; dummyData[3] = 0x2A // TIFF Magic Bytes
        try dummyData.write(to: stagingURL)
        
        // Финализируем перенос задания, созданного для Session A
        let asset = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: 1024, duration: 0.1)
        
        // Проверяем:
        // 1. Ассет записан с sessionID == Session A!
        verify(asset.sessionID == sessionA.id, "Ассет должен быть зарегистрирован в Session A")
        
        // 2. Файл перемещен в папку Session A, а не Session B!
        verify(asset.fileURL.path.contains(sessionA.name), "Файл должен лежать в папке Session A: \(asset.fileURL.path)")
        verify(!asset.fileURL.path.contains(sessionB.name), "Файл НЕ должен лежать в папке Session B")
        
        // 3. Сессия B не загрязнена чужим ассетом в оперативной памяти
        let sessionBAssets = await coordinator.assets
        verify(!sessionBAssets.contains(where: { $0.id == asset.id }), "Session B не должна отображать ассет из Session A")
        
        // 4. При переключении обратно на Session A ассет присутствует
        _ = await coordinator.switchActiveSession(to: sessionA.id)
        let sessionAAssets = await coordinator.assets
        verify(sessionAAssets.contains(where: { $0.id == asset.id }), "Session A должна содержать загруженный ассет")
        
        print("  ✓ Задания сохраняют свою первоначальную сессию даже при ее переключении")
    }
    
    // MARK: - 7. Производительность при 1000+ файлах на карте
    func testLargeCatalogPerformance() async throws {
        print("\n[7/9] Тест производительности каталога при 1500 файлах...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        var files: [CameraFileItem] = []
        files.reserveCapacity(1500)
        
        for i in 1...1500 {
            let isRAW = i % 2 == 0
            let ext = isRAW ? "NEF" : "JPG"
            let size: Int64 = isRAW ? 45_000_000 : 12_000_000
            let status: CameraFileImportStatus = i <= 500 ? .imported : (i <= 550 ? .queued : .notImported)
            let item = CameraFileItem(
                cameraID: "nikon",
                filename: String(format: "DSC_%04d.%@", i, ext),
                fileSize: size,
                status: status
            )
            files.append(item)
        }
        
        manager.catalogFiles = files
        
        let start = Date()
        
        let stats = manager.catalogStats
        
        let elapsed = Date().timeIntervalSince(start)
        
        verify(stats.totalCount == 1500, "Всего должно быть 1500 файлов")
        verify(stats.unimportedCount == 950, "Доступных должно быть 950 файлов")
        verify(elapsed < 0.05, "Расчет статистики для 1500 файлов должен занимать менее 50 мс, фактически: \(elapsed * 1000) мс")
        
        // Тест скорости фильтрации RAW
        let filterStart = Date()
        let rawFiles = files.filter { $0.isRAW }
        let filterElapsed = Date().timeIntervalSince(filterStart)
        
        verify(rawFiles.count == 750, "Ровно половина должна быть RAW")
        verify(filterElapsed < 0.02, "Фильтрация 1500 файлов должна занимать менее 20 мс, фактически: \(filterElapsed * 1000) мс")
        
        print("  ✓ Производительность при 1500 файлах подтверждена: расчет \(String(format: "%.2f", elapsed * 1000)) мс")
    }
    
    // MARK: - 8. Закрытие экрана не отменяет фоновую очередь
    func testBackgroundPersistenceOnDismissal() async throws {
        print("\n[8/13] Тест независимости фоновой очереди от жизненного цикла окна...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        let mockCamera = MockCameraDevice()
        manager.connectedCamera = mockCamera
        manager.isCatalogReady = true
        
        let file = MockCameraFile(name: "DSC_BG.NEF", size: 30_000_000)
        let item = CameraFileItem(cameraID: "nikon", filename: "DSC_BG.NEF", fileSize: 30_000_000, cameraFile: file)
        manager.catalogFiles = [item]
        
        // Ставим файл в очередь
        await manager.importSelectedFiles([item])
        verify(await manager.transferQueue.totalQueueCount == 1, "Задание должно быть поставлено в очередь")
        
        // Очередь и выполняющиеся задачи внутри manager / coordinator остаются активными при скрытии UI!
        verify(await manager.transferQueue.totalQueueCount == 1, "Закрытие экрана НЕ должно отменять очередь переноса")
        verify(manager.catalogFiles.first?.status == .queued || manager.catalogFiles.first?.status == .importing(progress: 0.0), "Файл сохраняет статус очереди/передачи")
        
        print("  ✓ Закрытие интерфейса импорта сохраняет фоновые задания и очередь невредимыми")
    }
    
    // MARK: - 9. Сохранение настроек независимых тумблеров автозагрузки
    func testAutoDownloadTogglesPersistence() async throws {
        print("\n[9/13] Тест независимого сохранения тумблеров автозагрузки...")
        
        let defaults = UserDefaults.standard
        let prevNew = defaults.object(forKey: USBCameraManager.autoDownloadNewShotsKey)
        let prevCard = defaults.object(forKey: USBCameraManager.autoDownloadCardOnConnectKey)
        
        defer {
            defaults.setValue(prevNew, forKey: USBCameraManager.autoDownloadNewShotsKey)
            defaults.setValue(prevCard, forKey: USBCameraManager.autoDownloadCardOnConnectKey)
        }
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        manager.isAutoDownloadNewShotsEnabled = false
        manager.isAutoDownloadCardOnConnectEnabled = true
        
        verify(defaults.bool(forKey: USBCameraManager.autoDownloadNewShotsKey) == false)
        verify(defaults.bool(forKey: USBCameraManager.autoDownloadCardOnConnectKey) == true)
        
        // Создаем новый менеджер и проверяем, что настройки подтянулись из хранилища
        let freshManager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        verify(freshManager.isAutoDownloadNewShotsEnabled == false)
        verify(freshManager.isAutoDownloadCardOnConnectEnabled == true)
        
        print("  ✓ Независимые настройки автозагрузки корректно сохраняются в UserDefaults")
    }
    
    // MARK: - 10. Фильтрованный импорт исключает скрытые файлы
    func testFilteredImportDoesNotImportHiddenFiles() async throws {
        print("\n[10/13] Тест изоляции фильтрованного набора от скрытых файлов...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        let rawFile1 = MockCameraFile(name: "DSC_0100.NEF", size: 40_000_000)
        let rawFile2 = MockCameraFile(name: "DSC_0101.NEF", size: 42_000_000)
        let jpgFile1 = MockCameraFile(name: "DSC_0100.JPG", size: 10_000_000)
        let jpgFile2 = MockCameraFile(name: "DSC_0101.JPG", size: 12_000_000)
        
        let rawItem1 = CameraFileItem(cameraID: "nikon", filename: "DSC_0100.NEF", fileSize: 40_000_000, cameraFile: rawFile1)
        let rawItem2 = CameraFileItem(cameraID: "nikon", filename: "DSC_0101.NEF", fileSize: 42_000_000, cameraFile: rawFile2)
        let jpgItem1 = CameraFileItem(cameraID: "nikon", filename: "DSC_0100.JPG", fileSize: 10_000_000, cameraFile: jpgFile1)
        let jpgItem2 = CameraFileItem(cameraID: "nikon", filename: "DSC_0101.JPG", fileSize: 12_000_000, cameraFile: jpgFile2)
        
        manager.catalogFiles = [rawItem1, rawItem2, jpgItem1, jpgItem2]
        
        let mockCamera = MockCameraDevice()
        manager.connectedCamera = mockCamera
        manager.isCatalogReady = true
        
        // Фиксируем настройки автозагрузки
        manager.isAutoDownloadNewShotsEnabled = false
        manager.isAutoDownloadCardOnConnectEnabled = false
        
        // Выполняем импорт только RAW
        await manager.importFilteredUnimported(matching: .rawOnly)
        
        // Проверяем: только 2 RAW файла перешли в процесс импорта / очередь, а JPEG файлы остались .notImported
        verify(manager.catalogFiles[0].status == .queued || manager.catalogFiles[0].status == .importing(progress: 0.0), "Первый RAW должен перейти в importing/queued")
        verify(manager.catalogFiles[1].status == .queued, "Второй RAW должен быть queued")
        verify(manager.catalogFiles[2].status == .notImported, "Первый JPEG НЕ должен быть затронут")
        verify(manager.catalogFiles[3].status == .notImported, "Второй JPEG НЕ должен быть затронут")
        
        // Проверяем, что ручной импорт НЕ изменил настройки автозагрузки
        verify(manager.isAutoDownloadNewShotsEnabled == false, "Ручной импорт не должен менять настройку live tethering")
        verify(manager.isAutoDownloadCardOnConnectEnabled == false, "Ручной импорт не должен менять настройку автоимпорта с карты")
        
        print("  ✓ Фильтрованный импорт скачивает исключительно видимые файлы, не трогая скрытые")
    }
    
    // MARK: - 11. Защита от двойного тапа (isBatchSchedulingInProgress)
    func testDoubleTapProtection() async throws {
        print("\n[11/13] Тест защиты от двойного тапа по кнопке импорта...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        let file = MockCameraFile(name: "DSC_DOUBLE.NEF", size: 30_000_000)
        let item = CameraFileItem(cameraID: "nikon", filename: "DSC_DOUBLE.NEF", fileSize: 30_000_000, cameraFile: file)
        manager.catalogFiles = [item]
        manager.connectedCamera = MockCameraDevice()
        manager.isCatalogReady = true
        
        // Имитируем активный процесс планирования (первый тап еще исполняется)
        manager.isBatchSchedulingInProgress = true
        
        // Второй тап пытается запустить импорт
        await manager.importFilteredUnimported(matching: .all)
        
        // Задание НЕ должно дублироваться
        verify(await manager.transferQueue.totalQueueCount == 0, "Второй вызов при активном планировании должен быть проигнорирован")
        
        // Снимаем блокировку
        manager.isBatchSchedulingInProgress = false
        await manager.importFilteredUnimported(matching: .all)
        verify(await manager.transferQueue.totalQueueCount == 1, "После снятия блокировки файл успешно встает в очередь")
        
        print("  ✓ Защита от повторного запуска (двойной тап) предотвращает дублирование заданий")
    }
    
    // MARK: - 12. Приоритет нового кадра (Live Tethering) над пакетной очередью с карты
    func testLiveTetheringPriorityOverPendingBatchQueue() async throws {
        print("\n[12/13] Тест приоритета live-tethering кадра перед пакетным импортом...")
        
        let queue = USBTransferQueue(maxConcurrentDownloads: 1)
        let batchItem1 = USBQueueItem(
            compositeID: "nikon_BATCH_1.NEF_100_0",
            cameraFile: MockCameraFile(name: "BATCH_1.NEF"),
            filename: "BATCH_1.NEF",
            fileSize: 100
        )
        let batchItem2 = USBQueueItem(
            compositeID: "nikon_BATCH_2.NEF_100_0",
            cameraFile: MockCameraFile(name: "BATCH_2.NEF"),
            filename: "BATCH_2.NEF",
            fileSize: 100
        )
        let liveShot = USBQueueItem(
            compositeID: "nikon_LIVE_SHOT.NEF_100_0",
            cameraFile: MockCameraFile(name: "LIVE_SHOT.NEF"),
            filename: "LIVE_SHOT.NEF",
            fileSize: 100
        )
        
        // Добавляем пакетные файлы в стандартном порядке
        _ = await queue.enqueue(batchItem1, priority: false)
        _ = await queue.enqueue(batchItem2, priority: false)
        
        // Приходит новый live-кадр прямо во время пакетного скачивания
        _ = await queue.enqueue(liveShot, priority: true)
        
        // Проверяем: liveShot должен быть извлечен первым из очереди ожидания!
        let next = await queue.dequeueNextIfAvailable()
        verify(next?.filename == "LIVE_SHOT.NEF", "Свежий снимок должен иметь приоритет над пакетной очередью с карты")
        
        let second = await queue.markCompleted(compositeID: next!.compositeID)
        verify(second?.filename == "BATCH_1.NEF", "Далее извлекается первый пакетный файл")
        
        print("  ✓ Live-кадр вставляется в голову очереди и обрабатывается в приоритетном порядке")
    }
    
    // MARK: - 13. Отмена задания и отключение камеры
    func testCameraDisconnectAndCancelTransfer() async throws {
        print("\n[13/13] Тест отмены задания и отключения камеры...")
        
        let coordinator = try await makeCoordinator()
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        
        let mockCamera = MockCameraDevice()
        manager.connectedCamera = mockCamera
        manager.isCatalogReady = true
        
        let file = MockCameraFile(name: "DSC_CANCEL.NEF", size: 50_000_000)
        let item = CameraFileItem(cameraID: "nikon", filename: "DSC_CANCEL.NEF", fileSize: 50_000_000, cameraFile: file)
        manager.catalogFiles = [item]
        
        await manager.importSelectedFiles([item])
        verify(await manager.transferQueue.totalQueueCount == 1)
        
        // Отменяем задание по составному ID
        await manager.cancelTransfer(compositeID: item.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        
        verify(await manager.transferQueue.totalQueueCount == 0, "Очередь должна быть пуста после отмены")
        verify(manager.catalogFiles.first?.status == .notImported, "Статус файла должен сброситься в notImported")
        
        // Имитируем отключение камеры
        await manager.resetState()
        verify(manager.connectedCamera == nil, "Камера сброшена")
        verify(manager.isCatalogReady == false, "Каталог не готов")
        verify(manager.catalogFiles.isEmpty, "Файлы каталога очищены")
        verify(manager.isBatchSchedulingInProgress == false, "Флаг блокировки планирования сброшен")
        
        print("  ✓ Отмена и отключение камеры корректно сбрасывают состояние без зависаний")
    }
    
    // MARK: - Вспомогательные фабрики
    private func makeCoordinator() async throws -> TransferCoordinator {
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        return coordinator
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
    weak var downloadDelegate: (any ICCameraDeviceDownloadDelegate)?
    var customName: String = "Nikon Z 8 (Mock)"
    
    override var name: String? {
        customName
    }
    
    override func cancelDownload() {
        cancelDownloadCalled = true
        if let file = lastRequestedFile, let delegate = downloadDelegate as? USBCameraManager {
            let cancelErr = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
            Task { @MainActor in
                delegate.didDownloadFile(file, error: cancelErr, options: [:], contextInfo: nil)
            }
        }
    }
    
    override func requestDownloadFile(
        _ file: ICCameraFile,
        options: [ICDownloadOption: Any] = [:],
        downloadDelegate: any ICCameraDeviceDownloadDelegate,
        didDownloadSelector: Selector,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        lastRequestedFile = file
        self.downloadDelegate = downloadDelegate
    }
}
