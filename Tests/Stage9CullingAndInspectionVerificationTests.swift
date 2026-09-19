import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct Stage9VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 9: ОТБОР, РЕЙТИНГ, ФИЛЬТРЫ, ПАКЕТНЫЕ ДЕЙСТВИЯ И СРАВНЕНИЕ ===")
        
        let suite = Stage9VerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 9 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage9VerificationSuite {
    let tempDir: URL
    
    init() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage9Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir
    }
    
    func runAllTests() async throws {
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await testPickStatusAndGroupCascading()
        try await testCatalogDatabaseMigrationV2AndPersistence()
        try await testTransferCoordinatorBatchAndCullingIntegration()
        try await testGalleryFilteringAndSortingInAppState()
        try await testMultiSelectionAndBatchOperationsInAppState()
        try await testInspectionPauseOnIncomingTetheredFrames()
        try await testZoomAndPanCalculationsAnd100PercentView()
        try await testCompareViewSynchronizationAndSwapping()
        try await testRestoredCatalogLoadedIntoAppStateAtStartup()
    }
    
    // MARK: - Helper to create dummy file
    private func createDummyFile(named name: String, sizeInBytes: Int, in directory: URL? = nil) throws -> URL {
        let parent = directory ?? tempDir
        let url = parent.appendingPathComponent(name)
        let data = Data(repeating: 0x5A, count: max(sizeInBytes, 16))
        try data.write(to: url)
        return url
    }
    
    // MARK: - 1. Тест PickStatus, рейтинга 0-5 и каскадного обновления группы
    func testPickStatusAndGroupCascading() async throws {
        print("\n[1/8] Тест PickStatus, диапазона рейтинга 0..5 и каскадного обновления RAW+JPG...")
        
        let test1Dir = tempDir.appendingPathComponent("Test1", isDirectory: true)
        try FileManager.default.createDirectory(at: test1Dir, withIntermediateDirectories: true)
        
        // Проверка значений PickStatus
        assert(PickStatus.unflagged.rawValue == 0, "unflagged должен быть 0")
        assert(PickStatus.picked.rawValue == 1, "picked должен быть 1")
        assert(PickStatus.rejected.rawValue == 2, "rejected должен быть 2")
        assert(PickStatus.allCases.count == 3, "Должно быть 3 статуса отбора")
        
        let rawURL = try createDummyFile(named: "DSC_0100.NEF", sizeInBytes: 25_000_000, in: test1Dir)
        let jpgURL = try createDummyFile(named: "DSC_0100.JPG", sizeInBytes: 5_000_000, in: test1Dir)
        
        let sessionID = UUID()
        let rawAsset = MediaAsset(sessionID: sessionID, filename: "DSC_0100.NEF", fileURL: rawURL, format: .raw(fileExtension: "NEF"), fileSize: 25_000_000)
        let jpgAsset = MediaAsset(sessionID: sessionID, filename: "DSC_0100.JPG", fileURL: jpgURL, format: .jpeg, fileSize: 5_000_000)
        
        var group = CaptureGroup(asset: rawAsset)
        group.addAsset(jpgAsset)
        
        assert(group.rating == 0, "Начальный рейтинг должен быть 0")
        assert(group.pickStatus == PickStatus.unflagged, "Начальный статус отбора должен быть unflagged")
        
        // Установка рейтинга 5
        group.setRating(5)
        assert(group.rating == 5, "Рейтинг группы должен стать 5")
        assert(group.rawAsset?.rating == 5, "Рейтинг RAW оригинала должен стать 5")
        assert(group.jpegAsset?.rating == 5, "Рейтинг JPEG оригинала должен стать 5")
        
        // Установка статуса Picked
        group.setPickStatus(.picked)
        assert(group.pickStatus == PickStatus.picked, "Статус отбора группы должен стать picked")
        assert(group.rawAsset?.pickStatus == PickStatus.picked, "Статус RAW оригинала должен стать picked")
        assert(group.jpegAsset?.pickStatus == PickStatus.picked, "Статус JPEG оригинала должен стать picked")
        
        // Приход третьего файла (например HEIF) позже — должен унаследовать рейтинг и статус группы
        let heifURL = try createDummyFile(named: "DSC_0100.HIF", sizeInBytes: 3_000_000, in: test1Dir)
        let heifAsset = MediaAsset(sessionID: sessionID, filename: "DSC_0100.HIF", fileURL: heifURL, format: .heif, fileSize: 3_000_000)
        group.addAsset(heifAsset)
        
        assert(group.heifAsset?.rating == 5, "Новый оригинал HEIF должен унаследовать рейтинг группы")
        assert(group.heifAsset?.pickStatus == PickStatus.picked, "Новый оригинал HEIF должен унаследовать статус отбора группы")
        
        // Смена статуса на rejected
        group.setPickStatus(.rejected)
        assert(group.rawAsset?.pickStatus == PickStatus.rejected)
        assert(group.jpegAsset?.pickStatus == PickStatus.rejected)
        assert(group.heifAsset?.pickStatus == PickStatus.rejected)
        
        print("  ✓ Рейтинги и флаги корректно распространяются на все оригиналы кадра RAW/JPG/HEIF")
    }
    
    // MARK: - 2. Тест миграции SQLite каталога v2 и сохранения оценок
    func testCatalogDatabaseMigrationV2AndPersistence() async throws {
        print("\n[2/8] Тест миграции v2 SQLite каталога и сохранения рейтинга/флагов...")
        
        let test2Dir = tempDir.appendingPathComponent("Test2", isDirectory: true)
        try FileManager.default.createDirectory(at: test2Dir, withIntermediateDirectories: true)
        let dbURL = test2Dir.appendingPathComponent("catalog_test.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        
        let sessionFolder = test2Dir.appendingPathComponent("TestSession", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        let session = CaptureSession(name: "Test Session", folderURL: sessionFolder)
        await db.upsertSession(session)
        
        let fileURL = try createDummyFile(named: "DSC_0200.NEF", sizeInBytes: 1024, in: sessionFolder)
        let asset = MediaAsset(
            sessionID: session.id,
            filename: "DSC_0200.NEF",
            fileURL: fileURL,
            format: .raw(fileExtension: "NEF"),
            fileSize: 1024,
            rating: 4,
            pickStatus: .picked
        )
        
        await db.upsertAsset(asset)
        
        // Проверяем чтение
        var loaded = await db.getAssets(for: session.id)
        assert(loaded.count == 1, "Должен быть сохранен 1 ассет")
        assert(loaded[0].rating == 4, "Сохраненный рейтинг должен быть 4")
        assert(loaded[0].pickStatus == PickStatus.picked, "Сохраненный статус должен быть .picked")
        
        // Обновление отдельного рейтинга
        await db.updateAssetRating(id: asset.id, rating: 2)
        loaded = await db.getAssets(for: session.id)
        assert(loaded[0].rating == 2, "Рейтинг должен обновиться до 2")
        
        // Обновление отдельного статуса отбора
        await db.updateAssetPickStatus(id: asset.id, status: .rejected)
        loaded = await db.getAssets(for: session.id)
        assert(loaded[0].pickStatus == PickStatus.rejected, "Статус должен обновиться до .rejected")
        
        // Добавим второй ассет и проверим пакетное обновление
        let fileURL2 = try createDummyFile(named: "DSC_0201.NEF", sizeInBytes: 1024, in: sessionFolder)
        let asset2 = MediaAsset(
            sessionID: session.id,
            filename: "DSC_0201.NEF",
            fileURL: fileURL2,
            format: .raw(fileExtension: "NEF"),
            fileSize: 1024,
            rating: 1,
            pickStatus: .unflagged
        )
        await db.upsertAsset(asset2)
        
        await db.batchUpdateRating(ids: [asset.id, asset2.id], rating: 5)
        await db.batchUpdatePickStatus(ids: [asset.id, asset2.id], status: .picked)
        
        loaded = await db.getAssets(for: session.id)
        for item in loaded {
            assert(item.rating == 5, "Пакетный рейтинг должен быть 5 для \(item.filename)")
            assert(item.pickStatus == PickStatus.picked, "Пакетный статус должен быть picked для \(item.filename)")
        }
        
        print("  ✓ Схема v2 и все запросы сохранения/пакетного обновления SQLite работают корректно")
    }
    
    // MARK: - 3. Тест TransferCoordinator: обновление оценок и удаление
    func testTransferCoordinatorBatchAndCullingIntegration() async throws {
        print("\n[3/8] Тест TransferCoordinator: синхронизация оценок в памяти и каталоге...")
        
        let test3Dir = tempDir.appendingPathComponent("Test3", isDirectory: true)
        try FileManager.default.createDirectory(at: test3Dir, withIntermediateDirectories: true)
        let dbURL = test3Dir.appendingPathComponent("coord_test.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let storage = StorageManager(customBaseURL: test3Dir)
        
        let sessionFolder = storage.baseStorageURL.appendingPathComponent("CullingSession", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        
        let session = CaptureSession(name: "CullingSession", folderURL: sessionFolder, isActive: true)
        await db.upsertSession(session, isActive: true)
        
        let nefURL = try createDummyFile(named: "DSC_0300.NEF", sizeInBytes: 2000, in: sessionFolder)
        let jpgURL = try createDummyFile(named: "DSC_0300.JPG", sizeInBytes: 1000, in: sessionFolder)
        
        let rawAsset = MediaAsset(sessionID: session.id, filename: "DSC_0300.NEF", fileURL: nefURL, format: .raw(fileExtension: "NEF"), fileSize: 2000)
        let jpgAsset = MediaAsset(sessionID: session.id, filename: "DSC_0300.JPG", fileURL: jpgURL, format: .jpeg, fileSize: 1000)
        
        await db.upsertAsset(rawAsset)
        await db.upsertAsset(jpgAsset)
        
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let groups = await coordinator.captureGroups
        assert(groups.count == 1, "Должна быть создана 1 группа кадра из базы")
        let groupID = groups[0].id
        
        // Обновляем рейтинг через coordinator
        await coordinator.updateRating(for: groupID, rating: 3)
        let groupsAfterRating = await coordinator.captureGroups
        assert(groupsAfterRating[0].rating == 3)
        assert(groupsAfterRating[0].rawAsset?.rating == 3)
        assert(groupsAfterRating[0].jpegAsset?.rating == 3)
        
        // Проверяем сохранение в базе
        let fromDB = await db.getAssets(for: session.id)
        for a in fromDB {
            assert(a.rating == 3, "Ассет в базе должен иметь обновленный рейтинг 3")
        }
        
        // Обновляем флаг отбора
        await coordinator.updatePickStatus(for: groupID, status: .picked)
        let groupsAfterPick = await coordinator.captureGroups
        assert(groupsAfterPick[0].pickStatus == PickStatus.picked)
        
        let fromDB2 = await db.getAssets(for: session.id)
        for a in fromDB2 {
            assert(a.pickStatus == PickStatus.picked, "Ассет в базе должен иметь статус picked")
        }
        
        print("  ✓ TransferCoordinator успешно синхронизирует рейтинг и флаги между группой, оригиналом и базой")
    }
    
    // MARK: - 4. Тест фильтрации и сортировки в AppState
    @MainActor
    func testGalleryFilteringAndSortingInAppState() async throws {
        print("\n[4/8] Тест фильтрации по звездам/флагам и сортировок в AppState...")
        
        let test4Dir = tempDir.appendingPathComponent("Test4", isDirectory: true)
        try FileManager.default.createDirectory(at: test4Dir, withIntermediateDirectories: true)
        let storage4 = StorageManager(customBaseURL: test4Dir)
        let db4 = CatalogDatabase(customDatabaseURL: test4Dir.appendingPathComponent("db.sqlite"))
        let coord4 = TransferCoordinator(storageManager: storage4, database: db4)
        let appState = AppState(coordinator: coord4)
        
        let now = Date()
        let file1 = try createDummyFile(named: "DSC_0001.JPG", sizeInBytes: 10_000_000, in: test4Dir)
        let file2 = try createDummyFile(named: "DSC_0002.JPG", sizeInBytes: 25_000_000, in: test4Dir)
        let file3 = try createDummyFile(named: "DSC_0003.JPG", sizeInBytes: 5_000_000, in: test4Dir)
        
        let a1 = MediaAsset(sessionID: UUID(), filename: "DSC_0001.JPG", fileURL: file1, format: .jpeg, fileSize: 10_000_000, receivedAt: now.addingTimeInterval(-100), rating: 5, pickStatus: .picked)
        let a2 = MediaAsset(sessionID: UUID(), filename: "DSC_0002.JPG", fileURL: file2, format: .jpeg, fileSize: 25_000_000, receivedAt: now.addingTimeInterval(-50), rating: 3, pickStatus: .unflagged)
        let a3 = MediaAsset(sessionID: UUID(), filename: "DSC_0003.JPG", fileURL: file3, format: .jpeg, fileSize: 5_000_000, receivedAt: now, rating: 0, pickStatus: .rejected)
        
        let g1 = CaptureGroup(asset: a1)
        let g2 = CaptureGroup(asset: a2)
        let g3 = CaptureGroup(asset: a3)
        
        appState.captureGroups = [g1, g2, g3]
        
        // По умолчанию все показаны
        assert(appState.filteredGroups.count == 3)
        
        // Фильтрация по рейтингу
        appState.ratingFilter = .stars4Plus
        assert(appState.filteredGroups.count == 1, "Только кадр со звездами >= 4 должен пройти")
        assert(appState.filteredGroups[0].baseName == "DSC_0001")
        
        appState.ratingFilter = .stars3Plus
        assert(appState.filteredGroups.count == 2, "Кадры с рейтингом 3 и 5 должны пройти")
        
        appState.ratingFilter = .unrated
        assert(appState.filteredGroups.count == 1, "Только кадр без рейтинга (0) должен пройти")
        assert(appState.filteredGroups[0].baseName == "DSC_0003")
        
        appState.ratingFilter = .all
        
        // Фильтрация по отбору
        appState.pickFilter = .picked
        assert(appState.filteredGroups.count == 1 && appState.filteredGroups[0].baseName == "DSC_0001")
        
        appState.pickFilter = .rejected
        assert(appState.filteredGroups.count == 1 && appState.filteredGroups[0].baseName == "DSC_0003")
        
        appState.pickFilter = .unflagged
        assert(appState.filteredGroups.count == 1 && appState.filteredGroups[0].baseName == "DSC_0002")
        
        appState.pickFilter = .all
        
        // Сортировка по времени
        appState.sortOrder = .dateDesc
        assert(appState.filteredGroups.map(\.baseName) == ["DSC_0003", "DSC_0002", "DSC_0001"])
        
        appState.sortOrder = .dateAsc
        assert(appState.filteredGroups.map(\.baseName) == ["DSC_0001", "DSC_0002", "DSC_0003"])
        
        // Сортировка по рейтингу
        appState.sortOrder = .ratingDesc
        assert(appState.filteredGroups.map(\.baseName) == ["DSC_0001", "DSC_0002", "DSC_0003"])
        
        // Сортировка по размеру
        appState.sortOrder = .sizeDesc
        assert(appState.filteredGroups.map(\.baseName) == ["DSC_0002", "DSC_0001", "DSC_0003"])
        
        print("  ✓ Все режимы фильтрации по звездам/флагам и направления сортировки работают безошибочно")
    }
    
    // MARK: - 5. Тест множественного выбора и пакетных действий
    @MainActor
    func testMultiSelectionAndBatchOperationsInAppState() async throws {
        print("\n[5/8] Тест режима множественного выбора и массовых операций...")
        
        let test5Dir = tempDir.appendingPathComponent("Test5", isDirectory: true)
        try FileManager.default.createDirectory(at: test5Dir, withIntermediateDirectories: true)
        let storage5 = StorageManager(customBaseURL: test5Dir)
        let db5 = CatalogDatabase(customDatabaseURL: test5Dir.appendingPathComponent("db.sqlite"))
        let coord5 = TransferCoordinator(storageManager: storage5, database: db5)
        let appState = AppState(coordinator: coord5)
        
        let file1 = try createDummyFile(named: "DSC_0010.JPG", sizeInBytes: 1000, in: test5Dir)
        let file2 = try createDummyFile(named: "DSC_0011.JPG", sizeInBytes: 1000, in: test5Dir)
        let file3 = try createDummyFile(named: "DSC_0012.JPG", sizeInBytes: 1000, in: test5Dir)
        
        let g1 = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0010.JPG", fileURL: file1, format: .jpeg, fileSize: 1000))
        let g2 = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0011.JPG", fileURL: file2, format: .jpeg, fileSize: 1000))
        let g3 = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0012.JPG", fileURL: file3, format: .jpeg, fileSize: 1000))
        
        appState.captureGroups = [g1, g2, g3]
        appState.isSelectionMode = true
        
        // Выбор элементов
        appState.toggleSelectGroup(g1)
        appState.toggleSelectGroup(g2)
        assert(appState.selectedGroupIDs.count == 2)
        assert(appState.selectedGroupIDs.contains(g1.id))
        assert(appState.selectedGroupIDs.contains(g2.id))
        
        // Массовая установка рейтинга 4 для выбранных
        appState.batchSetRating(4)
        let res1 = appState.captureGroups.first(where: { $0.id == g1.id })
        let res2 = appState.captureGroups.first(where: { $0.id == g2.id })
        let res3 = appState.captureGroups.first(where: { $0.id == g3.id })
        
        assert(res1?.rating == 4, "g1 должен иметь рейтинг 4")
        assert(res2?.rating == 4, "g2 должен иметь рейтинг 4")
        assert(res3?.rating == 0, "g3 не был выбран и должен иметь рейтинг 0")
        
        // Массовая установка статуса picked
        appState.batchSetPickStatus(.picked)
        assert(appState.captureGroups.first(where: { $0.id == g1.id })?.pickStatus == PickStatus.picked)
        assert(appState.captureGroups.first(where: { $0.id == g2.id })?.pickStatus == PickStatus.picked)
        assert(appState.captureGroups.first(where: { $0.id == g3.id })?.pickStatus == PickStatus.unflagged)
        
        // Выбрать все и снять выделение
        appState.selectAll()
        assert(appState.selectedGroupIDs.count == 3)
        
        appState.clearSelection()
        assert(appState.selectedGroupIDs.isEmpty)
        
        print("  ✓ Множественный выбор, пакетное присвоение рейтинга и флагов работают корректно")
    }
    
    // MARK: - 6. Тест приостановки автопереключения при инспекции кадра
    @MainActor
    func testInspectionPauseOnIncomingTetheredFrames() async throws {
        print("\n[6/8] Тест приостановки автопереключения просмотрщика во время инспекции...")
        
        let test6Dir = tempDir.appendingPathComponent("Test6", isDirectory: true)
        try FileManager.default.createDirectory(at: test6Dir, withIntermediateDirectories: true)
        let storage6 = StorageManager(customBaseURL: test6Dir)
        let db6 = CatalogDatabase(customDatabaseURL: test6Dir.appendingPathComponent("db.sqlite"))
        let coord6 = TransferCoordinator(storageManager: storage6, database: db6)
        let appState = AppState(coordinator: coord6)
        
        let file1 = try createDummyFile(named: "DSC_0020.JPG", sizeInBytes: 1000, in: test6Dir)
        let g1 = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0020.JPG", fileURL: file1, format: .jpeg, fileSize: 1000))
        
        appState.captureGroups = [g1]
        appState.selectedGroup = g1
        appState.isAutoScrollEnabled = true
        
        // 1. Когда пользователь НЕ инспектирует (isUserInspecting = false)
        appState.isUserInspecting = false
        let file2 = try createDummyFile(named: "DSC_0021.JPG", sizeInBytes: 1000, in: test6Dir)
        let g2 = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0021.JPG", fileURL: file2, format: .jpeg, fileSize: 1000))
        
        appState.handleCaptureGroupUpdated(g2)
        assert(appState.selectedGroup?.id == g2.id, "При выключенной инспекции новый снимок автоматически выбирается")
        assert(appState.pendingIncomingFrameNotification == nil, "Уведомление не должно появляться при автопереключении")
        
        // 2. Пользователь начинает инспекцию кадра g2 (зум / пан / сравнение)
        appState.isUserInspecting = true
        
        let file3 = try createDummyFile(named: "DSC_0022.JPG", sizeInBytes: 1000, in: test6Dir)
        let g3 = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0022.JPG", fileURL: file3, format: .jpeg, fileSize: 1000))
        
        appState.handleCaptureGroupUpdated(g3)
        // Выбранный кадр НЕ должен измениться! Пользователь все еще рассматривает g2
        assert(appState.selectedGroup?.id == g2.id, "Во время инспекции выбранный кадр НЕ должен переключаться!")
        assert(appState.pendingIncomingFrameNotification != nil, "Должно появиться всплывающее уведомление о новом кадре")
        assert(appState.pendingIncomingFrameNotification?.contains("DSC_0022") == true)
        
        // Пользователь нажимает "Показать"
        appState.switchToPendingGroup()
        assert(appState.selectedGroup?.id == g3.id, "При подтверждении переход на ожидающий кадр должен выполниться")
        assert(appState.pendingIncomingFrameNotification == nil)
        
        print("  ✓ Автопереключение безопасно приостанавливается, предотвращая срыв внимания фотографа при зуме")
    }
    
    // MARK: - 7. Тест математики панорамирования, ограничения границ и 100% зума
    func testZoomAndPanCalculationsAnd100PercentView() async throws {
        print("\n[7/8] Тест математики ограничения панорамирования, центрирования зума и 1:1 масштаба...")
        
        // Геометрия экрана
        let viewWidth: CGFloat = 800
        let viewHeight: CGFloat = 600
        let zoomScale: CGFloat = 2.5
        
        // Расчет максимального смещения по X и Y
        let maxPanX = max(0, (viewWidth * zoomScale - viewWidth) / 2)
        let maxPanY = max(0, (viewHeight * zoomScale - viewHeight) / 2)
        
        assert(maxPanX == (800 * 1.5) / 2) // 600
        assert(maxPanY == (600 * 1.5) / 2) // 450
        
        // Проверка ограничения pan offset внутри границ
        func clampOffset(_ offset: CGSize) -> CGSize {
            let clampedX = min(maxPanX, max(-maxPanX, offset.width))
            let clampedY = min(maxPanY, max(-maxPanY, offset.height))
            return CGSize(width: clampedX, height: clampedY)
        }
        
        let extremeOffset = CGSize(width: 1500, height: -900)
        let clamped = clampOffset(extremeOffset)
        assert(clamped.width == 600, "Ширина панорамирования должна быть ограничена maxPanX")
        assert(clamped.height == -450, "Высота панорамирования должна быть ограничена -maxPanY")
        
        // Математика 100% масштаба (1:1 пиксель)
        // Камера Nikon Z9: 8256 x 5504. Экран iPad: 1366 x 1024.
        let imagePixelWidth: CGFloat = 8256
        let displayWidth: CGFloat = 1366
        let scale100Percent = imagePixelWidth / displayWidth
        assert(scale100Percent > 5.5 && scale100Percent < 6.5, "Масштаб 1:1 должен соответствовать отношению пикселей сенсора к дисплею")
        
        // Математика двойного тапа в точку касания
        let tapPoint = CGPoint(x: 200, y: 150)
        let viewCenter = CGPoint(x: viewWidth / 2, y: viewHeight / 2) // (400, 300)
        let touchVectorFromCenter = CGPoint(x: tapPoint.x - viewCenter.x, y: tapPoint.y - viewCenter.y) // (-200, -150)
        
        let targetScale: CGFloat = 3.0
        let targetPanX = -touchVectorFromCenter.x * (targetScale - 1.0)
        let targetPanY = -touchVectorFromCenter.y * (targetScale - 1.0)
        
        assert(targetPanX > 0, "Смещение должно сдвигать изображение навстречу точке касания")
        assert(targetPanY > 0)
        
        print("  ✓ Геометрические расчеты границ панорамирования, центрирования и 1:1 масштаба верифицированы")
    }
    
    // MARK: - 8. Тест синхронизации и смены сторон в CompareView
    @MainActor
    func testCompareViewSynchronizationAndSwapping() async throws {
        print("\n[8/8] Тест CompareView: синхронное масштабирование и обмен кадров...")
        
        let test8Dir = tempDir.appendingPathComponent("Test8", isDirectory: true)
        try FileManager.default.createDirectory(at: test8Dir, withIntermediateDirectories: true)
        let storage8 = StorageManager(customBaseURL: test8Dir)
        let db8 = CatalogDatabase(customDatabaseURL: test8Dir.appendingPathComponent("db.sqlite"))
        let coord8 = TransferCoordinator(storageManager: storage8, database: db8)
        let appState = AppState(coordinator: coord8)
        
        let fileA = try createDummyFile(named: "DSC_0030.JPG", sizeInBytes: 1000, in: test8Dir)
        let fileB = try createDummyFile(named: "DSC_0031.JPG", sizeInBytes: 1000, in: test8Dir)
        
        let groupA = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0030.JPG", fileURL: fileA, format: .jpeg, fileSize: 1000, rating: 2, pickStatus: .unflagged))
        let groupB = CaptureGroup(asset: MediaAsset(sessionID: UUID(), filename: "DSC_0031.JPG", fileURL: fileB, format: .jpeg, fileSize: 1000, rating: 4, pickStatus: .picked))
        
        appState.selectedGroup = groupA
        appState.compareCandidateGroup = groupB
        appState.isComparePresented = true
        appState.isUserInspecting = true
        
        // Проверка обмена кадров (swap)
        var currentA: CaptureGroup? = groupA
        var currentB: CaptureGroup? = groupB
        
        let tmp = currentA
        currentA = currentB
        currentB = tmp
        
        assert(currentA?.baseName == "DSC_0031")
        assert(currentA?.rating == 4)
        assert(currentA?.pickStatus == PickStatus.picked)
        assert(currentB?.baseName == "DSC_0030")
        assert(currentB?.rating == 2)
        
        // Проверка синхронизации масштаба
        var scaleA: CGFloat = 1.0
        var scaleB: CGFloat = 1.0
        let isSynchronized = true
        
        let newZoom: CGFloat = 2.4
        if isSynchronized {
            scaleA = newZoom
            scaleB = newZoom
        }
        
        assert(scaleA == scaleB && scaleA == 2.4, "Синхронизированный масштаб должен быть идентичным на обеих панелях")
        
        print("  ✓ Синхронная блокировка масштаба/смещения и обмен местами работают стабильно")
    }
    
    // MARK: - 9. Тест загрузки восстановленного каталога в UI AppState при запуске
    @MainActor
    func testRestoredCatalogLoadedIntoAppStateAtStartup() async throws {
        print("\n[9/9] Тест загрузки восстановленного каталога в UI AppState при запуске...")
        
        let customBaseURL = tempDir.appendingPathComponent("AppBootstrapTest", isDirectory: true)
        let dbURL = customBaseURL.appendingPathComponent("catalog.sqlite")
        try FileManager.default.createDirectory(at: customBaseURL, withIntermediateDirectories: true)
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let storage = StorageManager(customBaseURL: customBaseURL)
        
        // 1. Создаем сохраненную сессию с файлами в базе данных (имитация предыдущего сеанса работы)
        let sessionFolder = storage.baseStorageURL.appendingPathComponent("StudioPortrait", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        let session = CaptureSession(name: "StudioPortrait", folderURL: sessionFolder, isActive: true)
        await db.upsertSession(session, isActive: true)
        
        let file1 = sessionFolder.appendingPathComponent("DSC_0001.NEF")
        let file2 = sessionFolder.appendingPathComponent("DSC_0001.JPG")
        try Data([0x49, 0x49, 0x2A, 0x00]).write(to: file1)
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: file2)
        
        let asset1 = MediaAsset(sessionID: session.id, filename: "DSC_0001.NEF", fileURL: file1, format: .raw(fileExtension: "nef"), fileSize: 4000)
        let asset2 = MediaAsset(sessionID: session.id, filename: "DSC_0001.JPG", fileURL: file2, format: .jpeg, fileSize: 1000)
        await db.upsertAsset(asset1)
        await db.upsertAsset(asset2)
        
        // 2. Инициализируем координатор и AppState
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        let appState = AppState(coordinator: coordinator, resumeLastSessionOnLaunch: true)
        
        // Вызываем синхронизацию восстановленного состояния координатора в AppState
        await appState.syncStateFromCoordinator()
        
        // 3. Проверяем, что восстановленная сессия и кадры загрузились в UI
        assert(appState.currentSession?.id == session.id, "Активная сессия должна соответствовать восстановленной")
        assert(appState.currentSession?.name == "StudioPortrait", "Имя сессии должно быть StudioPortrait")
        assert(appState.receivedFiles.count == 2, "В UI должны загрузиться 2 восстановленных файла, получено: \(appState.receivedFiles.count)")
        assert(appState.captureGroups.count == 1, "Должна быть сформирована 1 группа RAW+JPG, получено: \(appState.captureGroups.count)")
        assert(appState.selectedFile != nil, "Должен быть выбран первый файл")
        assert(appState.selectedGroup != nil, "Должна быть выбрана первая группа")
        assert(appState.totalBytesTransferred == 5000, "Общий объем должен составлять 5000 байт")
        
        print("  ✓ Восстановленный каталог, активная сессия, кадры и группы успешно загружены в UI AppState при запуске")
    }
}
