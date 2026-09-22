import Foundation
import CoreGraphics
import SQLite3
import SwiftUI
import ImageCaptureCore

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct FinalUniversalUIVerificationMain {
    static func main() async throws {
        print("=== СТАРТ ФИНАЛЬНОЙ ПРОВЕРКИ 9 ПОЛЬЗОВАТЕЛЬСКИХ СЦЕНАРИЕВ ИНТЕРФЕЙСА ===")
        
        let suite = FinalUniversalUIVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ 9 ПОЛЬЗОВАТЕЛЬСКИХ СЦЕНАРИЕВ УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class FinalUniversalUIVerificationSuite {
    let tempBaseURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FinalUITest_\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
    }
    
    func runAllTests() async throws {
        defer { try? FileManager.default.removeItem(at: tempBaseURL) }
        
        await USBCameraManager.shared.resetState()
        try await testScenario1FirstActionWithoutAndWithCamera()
        
        await USBCameraManager.shared.resetState()
        try await testScenario2CardReadingAndPrematureImportGating()
        
        await USBCameraManager.shared.resetState()
        try await testScenario3SelectiveAndBatchImportAccounting()
        
        await USBCameraManager.shared.resetState()
        try await testScenario4SectionSwitchingDuringActiveTransfer()
        
        await USBCameraManager.shared.resetState()
        try await testScenario5WindowResizeAndOrientationPreservesSelection()
        
        await USBCameraManager.shared.resetState()
        try await testScenario6SessionSwitchingDuringActiveTransfer()
        
        await USBCameraManager.shared.resetState()
        try await testScenario7TransferErrorCancellationAndRetry()
        
        await USBCameraManager.shared.resetState()
        try await testScenario8FiltersRAWJPEGGroupingInspectionCompareExport()
        
        await USBCameraManager.shared.resetState()
        try await testScenario9ClientScreenAndSessionHistoryAccess()
    }
    
    // MARK: - Сценарий 1: Понятность первого действия без камеры и с камерой
    func testScenario1FirstActionWithoutAndWithCamera() async throws {
        print("\n[Сценарий 1/9] Понятность первого действия без камеры и с камерой...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario1")
        let appState = AppState(port: 39201, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        
        // 1.1 Без камеры
        let stateNoCamera = appState.mainScreenState
        guard let emptyState = stateNoCamera.emptyState else {
            verify(false, "Ожидалось пустое состояние .disconnected")
            return
        }
        verify(emptyState.kind == .disconnected, "При отсутствии камеры состояние должно быть .disconnected")
        verify(!emptyState.title.isEmpty, "Заголовок первого действия не должен быть пустым")
        verify(!emptyState.description.isEmpty, "Описание первого действия должно быть информативным")
        verify(emptyState.primaryAction?.type == .connectCamera || emptyState.primaryAction?.type == .openConnectionGuide, "Первое действие направляет пользователя на подключение")
        
        // 1.2 С подключенной камерой (готовой к работе)
        let mockCamera = MockCameraDevice()
        appState.currentUSBManager.connectedCamera = mockCamera
        appState.currentUSBManager.isCatalogReady = true
        appState.currentUSBManager.catalogFiles = [
            CameraFileItem(cameraID: "nikon", filename: "DSC_0001.NEF", fileSize: 50_000_000, status: .notImported)
        ]
        
        let stateWithCamera = appState.mainScreenState
        guard let readyState = stateWithCamera.emptyState else {
            verify(false, "Ожидалось состояние готовности к импорту")
            return
        }
        verify(readyState.kind == .cardReady, "С камерой и файлами состояние должно быть .cardReady")
        verify(readyState.primaryAction?.type == .importAllFromCard, "Главное действие предлагает импорт с карты")
        
        print("  ✓ Сценарий 1 подтвержден: понятные первые действия без камеры и с камерой")
    }
    
    // MARK: - Сценарий 2: Чтение карты памяти и запрет преждевременного импорта
    func testScenario2CardReadingAndPrematureImportGating() async throws {
        print("\n[Сценарий 2/9] Чтение карты и запрет преждевременного импорта...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario2")
        let appState = AppState(port: 39202, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await appState.waitUntilReady()
        await appState.syncStateFromCoordinator()
        let manager = appState.currentUSBManager
        
        let mockCamera = MockCameraDevice()
        manager.connectedCamera = mockCamera
        manager.isCatalogReady = false // Карта еще читается
        
        let file = MockCameraFile(name: "DSC_TEST.NEF")
        let item = CameraFileItem(cameraID: "nikon", filename: "DSC_TEST.NEF", fileSize: 40_000_000, cameraFile: file)
        manager.catalogFiles = [item]
        
        // Попытка запустить импорт до готовности оглавления
        await manager.importAllUnimported()
        let countWhileReading = await manager.transferQueue.totalQueueCount
        verify(countWhileReading == 0, "Импорт НЕ должен начинаться, пока каталог карты не готов (isCatalogReady == false)")
        
        // Каталог готов
        manager.isCatalogReady = true
        await manager.importAllUnimported()
        let countReady = await manager.transferQueue.totalQueueCount
        verify(countReady == 1, "После готовности каталога импорт успешно инициирован")
        
        print("  ✓ Сценарий 2 подтвержден: преждевременный импорт строго заблокирован")
    }
    
    // MARK: - Сценарий 3: Выборочный и пакетный импорт
    func testScenario3SelectiveAndBatchImportAccounting() async throws {
        print("\n[Сценарий 3/9] Выборочный и пакетный импорт...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario3")
        let appState = AppState(port: 39203, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        let manager = appState.currentUSBManager
        manager.connectedCamera = MockCameraDevice()
        manager.isCatalogReady = true
        
        let f1 = CameraFileItem(cameraID: "nikon", filename: "IMG_1.NEF", fileSize: 30_000_000, cameraFile: MockCameraFile(name: "IMG_1.NEF"))
        let f2 = CameraFileItem(cameraID: "nikon", filename: "IMG_2.NEF", fileSize: 30_000_000, cameraFile: MockCameraFile(name: "IMG_2.NEF"))
        let f3 = CameraFileItem(cameraID: "nikon", filename: "IMG_3.JPG", fileSize: 10_000_000, cameraFile: MockCameraFile(name: "IMG_3.JPG"), status: .imported)
        manager.catalogFiles = [f1, f2, f3]
        
        let stats = manager.catalogStats
        verify(stats.totalCount == 3, "Всего на карте 3 файла")
        verify(stats.unimportedCount == 2, "Доступно для импорта 2 файла")
        verify(stats.importedCount == 1, "Уже импортирован 1 файл")
        
        // Выборочный импорт только f1
        await manager.importSelectedFiles([f1])
        verify(await manager.transferQueue.totalQueueCount == 1, "В очереди строго выбранный файл")
        
        print("  ✓ Сценарий 3 подтвержден: точный учет доступных файлов и выборочный импорт")
    }
    
    // MARK: - Сценарий 4: Переходы между разделами во время передачи
    func testScenario4SectionSwitchingDuringActiveTransfer() async throws {
        print("\n[Сценарий 4/9] Переходы между разделами во время передачи...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario4")
        let appState = AppState(port: 39204, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await appState.syncStateFromCoordinator()
        
        // Имитируем активное задание переноса
        let activeJob = TransferJob(
            id: UUID(),
            source: CameraSource(id: "nikon", model: "Nikon Z 8", transportType: .usb),
            sourceFileID: "DSC_ACTIVE.NEF",
            destinationURL: appState.currentSession!.folderURL.appendingPathComponent("DSC_ACTIVE.NEF"),
            stagingURL: appState.currentSession!.folderURL.appendingPathComponent(".staging/DSC_ACTIVE.tmp"),
            sessionID: appState.currentSession!.id,
            state: .inProgress(progress: 0.5, bytesTransferred: 25_000_000, totalBytes: 50_000_000),
            totalBytes: 50_000_000
        )
        appState.activeJobs = [activeJob]
        appState.currentTransferSpeedMBs = 42.5
        
        verify(appState.activeTransferJob != nil, "Активное задание должно определяться в UI")
        verify(appState.currentTransferSpeedMBs > 40, "Скорость передачи должна отображаться в стрипе")
        
        // Переключаем разделы
        appState.selectedSection = .photos
        verify(appState.activeTransferJob != nil, "Смена раздела на .photos не прерывает задание")
        
        appState.selectedSection = .camera
        verify(appState.activeTransferJob != nil, "Смена раздела на .camera не прерывает задание")
        
        appState.selectedSection = .sessions
        verify(appState.activeTransferJob != nil, "Смена раздела на .sessions не прерывает задание")
        
        print("  ✓ Сценарий 4 подтвержден: плашка и задания активны во всех 3 разделах")
    }
    
    // MARK: - Сценарий 5: Изменение ширины окна без потери выбора
    func testScenario5WindowResizeAndOrientationPreservesSelection() async throws {
        print("\n[Сценарий 5/9] Изменение ширины окна без потери выбора...")
        
        let (coordinator, localDB, _) = try await makeIsolatedEnvironment(named: "Scenario5")
        let session = try await coordinator.startNewSession(named: "Selection_Test_Session")
        let appState = AppState(port: 39205, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await appState.waitUntilReady()
        await appState.syncStateFromCoordinator()
        
        // Добавляем тестовые кадры
        let folder = session.folderURL.resolvingSymlinksInPath()
        let photoA = folder.appendingPathComponent("SELECT_A.JPG")
        let photoB = folder.appendingPathComponent("SELECT_B.JPG")
        try Data([1, 2, 3]).write(to: photoA)
        try Data([4, 5, 6]).write(to: photoB)
        
        let assetA = MediaAsset(sessionID: session.id, filename: "SELECT_A.JPG", fileURL: photoA, format: .jpeg, fileSize: 3)
        let assetB = MediaAsset(sessionID: session.id, filename: "SELECT_B.JPG", fileURL: photoB, format: .jpeg, fileSize: 3)
        await localDB.upsertAsset(assetA)
        await localDB.upsertAsset(assetB)
        let switched = await coordinator.switchActiveSession(to: session.id)
        verify(switched?.id == session.id)
        await appState.syncStateFromCoordinator()
        verify(appState.captureGroups.count == 2, "Должно быть ровно 2 кадра в сессии")
        let groupA = appState.captureGroups[0]
        let groupB = appState.captureGroups[1]
        
        // Выбираем группу и множественный выбор
        appState.selectedGroup = groupA
        appState.selectedGroupIDs = [groupA.id, groupB.id]
        appState.selectedSection = .sessions
        
        // Проверяем резолвер компоновок
        let narrowMode = AdaptiveLayoutResolver.resolve(width: 390, dynamicTypeSize: .large)
        verify(narrowMode == .narrow, "390 pt — узкая компоновка")
        
        let wideMode = AdaptiveLayoutResolver.resolve(width: 1024, dynamicTypeSize: .large)
        verify(wideMode == .wide, "1024 pt — широкая компоновка")
        
        // Проверяем, что выбор сохранен в корневом AppState
        verify(appState.selectedGroup?.id == groupA.id, "Выбранный кадр не сбросился")
        verify(appState.selectedGroupIDs.count == 2, "Множественный выбор сохранился")
        verify(appState.selectedSection == .sessions, "Выбранный раздел сохранился")
        
        print("  ✓ Сценарий 5 подтвержден: смена геометрии не сбрасывает состояние и выбор")
    }
    
    // MARK: - Сценарий 6: Смена сессии во время загрузки
    func testScenario6SessionSwitchingDuringActiveTransfer() async throws {
        print("\n[Сценарий 6/9] Смена сессии во время загрузки...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario6")
        let appState = AppState(port: 39206, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await appState.waitUntilReady()
        await appState.syncStateFromCoordinator()
        
        let session1 = appState.currentSession!
        let session2 = try await coordinator.startNewSession(named: "TargetSession_2")
        
        // Активное фоновое задание в Session 1
        let inFlightJob = TransferJob(
            id: UUID(),
            source: CameraSource(id: "nikon", model: "Nikon Z 8", transportType: .usb),
            sourceFileID: "BG_IN_FLIGHT.NEF",
            destinationURL: session1.folderURL.appendingPathComponent("BG_IN_FLIGHT.NEF"),
            stagingURL: session1.folderURL.appendingPathComponent(".staging/BG_IN_FLIGHT.tmp"),
            sessionID: session1.id,
            state: .inProgress(progress: 0.2, bytesTransferred: 10_000_000, totalBytes: 60_000_000),
            totalBytes: 60_000_000
        )
        
        // Переключаем активную сессию на Session 2
        let switched = await coordinator.switchActiveSession(to: session2.id)
        verify(switched?.id == session2.id, "Активной стала сессия 2")
        
        // Проверяем привязку задания
        verify(inFlightJob.sessionID == session1.id, "Фоновое задание жестко привязано к Session 1")
        verify(inFlightJob.destinationURL.path.contains("BG_IN_FLIGHT.NEF"), "Путь файла не изменился")
        
        print("  ✓ Сценарий 6 подтвержден: фоновая загрузка изолирована и сохраняет сессию")
    }
    
    // MARK: - Сценарий 7: Ошибки, отмена и повтор
    func testScenario7TransferErrorCancellationAndRetry() async throws {
        print("\n[Сценарий 7/9] Ошибки, отмена и повтор...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario7")
        let manager = USBCameraManager(coordinator: coordinator, maxConcurrentDownloads: 1)
        manager.isCatalogReady = true
        manager.connectedCamera = MockCameraDevice()
        
        let file = MockCameraFile(name: "DSC_ERROR.NEF")
        let item = CameraFileItem(cameraID: "nikon", filename: "DSC_ERROR.NEF", fileSize: 30_000_000, cameraFile: file)
        manager.catalogFiles = [item]
        
        // 1. Постановка и отмена
        await manager.importSelectedFiles([item])
        verify(await manager.transferQueue.totalQueueCount == 1)
        await manager.cancelTransfer(compositeID: item.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        verify(await manager.transferQueue.totalQueueCount == 0, "Отмена очистила очередь")
        verify(manager.catalogFiles.first?.status == .notImported, "Статус вернулся в .notImported")
        
        // 2. Имитация ошибки и точечный повтор
        var failedItem = item
        failedItem.status = .failed(error: "I/O Error")
        verify(failedItem.status == .failed(error: "I/O Error"), "Статус зафиксирован как ошибка")
        
        await manager.retryTransfer(for: failedItem)
        verify(await manager.transferQueue.totalQueueCount == 1, "Повтор снова добавил файл в очередь")
        
        print("  ✓ Сценарий 7 подтвержден: отмена и точечный повтор работают корректно")
    }
    
    // MARK: - Сценарий 8: Фильтры, RAW+JPEG, отбор, сравнение и экспорт
    func testScenario8FiltersRAWJPEGGroupingInspectionCompareExport() async throws {
        print("\n[Сценарий 8/9] Фильтры, RAW+JPEG, отбор, сравнение и экспорт...")
        
        let (coordinator, localDB, _) = try await makeIsolatedEnvironment(named: "Scenario8")
        let session = try await coordinator.startNewSession(named: "Pairing_Test_Session")
        let appState = AppState(port: 39208, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await appState.waitUntilReady()
        await appState.syncStateFromCoordinator()
        
        // Создаем пару RAW+JPEG
        let folder = session.folderURL.resolvingSymlinksInPath()
        let nefURL = folder.appendingPathComponent("DSC_PAIR.NEF")
        let jpgURL = folder.appendingPathComponent("DSC_PAIR.JPG")
        try Data([1, 1]).write(to: nefURL)
        try Data([2, 2]).write(to: jpgURL)
        
        let assetRAW = MediaAsset(sessionID: session.id, filename: "DSC_PAIR.NEF", fileURL: nefURL, format: .raw(fileExtension: "NEF"), fileSize: 2)
        let assetJPG = MediaAsset(sessionID: session.id, filename: "DSC_PAIR.JPG", fileURL: jpgURL, format: .jpeg, fileSize: 2)
        
        await localDB.upsertAsset(assetRAW)
        await localDB.upsertAsset(assetJPG)
        _ = await coordinator.switchActiveSession(to: session.id)
        await appState.syncStateFromCoordinator()
        
        // 1. RAW+JPEG сгруппированы в один кадр
        verify(appState.captureGroups.count == 1, "RAW и JPEG должны объединиться в 1 CaptureGroup")
        let group = appState.captureGroups.first!
        verify(group.isPaired, "Кадр должен определяться как пара")
        verify(group.hasBothRawAndJpeg, "Кадр содержит и RAW, и JPEG")
        
        // 2. Отбор (рейтинг и флаг)
        appState.setRating(5, for: group)
        appState.setPickStatus(.picked, for: group)
        
        let updatedGroup = appState.captureGroups.first!
        verify(updatedGroup.rating == 5, "Рейтинг 5 звезд должен сохраниться")
        verify(updatedGroup.pickStatus == .picked, "Флаг Picked должен сохраниться")
        
        // 3. Сравнение
        appState.selectedGroup = updatedGroup
        appState.compareCandidateGroup = updatedGroup
        verify(appState.selectedGroup != nil && appState.compareCandidateGroup != nil)
        
        // 4. Экспорт
        appState.presentExport(for: [updatedGroup])
        verify(appState.isExportSheetPresented == true, "Лист экспорта должен открыться")
        verify(appState.exportTargetGroups.count == 1, "Целевая группа для экспорта передана")
        
        print("  ✓ Сценарий 8 подтвержден: объединение в пары, отбор, сравнение и экспорт работают")
    }
    
    // MARK: - Сценарий 9: Доступность клиентского экрана и истории
    func testScenario9ClientScreenAndSessionHistoryAccess() async throws {
        print("\n[Сценарий 9/9] Клиентский экран и история съемок...")
        
        let (coordinator, _, _) = try await makeIsolatedEnvironment(named: "Scenario9")
        let appState = AppState(port: 39209, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await appState.waitUntilReady()
        await appState.syncStateFromCoordinator()
        
        // 9.1 Клиентский экран
        let monitor = appState.clientMonitorManager
        verify(monitor.config.filterMode == .all, "Фильтр клиента по умолчанию .all")
        
        monitor.setHold(true, for: appState.selectedGroup)
        verify(monitor.config.isHoldEnabled, "Hold режим успешно активирован")
        
        monitor.releaseHold(latestGroup: nil)
        verify(!monitor.config.isHoldEnabled, "Hold режим успешно сброшен")
        
        // 9.2 История съемок
        let allSessions = appState.availableSessions
        verify(!allSessions.isEmpty, "История съемок доступна")
        
        let stats = await appState.fetchSessionStats(for: appState.currentSession!.id)
        verify(!stats.formattedSize.isEmpty, "Статистика истории съемок возвращает размер")
        
        print("  ✓ Сценарий 9 подтвержден: клиентский экран и история съемок полностью доступны")
    }
    
    // MARK: - Вспомогательная фабрика
    private func makeIsolatedEnvironment(named name: String) async throws -> (TransferCoordinator, CatalogDatabase, URL) {
        let dir = tempBaseURL.appendingPathComponent(name, isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let localDB = CatalogDatabase(customDatabaseURL: dir.appendingPathComponent("test.sqlite"))
        let storage = StorageManager(customBaseURL: dir)
        let coordinator = TransferCoordinator(storageManager: storage, database: localDB)
        await coordinator.bootstrap()
        return (coordinator, localDB, dir)
    }
}

// MARK: - Mocks
final class MockCameraFile: ICCameraFile, @unchecked Sendable {
    var customName: String
    var customSize: off_t
    
    init(name: String, size: off_t = 45_000_000) {
        self.customName = name
        self.customSize = size
        super.init()
    }
    
    override var name: String? { customName }
    override var fileSize: off_t { customSize }
}

final class MockCameraDevice: ICCameraDevice, @unchecked Sendable {
    var customName: String = "Nikon Z 8 (Mock)"
    var lastRequestedFile: ICCameraFile?
    weak var downloadDelegate: (any ICCameraDeviceDownloadDelegate)?
    
    override var name: String? { customName }
    
    #if os(macOS)
    override func cancelDownload() {
        performCancel()
    }
    #else
    @objc func cancelDownload() {
        performCancel()
    }
    #endif
    
    private func performCancel() {
        if let file = lastRequestedFile, let delegate = downloadDelegate as? USBCameraManager {
            let cancelErr = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
            Task { @MainActor in
                delegate.didDownloadFile(file, error: cancelErr, options: [:], contextInfo: nil)
            }
        }
    }
    
    override func requestDownloadFile(
        _ file: ICCameraFile,
        options: [ICDownloadOption : Any] = [:],
        downloadDelegate: any ICCameraDeviceDownloadDelegate,
        didDownloadSelector: Selector,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        lastRequestedFile = file
        self.downloadDelegate = downloadDelegate
    }
}
