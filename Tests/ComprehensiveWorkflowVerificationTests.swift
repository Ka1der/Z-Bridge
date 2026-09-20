import Foundation
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
struct ComprehensiveWorkflowVerificationMain {
    static func main() async throws {
        print("=== СТАРТ КОМПЛЕКСНОЙ ПРОВЕРКИ 6 КЛЮЧЕВЫХ СЦЕНАРИЕВ NIKONZBRIDGE ===")
        
        let suite = ComprehensiveWorkflowVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ 6 ПОВЕДЕНЧЕСКИХ СЦЕНАРИЕВ УСПЕШНО ВЕРИФИЦИРОВАНЫ! ===")
    }
}

@MainActor
final class ComprehensiveWorkflowVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WorkflowTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("workflow_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        defer { try? FileManager.default.removeItem(at: tempBaseURL) }
        
        try await testInitialSessionSelectionAndHistoryPreservation()
        try await testCatalogReadinessBeforeImport()
        try await testIndependenceOfManualImportAndLiveTethering()
        try await testDuplicateJobProtectionAndDeduplication()
        try await testErrorCancellationRetryAndSessionAffinity()
        try await testRAWJPEGGroupingFiltersCullingAndExport()
    }
    
    // MARK: - 1. Выбор стартовой сессии и сохранность истории
    func testInitialSessionSelectionAndHistoryPreservation() async throws {
        print("\n--- [1/6] Тест: Выбор стартовой сессии и сохранность истории ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        
        // Создаем две исторические сессии в базе данных
        let session1 = try await storage.createNewSession(named: "Historical_Shoot_01")
        await database.upsertSession(session1, isActive: false)
        let asset1 = MediaAsset(sessionID: session1.id, filename: "HIST_01.NEF", fileURL: session1.folderURL.appendingPathComponent("HIST_01.NEF"), format: MediaFormat(fileExtension: "nef"), fileSize: 25_000_000)
        await database.upsertAsset(asset1)
        
        let session2 = try await storage.createNewSession(named: "Historical_Shoot_02")
        await database.upsertSession(session2, isActive: true)
        let asset2 = MediaAsset(sessionID: session2.id, filename: "HIST_02.NEF", fileURL: session2.folderURL.appendingPathComponent("HIST_02.NEF"), format: MediaFormat(fileExtension: "nef"), fileSize: 30_000_000)
        await database.upsertAsset(asset2)
        
        // Сценарий A: Запуск с resumeLastSession: false (старт с пустой сессии по умолчанию)
        try await coordinator.bootstrapForLaunch(resumeLastSession: false)
        
        // Проверяем: создана новая чистая сессия
        let activeIdA = await coordinator.activeSession.id
        let assetsA = await coordinator.assets
        verify(activeIdA != session1.id, "При resumeLastSession: false активная сессия не должна быть Session 1")
        verify(activeIdA != session2.id, "При resumeLastSession: false активная сессия не должна быть Session 2")
        verify(assetsA.isEmpty, "Новая сессия должна быть пустой (0 ассетов)")
        
        // Но история НЕ удалена! Все исторические сессии сохранены в SQLite и координаторе
        let allSessions = await database.getAllSessions()
        verify(allSessions.contains(where: { $0.id == session1.id }), "Session 1 сохранена в истории SQLite")
        verify(allSessions.contains(where: { $0.id == session2.id }), "Session 2 сохранена в истории SQLite")
        
        // Сценарий B: Переключение на историческую сессию восстанавливает ее кадры и статистику
        let switched = await coordinator.switchActiveSession(to: session1.id)
        let assetsSwitched = await coordinator.assets
        verify(switched?.id == session1.id, "Успешное переключение на Session 1")
        verify(assetsSwitched.count == 1, "Ассеты Session 1 восстановлены")
        verify(assetsSwitched[0].filename == "HIST_01.NEF", "Восстановлен правильный файл")
        
        let stats1 = await coordinator.getSessionStats(id: session1.id)
        verify(stats1.filesCount == 1, "Статистика Session 1: 1 ассет")
        verify(stats1.totalBytes == 25_000_000, "Статистика Session 1: 25 МБ")
        
        // Сценарий C: Запуск с resumeLastSession: true (продолжение последней сессии)
        let coordinatorResume = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        try await coordinatorResume.bootstrapForLaunch(resumeLastSession: true)
        let activeIdResume = await coordinatorResume.activeSession.id
        let assetsResume = await coordinatorResume.assets
        verify(activeIdResume == session1.id, "При resumeLastSession: true возобновлена последняя активная сессия")
        verify(assetsResume.count == 1, "Кадры возобновленной сессии на месте")
        
        print("  [✓] Стартовая сессия и полная сохранность истории верифицированы.")
    }
    
    // MARK: - 2. Готовность каталога перед началом импорта
    func testCatalogReadinessBeforeImport() async throws {
        print("\n--- [2/6] Тест: Готовность каталога перед началом импорта ---")
        
        // 1. Камера отключена
        let disconnectedState = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .disconnected,
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(disconnectedState.emptyState?.kind == .disconnected, "При .disconnected состояние .disconnected")
        
        // 2. Камера подключена, но оглавление карты вычитывается (!isCatalogReady)
        // Камера физически есть, но импортировать НЕЛЬЗЯ
        let readingState = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .enumeratingCatalog(name: "Nikon Z 8", itemsFound: 15),
            isCatalogReady: false,
            catalogTotalCount: 15,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(readingState.emptyState?.kind == .readingCard, "Пока каталог не готов, статус строго .readingCard")
        verify(readingState.emptyState?.primaryAction == nil, "Пока каталог не готов, действие импорта ЗАПРЕЩЕНО (primaryAction == nil)")
        
        // 3. Каталог готов, но карта пуста (0 файлов)
        let emptyCardState = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .ready(name: "Nikon Z 9", totalItems: 0),
            isCatalogReady: true,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(emptyCardState.emptyState?.kind == .cardEmptyOrNoMatchingFiles, "Пустая карта дает .cardEmptyOrNoMatchingFiles")
        verify(emptyCardState.emptyState?.description.contains("нет файлов") == true, "Описание указывает на пустую карту")
        
        // 4. Каталог готов, есть доступные файлы -> только ТЕПЕРЬ готов к импорту!
        let readyState = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .ready(name: "Nikon Z 9", totalItems: 10),
            isCatalogReady: true,
            catalogTotalCount: 10,
            catalogUnimportedCount: 8,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(readyState.emptyState?.kind == .cardReady, "Только при готовности каталога вид .cardReady")
        verify(readyState.emptyState?.primaryAction?.type == .importAllFromCard, "Кнопка «Загрузить с камеры» становится доступной")
        
        print("  [✓] Разделение подключения и готовности каталога карты верифицировано.")
    }
    
    // MARK: - 3. Независимость ручного импорта и автозагрузки новых кадров
    func testIndependenceOfManualImportAndLiveTethering() async throws {
        print("\n--- [3/6] Тест: Независимость ручного импорта и автозагрузки новых кадров ---")
        
        let appState = AppState()
        let usb = appState.currentUSBManager
        
        // Включаем live tethering и выключаем автозагрузку карты
        usb.isAutoDownloadNewShotsEnabled = true
        usb.isAutoDownloadCardOnConnectEnabled = false
        
        verify(UserDefaults.standard.bool(forKey: USBCameraManager.autoDownloadNewShotsKey) == true, "Live tethering сохранен в UserDefaults")
        verify(UserDefaults.standard.bool(forKey: USBCameraManager.autoDownloadCardOnConnectKey) == false, "Auto download card сохранен в UserDefaults")
        
        // Заполняем каталог файлами для ручного импорта
        let item1 = CameraFileItem(cameraID: "CAM_Z9", filename: "MAN_01.NEF", fileSize: 1000, status: .notImported)
        let item2 = CameraFileItem(cameraID: "CAM_Z9", filename: "MAN_02.NEF", fileSize: 1000, status: .notImported)
        usb.catalogFiles = [item1, item2]
        usb.isCatalogReady = true
        
        // Ручной выбор и запуск импорта НЕ должен затрагивать флаги автозагрузки!
        await usb.importSelectedFiles([item1])
        
        verify(usb.isAutoDownloadNewShotsEnabled == true, "Ручной импорт НЕ изменил тумблер live tethering")
        verify(usb.isAutoDownloadCardOnConnectEnabled == false, "Ручной импорт НЕ изменил тумблер автозагрузки карты")
        
        print("  [✓] Независимость ручного импорта и автозагрузки подтверждена.")
    }
    
    // MARK: - 4. Защиту от повторных заданий (Deduplication)
    func testDuplicateJobProtectionAndDeduplication() async throws {
        print("\n--- [4/6] Тест: Защита от повторных заданий и сессионная дедупликация ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        
        let sessionA = try await storage.createNewSession(named: "Dedup_Session_A")
        await database.upsertSession(sessionA, isActive: true)
        await coordinator.switchActiveSession(to: sessionA.id)
        
        // Первый импорт кадра
        let assetA = MediaAsset(
            sessionID: sessionA.id,
            filename: "DSC_9999.NEF",
            fileURL: sessionA.folderURL.appendingPathComponent("DSC_9999.NEF"),
            format: MediaFormat(fileExtension: "nef"),
            fileSize: 45_000_000
        )
        await database.upsertAsset(assetA)
        
        // 1. Проверка дедупликации в активной сессии:
        let isDupA = await coordinator.isAssetAlreadyImported(sourceFileID: "FILE_9999", filename: "DSC_9999.NEF", fileSize: 45_000_000)
        verify(isDupA == true, "Кадр DSC_9999.NEF должен распознаваться как уже импортированный")
        
        let notDupA = await coordinator.isAssetAlreadyImported(sourceFileID: "FILE_NEW", filename: "DSC_9998.NEF", fileSize: 45_000_000)
        verify(notDupA == false, "Новый кадр не должен блокироваться")
        
        // 2. Сессионная изоляция дедупликации:
        // В новой сессии Session B этот же кадр еще не импортирован и доступен для съемки/импорта
        let sessionB = try await storage.createNewSession(named: "Dedup_Session_B")
        await database.upsertSession(sessionB, isActive: true)
        await coordinator.switchActiveSession(to: sessionB.id)
        
        let isDupB = await coordinator.isAssetAlreadyImported(sourceFileID: "FILE_9999", filename: "DSC_9999.NEF", fileSize: 45_000_000)
        verify(isDupB == false, "В другой сессии Session B кадр DSC_9999.NEF доступен для импорта")
        
        print("  [✓] Защита от повторных заданий и сессионная изоляция подтверждены.")
    }
    
    // MARK: - 5. Ошибку, отмену, повтор и привязку задания к сессии
    func testErrorCancellationRetryAndSessionAffinity() async throws {
        print("\n--- [5/6] Тест: Ошибка, отмена, повтор и жесткая привязка задания к сессии ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        let appState = AppState(coordinator: coordinator)
        
        let sessionA = try await storage.createNewSession(named: "Affinity_A")
        await database.upsertSession(sessionA, isActive: true)
        await coordinator.switchActiveSession(to: sessionA.id)
        await appState.syncStateFromCoordinator()
        
        // Создаем задание в Session A
        let job = TransferJob(
            id: UUID(),
            source: CameraSource(id: "cam-z9", model: "Nikon Z 9", transportType: .usb),
            sourceFileID: "SHOT_404",
            destinationURL: sessionA.folderURL.appendingPathComponent("SHOT_404.NEF"),
            sessionID: sessionA.id,
            state: .inProgress(progress: 0.1, bytesTransferred: 1000, totalBytes: 10000),
            progress: 0.1,
            transferredBytes: 1000,
            totalBytes: 10000
        )
        await coordinator.upsertJobForTesting(job)
        await appState.syncStateFromCoordinator()
        
        // 1. Отмена задания через UI AppState
        appState.cancelJob(id: job.id)
        var cancelledJob: TransferJob?
        for _ in 1...10 {
            try? await Task.sleep(nanoseconds: 30_000_000)
            cancelledJob = await coordinator.getJob(id: job.id)
            if cancelledJob?.state == .cancelled { break }
        }
        verify(cancelledJob?.state == .cancelled, "Задание должно перейти в .cancelled")
        
        // 2. Повтор задания
        let retriedJob = try await coordinator.prepareJobForRetry(jobID: job.id)
        verify(retriedJob.state == .pending, "После повтора задание перешло в .pending")
        verify(retriedJob.attempts == 1, "Счетчик попыток увеличился")
        verify(retriedJob.error == nil, "Ошибка сброшена")
        
        // 3. Ошибка передачи
        await coordinator.failTransfer(jobID: job.id, error: .verificationFailed("Checksum mismatch: expected ABC, actual DEF"))
        let failedJob = await coordinator.getJob(id: job.id)
        verify(failedJob?.state.isFailed == true, "Задание перешло в статус сбоя")
        
        // 4. ЖЕСТКАЯ ПРИВЯЗКА К СЕССИИ (Session Affinity):
        // Переключаем активную сессию на Session B во время выполнения задания
        let sessionB = try await storage.createNewSession(named: "Affinity_B")
        await database.upsertSession(sessionB, isActive: true)
        await coordinator.switchActiveSession(to: sessionB.id)
        
        // Создаем временный файл staging для финализации
        let stagingURL = sessionA.folderURL.appendingPathComponent(".staging_test.tmp")
        try Data("EXIF_NEF_DATA".utf8).write(to: stagingURL)
        
        let completingJob = TransferJob(
            id: UUID(),
            source: CameraSource(id: "cam-z9", model: "Nikon Z 9", transportType: .usb),
            sourceFileID: "SHOT_FINAL",
            destinationURL: sessionA.folderURL.appendingPathComponent("SHOT_FINAL.NEF"),
            stagingURL: stagingURL,
            sessionID: sessionA.id, // ЖЕСТКО ПРИВЯЗАНО К СЕССИИ А!
            state: .inProgress(progress: 1.0, bytesTransferred: 13, totalBytes: 13),
            totalBytes: 13
        )
        await coordinator.upsertJobForTesting(completingJob)
        
        // Финализируем перенос
        try await coordinator.finalizeTransfer(jobID: completingJob.id, actualSize: 13, duration: 0.1)
        
        // Проверяем: файл сохранен в папке Session A!
        let finalPathInA = sessionA.folderURL.appendingPathComponent("SHOT_FINAL.NEF")
        verify(FileManager.default.fileExists(atPath: finalPathInA.path), "Файл должен быть перемещен в папку Session A")
        
        // Запись в SQLite принадлежит Session A!
        let assetsA = await database.getAssets(for: sessionA.id)
        verify(assetsA.contains(where: { $0.filename == "SHOT_FINAL.NEF" }), "Ассет зарегистрирован в Session A")
        
        // Session B чиста и не загрязнена чужим файлом!
        let assetsB = await database.getAssets(for: sessionB.id)
        verify(!assetsB.contains(where: { $0.filename == "SHOT_FINAL.NEF" }), "Session B не должна содержать ассет из Session A")
        
        print("  [✓] Отмена, повтор, обработка ошибок и привязка к сессии верифицированы.")
    }
    
    // MARK: - 6. RAW+JPEG-группировка, фильтры, отбор и экспорт
    func testRAWJPEGGroupingFiltersCullingAndExport() async throws {
        print("\n--- [6/6] Тест: RAW+JPEG-группировка, фильтры, отбор и экспорт ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        let appState = AppState(coordinator: coordinator)
        
        let session = try await storage.createNewSession(named: "Culling_Export_Session")
        await database.upsertSession(session, isActive: true)
        await coordinator.switchActiveSession(to: session.id)
        
        // 1. RAW + JPEG группировка
        let nefFile = session.folderURL.appendingPathComponent("DSC_7777.NEF")
        let jpgFile = session.folderURL.appendingPathComponent("DSC_7777.JPG")
        try Data("RAW_DATA".utf8).write(to: nefFile)
        try Data("JPG_DATA".utf8).write(to: jpgFile)
        
        let rawAsset = MediaAsset(sessionID: session.id, filename: "DSC_7777.NEF", fileURL: nefFile, format: MediaFormat(fileExtension: "nef"), fileSize: 8)
        let jpgAsset = MediaAsset(sessionID: session.id, filename: "DSC_7777.JPG", fileURL: jpgFile, format: MediaFormat(fileExtension: "jpg"), fileSize: 8)
        
        await database.upsertAsset(rawAsset)
        await database.upsertAsset(jpgAsset)
        
        await coordinator.switchActiveSession(to: session.id)
        await appState.syncStateFromCoordinator()
        
        verify(appState.captureGroups.count == 1, "RAW и JPEG должны объединиться в одну группу")
        let group = appState.captureGroups[0]
        verify(group.hasBothRawAndJpeg == true, "Группа должна быть парной (hasBothRawAndJpeg == true)")
        verify(group.rawAsset != nil && group.jpegAsset != nil, "Группа содержит и RAW, и JPEG")
        
        // 2. Отбор (Culling)
        appState.setRating(5, for: group)
        appState.setPickStatus(.picked, for: group)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        verify(appState.captureGroups[0].rating == 5, "Рейтинг группы стал 5")
        verify(appState.captureGroups[0].pickStatus == .picked, "Статус группы стал .picked")
        
        // Проверяем каскадное обновление в базе данных для обоих файлов пары
        let dbAssets = await database.getAssets(for: session.id)
        for a in dbAssets {
            verify(a.rating == 5, "Рейтинг файла \(a.filename) в БД обновлен каскадно")
            verify(a.pickStatus == .picked, "Флаг файла \(a.filename) в БД обновлен каскадно")
        }
        
        // 3. Фильтры
        appState.ratingFilter = .stars5Only
        verify(appState.filteredGroups.count == 1, "Фильтр 5 звезд включает группу")
        
        appState.ratingFilter = .unrated
        verify(appState.filteredGroups.count == 0, "Фильтр без рейтинга исключает 5-звездочную группу")
        
        appState.ratingFilter = .all
        appState.pickFilter = .picked
        verify(appState.filteredGroups.count == 1, "Фильтр Pick включает группу")
        
        appState.pickFilter = .rejected
        verify(appState.filteredGroups.count == 0, "Фильтр Reject исключает группу")
        appState.pickFilter = .all
        
        // 4. Экспорт с XMP-сайдкаром и гарантией сохранности оригиналов
        let exportDir = tempBaseURL.appendingPathComponent("Export_Output", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        
        let allAssetsInSession = await database.getAssets(for: session.id)
        guard let updatedRAW = allAssetsInSession.first(where: { $0.filename == "DSC_7777.NEF" }) else {
            fatalError("Обновленный RAW ассет не найден в базе данных")
        }
        
        let exportItemRAW = ExportItem(asset: updatedRAW)
        let exportJob = ExportJob(
            destination: .directory(url: exportDir, bookmarkData: nil),
            items: [exportItemRAW],
            formatSelection: .rawOnly,
            includeXMPSidecars: true
        )
        
        let exportManager = ExportManager(diskGuard: diskGuard)
        let result = await exportManager.executeJob(exportJob)
        
        verify(result.state.isCompleted == true, "Экспорт должен завершиться успешно")
        let exportedRAW = exportDir.appendingPathComponent("DSC_7777.NEF")
        let exportedXMP = exportDir.appendingPathComponent("DSC_7777.xmp")
        
        verify(FileManager.default.fileExists(atPath: exportedRAW.path), "RAW файл экспортирован")
        verify(FileManager.default.fileExists(atPath: exportedXMP.path), "XMP сайдкар создан рядом с файлом")
        
        // Проверяем содержимое XMP
        let xmpContent = try String(contentsOf: exportedXMP, encoding: .utf8)
        verify(xmpContent.contains("xmp:Rating=\"5\""), "XMP содержит рейтинг 5")
        verify(xmpContent.contains("photoshop:Urgency=\"1\""), "XMP содержит Urgency=1 (Pick)")
        
        // Оригинал в сессии не пострадал
        let originalContent = try String(contentsOf: nefFile, encoding: .utf8)
        verify(originalContent == "RAW_DATA", "Оригинал в каталоге сессии остался неизменным")
        
        print("  [✓] Группировка RAW+JPEG, отбор, фильтры и экспорт с XMP верифицированы.")
    }
}
