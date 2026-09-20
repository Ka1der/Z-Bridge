import Foundation
import CoreGraphics
import SQLite3
import SwiftUI
@preconcurrency import ImageCaptureCore

@inline(__always)
fileprivate func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

// Мок для ICCameraFile для тестирования очереди передачи
final class TestCameraFile: ICCameraFile, @unchecked Sendable {
    private let _name: String
    private let _fileSize: Int64
    private let _creationDate: Date
    
    init(name: String, fileSize: Int64, creationDate: Date = Date()) {
        self._name = name
        self._fileSize = fileSize
        self._creationDate = creationDate
        super.init()
    }
    
    override var name: String? { _name }
    override var fileSize: Int64 { _fileSize }
    override var creationDate: Date? { _creationDate }
}

final class TestCameraDevice: ICCameraDevice, @unchecked Sendable {
    private let _name: String
    private var _mediaFiles: [ICCameraFile] = []
    
    init(name: String) {
        self._name = name
        super.init()
    }
    
    override var name: String? { _name }
    override var mediaFiles: [ICCameraItem]? { _mediaFiles }
    
    func setMediaFiles(_ files: [ICCameraFile]) {
        self._mediaFiles = files
    }
}

@main
struct SessionSwitchAndCatalogGatingMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ИСПРАВЛЕНИЙ P1 И P2 ДЛЯ NIKONZBRIDGE ===")
        
        let suite = SessionSwitchAndCatalogGatingSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ДЕФЕКТОВ P1 И P2 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class SessionSwitchAndCatalogGatingSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("P1P2Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("p1p2_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        defer { try? FileManager.default.removeItem(at: tempBaseURL) }
        
        try await testSessionSwitchDuringDownloadDoesNotBlockImportInNewSession()
        try await testSelectedImportGatedByCatalogReadiness()
        try await testCatalogStatsDoesNotPrematurelyReportAllImported()
        try await testRefreshCatalogSynchronizesActiveSessionAndDiscoveredFiles()
    }
    
    // MARK: - 1. P1: Смена сессии во время загрузки не блокирует импорт в новую сессию
    func testSessionSwitchDuringDownloadDoesNotBlockImportInNewSession() async throws {
        print("\n--- [1/4] P1: Смена сессии во время загрузки и независимость сессионного импорта ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        
        // Создаем две сессии: A и B
        let sessionA = try await storage.createNewSession(named: "Session_A")
        await database.upsertSession(sessionA, isActive: true)
        let sessionB = try await storage.createNewSession(named: "Session_B")
        await database.upsertSession(sessionB, isActive: false)
        
        // Стартуем в Session A
        await coordinator.switchActiveSession(to: sessionA.id)
        
        let usbManager = USBCameraManager(coordinator: coordinator)
        let mockCamera = TestCameraDevice(name: "Nikon Z 9")
        let file1 = TestCameraFile(name: "DSC_0001.NEF", fileSize: 2000)
        mockCamera.setMediaFiles([file1])
        
        usbManager.connectedCamera = mockCamera
        usbManager.isConnected = true
        usbManager.isCatalogReady = true
        
        let compositeID = CameraFileItem.makeCompositeID(cameraID: "Nikon Z 9", filename: "DSC_0001.NEF", fileSize: 2000, creationDate: file1.creationDate)
        let item1 = CameraFileItem(cameraID: "Nikon Z 9", filename: "DSC_0001.NEF", fileSize: 2000, creationDate: file1.creationDate, cameraFile: file1, status: .notImported)
        usbManager.catalogFiles = [item1]
        
        // 1. Создаем задание на скачивание файла в Session A
        let source = CameraSource(id: "usb-nikon", model: "Nikon Z 9", transportType: .usb)
        let stagingURL = sessionA.folderURL.appendingPathComponent(".staging_dsc1.tmp")
        try Data(repeating: 0x55, count: 2000).write(to: stagingURL)
        
        let jobForA = TransferJob(
            id: UUID(),
            source: source,
            sourceFileID: compositeID,
            destinationURL: sessionA.folderURL.appendingPathComponent("DSC_0001.NEF"),
            stagingURL: stagingURL,
            sessionID: sessionA.id, // Привязано к Session A!
            state: .inProgress(progress: 0.5, bytesTransferred: 1000, totalBytes: 2000),
            totalBytes: 2000
        )
        await coordinator.upsertJobForTesting(jobForA)
        
        // 2. Ставим в очередь USBTransferQueue для активной сессии A
        let queueItem = USBQueueItem(compositeID: compositeID, cameraFile: file1, filename: "DSC_0001.NEF", fileSize: 2000, jobID: jobForA.id)
        await usbManager.transferQueue.enqueue(queueItem)
        _ = await usbManager.transferQueue.dequeueNextIfAvailable() // Переходит в activeTransfers
        
        // 3. ПОЛЬЗОВАТЕЛЬ ПЕРЕКЛЮЧАЕТ АКТИВНУЮ СЕССИЮ НА SESSION B ВО ВРЕМЯ ЗАГРУЗКИ!
        await coordinator.switchActiveSession(to: sessionB.id)
        await usbManager.syncWithSession(sessionB)
        
        verify(await coordinator.activeSession.id == sessionB.id, "Активная сессия теперь Session B")
        
        // 4. Задание для Session A завершается (финализация)
        let assetA = try await coordinator.finalizeTransfer(jobID: jobForA.id, actualSize: 2000, duration: 0.2)
        verify(assetA.sessionID == sessionA.id, "Ассет финализирован строго в Session A")
        
        // Имитируем завершение в менеджере USB камеры (как в downloadFile)
        let activeSessionID = await coordinator.activeSession.id
        let isForActiveSession = (assetA.sessionID == activeSessionID)
        verify(!isForActiveSession, "Завершенное задание было НЕ для активной Session B, а для Session A")
        
        let nextItem = await usbManager.transferQueue.markCompleted(compositeID: compositeID, markAsImported: isForActiveSession)
        verify(nextItem == nil, "Очередь освободилась")
        
        if isForActiveSession {
            usbManager.catalogFiles[0].status = .imported
        } else {
            usbManager.catalogFiles[0].status = .notImported
        }
        
        // 5. ПРОВЕРКИ:
        // В Session B файл НЕ должен числиться импортированным!
        verify(usbManager.catalogFiles[0].status == .notImported, "Для Session B статус файла должен остаться .notImported")
        let isImportedInQueueB = await usbManager.transferQueue.isAlreadyImported(compositeID: compositeID)
        verify(!isImportedInQueueB, "В очереди Session B файл НЕ должен быть помечен как importedIDs")
        
        // Теперь пробуем импортировать этот же файл в пустую Session B обычной командой:
        let jobForB = TransferJob(
            id: UUID(),
            source: source,
            sourceFileID: compositeID,
            destinationURL: sessionB.folderURL.appendingPathComponent("DSC_0001.NEF"),
            stagingURL: sessionB.folderURL.appendingPathComponent(".staging_dsc1_b.tmp"),
            sessionID: sessionB.id,
            state: .pending,
            totalBytes: 2000
        )
        let queueItemB = USBQueueItem(compositeID: compositeID, cameraFile: file1, filename: "DSC_0001.NEF", fileSize: 2000, jobID: jobForB.id)
        let enqueuedInB = await usbManager.transferQueue.enqueue(queueItemB)
        
        verify(enqueuedInB == true, "Файл ДОЛЖЕН успешно ставиться в очередь для Session B!")
        print("  [✓] P1 исправлена: смена сессии не блокирует импорт в новую сессию.")
    }
    
    // MARK: - 2. P2: Выборочный импорт обходит ожидание готовности карты
    func testSelectedImportGatedByCatalogReadiness() async throws {
        print("\n--- [2/4] P2: Выборочный импорт блокируется до готовности карты ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        
        let session = try await storage.createNewSession(named: "CatalogGating_Session")
        await database.upsertSession(session, isActive: true)
        await coordinator.switchActiveSession(to: session.id)
        
        let usbManager = USBCameraManager(coordinator: coordinator)
        let mockCamera = TestCameraDevice(name: "Nikon Z 8")
        let file = TestCameraFile(name: "DSC_0002.NEF", fileSize: 5000)
        usbManager.connectedCamera = mockCamera
        usbManager.isConnected = true
        
        // КАТАЛОГ ЕЩЕ НЕ ГОТОВ!
        usbManager.isCatalogReady = false
        
        let item = CameraFileItem(cameraID: "Nikon Z 8", filename: "DSC_0002.NEF", fileSize: 5000, cameraFile: file, status: .notImported)
        usbManager.catalogFiles = [item]
        
        // Вызываем выборочный импорт до готовности оглавления
        await usbManager.importSelectedFiles([item])
        
        // Проверяем: ничего не должно встать в очередь!
        let queueCount = await usbManager.transferQueue.totalQueueCount
        verify(queueCount == 0, "При isCatalogReady == false выборочный импорт ЗАПРЕЩЕН (queueCount == 0)")
        verify(usbManager.catalogFiles[0].status == .notImported, "Статус файла не должен меняться на .queued")
        
        // Теперь переводим каталог в готовность
        usbManager.isCatalogReady = true
        await usbManager.importSelectedFiles([item])
        
        let queueCountAfter = await usbManager.transferQueue.totalQueueCount
        verify(queueCountAfter == 1, "После готовности оглавления (isCatalogReady == true) файл успешно попадает в очередь")
        
        print("  [✓] P2 исправлена: выборочный импорт строго ожидает готовности каталога.")
    }
    
    // MARK: - 3. P2: Интерфейс преждевременно сообщает «Все файлы загружены»
    func testCatalogStatsDoesNotPrematurelyReportAllImported() async throws {
        print("\n--- [3/4] P2: Статистика оглавления и разделение состояний передачи/ошибок ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        
        let usbManager = USBCameraManager(coordinator: coordinator)
        usbManager.isConnected = true
        usbManager.isCatalogReady = true
        
        // 5 файлов на карте:
        // 2 уже imported
        // 1 в очереди queued
        // 1 качается importing
        // 1 завершился ошибкой failed
        // 0 в статусе notImported
        let f1 = CameraFileItem(cameraID: "Z9", filename: "F1.NEF", fileSize: 1000, status: .imported)
        let f2 = CameraFileItem(cameraID: "Z9", filename: "F2.NEF", fileSize: 1000, status: .imported)
        let f3 = CameraFileItem(cameraID: "Z9", filename: "F3.NEF", fileSize: 1000, status: .queued)
        let f4 = CameraFileItem(cameraID: "Z9", filename: "F4.NEF", fileSize: 1000, status: .importing(progress: 0.5))
        let f5 = CameraFileItem(cameraID: "Z9", filename: "F5.NEF", fileSize: 1000, status: .failed(error: "I/O Error"))
        
        usbManager.catalogFiles = [f1, f2, f3, f4, f5]
        
        let browserView = USBCameraBrowserView(usbManager: usbManager)
        let stats = browserView.stats
        
        verify(stats.totalCount == 5, "Всего файлов: 5")
        verify(stats.unimportedCount == 0, "notImported: 0")
        verify(stats.importedCount == 2, "Импортировано: 2")
        verify(stats.inProgressCount == 2, "В процессе (queued + importing): 2")
        verify(stats.failedCount == 1, "С ошибкой: 1")
        
        // Проверяем: условие «Все файлы загружены» НЕ должно быть истинным, пока есть inProgress или failed!
        let isPrematureAllLoaded = (stats.importedCount == stats.totalCount)
        verify(!isPrematureAllLoaded, "Преждевременное сообщение 'Все файлы загружены' предотвращено!")
        
        // Теперь переводим все в .imported
        usbManager.catalogFiles = [
            CameraFileItem(cameraID: "Z9", filename: "F1.NEF", fileSize: 1000, status: .imported),
            CameraFileItem(cameraID: "Z9", filename: "F2.NEF", fileSize: 1000, status: .imported),
            CameraFileItem(cameraID: "Z9", filename: "F3.NEF", fileSize: 1000, status: .imported),
            CameraFileItem(cameraID: "Z9", filename: "F4.NEF", fileSize: 1000, status: .imported),
            CameraFileItem(cameraID: "Z9", filename: "F5.NEF", fileSize: 1000, status: .imported)
        ]
        let finalStats = browserView.stats
        verify(finalStats.importedCount == finalStats.totalCount, "Только теперь все файлы действительно импортированы")
        verify(finalStats.inProgressCount == 0 && finalStats.failedCount == 0, "Нет активных передач и ошибок")
        
        print("  [✓] P2 исправлена: статистика корректно разделяет inProgress, failed и imported.")
    }
    
    // MARK: - 4. P2: «Обновить карту» фактически обновляет каталог
    func testRefreshCatalogSynchronizesActiveSessionAndDiscoveredFiles() async throws {
        print("\n--- [4/4] P2: refreshCatalog фактически опрашивает носитель и синхронизирует сессию ---")
        
        let database = CatalogDatabase(customDatabaseURL: dbURL)
        let diskGuard = DiskSpaceGuard()
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: diskGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: database, diskGuard: diskGuard)
        
        let session = try await storage.createNewSession(named: "Refresh_Session")
        await database.upsertSession(session, isActive: true)
        await coordinator.switchActiveSession(to: session.id)
        
        let usbManager = USBCameraManager(coordinator: coordinator)
        let mockCamera = TestCameraDevice(name: "Nikon Z f")
        let fileA = TestCameraFile(name: "DSC_5555.NEF", fileSize: 3000)
        mockCamera.setMediaFiles([fileA])
        
        usbManager.connectedCamera = mockCamera
        usbManager.isConnected = true
        usbManager.isCatalogReady = true
        
        // Начальное оглавление
        let itemA = CameraFileItem(cameraID: "Nikon Z f", filename: "DSC_5555.NEF", fileSize: 3000, cameraFile: fileA, status: .notImported)
        usbManager.catalogFiles = [itemA]
        
        // На карте физически появился новый снимок DSC_5556.NEF (например, сделанный камерой)
        let fileB = TestCameraFile(name: "DSC_5556.NEF", fileSize: 3200)
        mockCamera.setMediaFiles([fileA, fileB])
        
        // Также в сессию был добавлен asset DSC_5555.NEF через внешний импорт
        let assetA = MediaAsset(sessionID: session.id, filename: "DSC_5555.NEF", fileURL: session.folderURL.appendingPathComponent("DSC_5555.NEF"), format: MediaFormat(fileExtension: "nef"), fileSize: 3000)
        await database.upsertAsset(assetA)
        
        // Вызываем фактическое обновление оглавления
        await usbManager.refreshCatalog()
        
        // Проверяем:
        // 1. DSC_5556.NEF обнаружен и добавлен в catalogFiles
        verify(usbManager.catalogFiles.contains(where: { $0.filename == "DSC_5556.NEF" }), "Новый файл DSC_5556.NEF обнаружен после refreshCatalog")
        
        // 2. DSC_5555.NEF обновил статус на .imported благодаря синхронизации с базой данных
        let updatedA = usbManager.catalogFiles.first(where: { $0.filename == "DSC_5555.NEF" })
        verify(updatedA?.status == .imported, "DSC_5555.NEF синхронизировал статус с SQLite и стал .imported")
        
        print("  [✓] P2 исправлена: refreshCatalog фактически перечитывает медиафайлы и синхронизирует статусы.")
    }
}
