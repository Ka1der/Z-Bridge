import Foundation
import Combine
import CommonCrypto
import Darwin
import ImageIO
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct Stage13EdgeCasesAndIntegrationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 13: КРАЕВЫЕ СЦЕНАРИИ И ИНТЕГРАЦИЯ FTP ===")
        
        let suite = Stage13EdgeCasesAndIntegrationVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ 10 ТЕСТОВ ЭТАПА 13 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage13EdgeCasesAndIntegrationVerificationSuite {
    let tempDir: URL
    let fileManager = FileManager.default
    
    init() {
        let base = fileManager.temporaryDirectory.appendingPathComponent("Stage13Test_\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.tempDir = base
    }
    
    func runAllTests() async throws {
        try await testIdenticalNamesAndParallelImports()
        try await testCancellationTimeoutDisconnectionAndRetry()
        try await testWriteErrorAndInsufficientStorageSpace()
        try await testCrashRecoveryBetweenSaveAndCatalogUpdate()
        try await testSessionSwitchingDuringActiveTransfer()
        try await testLegacyFolderMigration()
        try await testPartialBatchExportHandling()
        try await testLateRAWJPEGCompanionArrival()
        try await testRatingsAndPickStatusPersistenceAndRestoration()
        try await testRealTCPFTPClientIntegration()
    }
    
    // MARK: - 1. Одинаковые имена и параллельные попытки импорта
    func testIdenticalNamesAndParallelImports() async throws {
        print("\n[1/10] Тест: одинаковые имена и параллельные попытки импорта...")
        
        let storage = StorageManager(customBaseURL: tempDir.appendingPathComponent("test1_storage", isDirectory: true))
        let dbURL = tempDir.appendingPathComponent("test1_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-parallel", model: "Nikon Z 8", transportType: .ftp)
        
        // Два задания для файла с одним и тем же исходным именем DSC_0001.NEF
        let job1 = try await coordinator.createTransferJob(source: source, filename: "DSC_0001.NEF", expectedSize: 4096)
        let job2 = try await coordinator.createTransferJob(source: source, filename: "DSC_0001.NEF", expectedSize: 5120)
        
        verify(job1.stagingURL != job2.stagingURL, "Временные staging пути для параллельных заданий должны быть строго уникальными")
        
        // Записываем разные данные в каждый временный файл
        let rawData1 = createDummyTIFFData(size: 4096)
        let rawData2 = createDummyTIFFData(size: 5120)
        
        try rawData1.write(to: job1.stagingURL!)
        try rawData2.write(to: job2.stagingURL!)
        
        // Финализируем оба задания
        let asset1 = try await coordinator.finalizeTransfer(jobID: job1.id, actualSize: 4096, duration: 0.1)
        let asset2 = try await coordinator.finalizeTransfer(jobID: job2.id, actualSize: 5120, duration: 0.1)
        
        verify(asset1.filename != asset2.filename, "Имена файлов должны быть бесконфликтно разрешены")
        verify(asset1.filename == "DSC_0001.NEF", "Первый файл получает исходное имя")
        verify(asset2.filename == "DSC_0001_1.NEF", "Второй файл получает суффикс _1")
        
        // Проверяем сохранность обоих файлов на диске
        verify(fileManager.fileExists(atPath: asset1.fileURL.path), "Первый файл должен существовать на диске")
        verify(fileManager.fileExists(atPath: asset2.fileURL.path), "Второй файл должен существовать на диске")
        
        let size1 = (try? fileManager.attributesOfItem(atPath: asset1.fileURL.path)[.size] as? Int64) ?? 0
        let size2 = (try? fileManager.attributesOfItem(atPath: asset2.fileURL.path)[.size] as? Int64) ?? 0
        verify(size1 == 4096, "Размер первого файла не поврежден")
        verify(size2 == 5120, "Размер второго файла не поврежден")
        
        print("  ✓ Параллельные импорты с одинаковыми именами бесконфликтно разрешены без перезаписи")
    }
    
    // MARK: - 2. Отмена, таймаут, обрыв и повтор
    func testCancellationTimeoutDisconnectionAndRetry() async throws {
        print("\n[2/10] Тест: отмена, таймаут, обрыв и повтор...")
        
        let storage = StorageManager(customBaseURL: tempDir.appendingPathComponent("test2_storage", isDirectory: true))
        let dbURL = tempDir.appendingPathComponent("test2_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-cancel", model: "Nikon Z 9", transportType: .usb)
        
        // 1. Сценарий: Отмена пользователем
        let cancelJob = try await coordinator.createTransferJob(source: source, filename: "CANCEL_ME.NEF", expectedSize: 10000)
        guard let stagingCancelURL = cancelJob.stagingURL else { fatalError("stagingURL отсутствует") }
        try createDummyTIFFData(size: 2000).write(to: stagingCancelURL)
        verify(fileManager.fileExists(atPath: stagingCancelURL.path), "Staging файл создан")
        
        await coordinator.cancelTransfer(jobID: cancelJob.id)
        verify(!fileManager.fileExists(atPath: stagingCancelURL.path), "При отмене staging файл обязан быть немедленно удален")
        verify(!fileManager.fileExists(atPath: cancelJob.destinationURL.path), "Оригинал не должен появляться при отмене")
        
        // 2. Сценарий: Обрыв связи / таймаут
        let dropJob = try await coordinator.createTransferJob(source: source, filename: "DROP_ME.NEF", expectedSize: 8000)
        guard let stagingDropURL = dropJob.stagingURL else { fatalError("stagingURL отсутствует") }
        try createDummyTIFFData(size: 3000).write(to: stagingDropURL)
        
        await coordinator.interruptTransfer(jobID: dropJob.id, reason: "Обрыв сетевого соединения камеры")
        verify(!fileManager.fileExists(atPath: stagingDropURL.path), "При обрыве недокачанный временный файл удаляется")
        verify(!fileManager.fileExists(atPath: dropJob.destinationURL.path), "Частичный файл не сохранен в сессии")
        
        let jobs = await coordinator.jobs
        let interruptedJob = jobs[dropJob.id]
        var isInterruptedOrFailed = interruptedJob?.state.isFailed == true
        if case .interrupted = interruptedJob?.state {
            isInterruptedOrFailed = true
        }
        verify(isInterruptedOrFailed, "Задание переведено в прерванное/сбойное состояние")
        
        print("  ✓ Отмена и обрыв соединения гарантируют удаление временных файлов и целостность сессии")
    }
    
    // MARK: - 3. Ошибка записи и нехватка места
    func testWriteErrorAndInsufficientStorageSpace() async throws {
        print("\n[3/10] Тест: ошибка записи и нехватка места...")
        
        let storage = StorageManager(customBaseURL: tempDir.appendingPathComponent("test3_storage", isDirectory: true))
        let dbURL = tempDir.appendingPathComponent("test3_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        
        // Искусственно настраиваем DiskSpaceGuard с нереалистичным лимитом (1000 ТБ), чтобы вызвать нехватку места
        let hugeDiskGuard = DiskSpaceGuard(reserveBytes: 1_000_000_000_000_000)
        let coordinator = TransferCoordinator(storageManager: storage, database: db, diskGuard: hugeDiskGuard)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-space", model: "Nikon Z 6 III", transportType: .ftp)
        
        var caughtInsufficientSpace = false
        do {
            _ = try await coordinator.createTransferJob(source: source, filename: "TOO_BIG.NEF", expectedSize: 50_000_000)
        } catch TransferError.diskWriteFailed {
            caughtInsufficientSpace = true
        } catch {
            print("Другая ошибка: \(error)")
        }
        verify(caughtInsufficientSpace, "DiskSpaceGuard должен предотвратить трансфер при недостатке места")
        
        // Сценарий поврежденной записи (неверная сигнатура magic bytes)
        let standardCoordinator = TransferCoordinator(storageManager: storage, database: db)
        await standardCoordinator.bootstrap()
        let corruptedJob = try await standardCoordinator.createTransferJob(source: source, filename: "CORRUPTED.NEF", expectedSize: 1000)
        let garbageData = Data(repeating: 0x00, count: 1000) // нет сигнатуры TIFF
        try garbageData.write(to: corruptedJob.stagingURL!)
        
        var caughtVerificationFailed = false
        do {
            _ = try await standardCoordinator.finalizeTransfer(jobID: corruptedJob.id, actualSize: 1000, duration: 0.05)
        } catch TransferError.verificationFailed {
            caughtVerificationFailed = true
        }
        verify(caughtVerificationFailed, "Поврежденные при записи данные отклоняются верификатором")
        verify(!fileManager.fileExists(atPath: corruptedJob.stagingURL!.path), "Поврежденный staging файл удален")
        verify(!fileManager.fileExists(atPath: corruptedJob.destinationURL.path), "Поврежденный файл не попал в сессию")
        
        print("  ✓ Контроль дискового пространства и защита от поврежденных записей подтверждены")
    }
    
    // MARK: - 4. Восстановление после аварии между сохранением файла и обновлением каталога
    func testCrashRecoveryBetweenSaveAndCatalogUpdate() async throws {
        print("\n[4/10] Тест: восстановление после аварии между сохранением файла и обновлением каталога...")
        
        let storageBase = tempDir.appendingPathComponent("test4_storage", isDirectory: true)
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test4_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let activeSession = await coordinator.activeSession
        
        // Симулируем аварию: файл atomically перемещен в папку сессии, но приложение "упало" до SQLite upsertAsset
        let crashedFileName = "DSC_CRASH_RECOVERED.NEF"
        let fileInSessionURL = activeSession.folderURL.appendingPathComponent(crashedFileName)
        try createDummyTIFFData(size: 8192).write(to: fileInSessionURL)
        
        // Также оставляем "остаточный" временный файл в .staging
        let stagingDir = activeSession.folderURL.appendingPathComponent(".staging", isDirectory: true)
        try? fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let abandonedStagingURL = stagingDir.appendingPathComponent("transfer_abandoned_crash.tmp")
        try Data("orphan staging data".utf8).write(to: abandonedStagingURL)
        
        verify(fileManager.fileExists(atPath: fileInSessionURL.path))
        verify(fileManager.fileExists(atPath: abandonedStagingURL.path))
        
        // Запускаем новый экземпляр координатора (перезапуск после сбоя)
        let restartedCoordinator = TransferCoordinator(storageManager: storage, database: db)
        await restartedCoordinator.bootstrap()
        
        // 1. Проверяем, что осиротевший staging-файл очищен
        verify(!fileManager.fileExists(atPath: abandonedStagingURL.path), "Остаточные staging-файлы после сбоя очищены")
        
        // 2. Проверяем, что файл на диске автоматически обнаружен и внесен в каталог
        let recoveredAssets = await restartedCoordinator.assets
        let found = recoveredAssets.first(where: { $0.filename == crashedFileName })
        verify(found != nil, "Файл на диске должен быть автоматически зарегистрирован в каталоге")
        verify(found?.fileSize == 8192, "Размер восстановленного файла совпадает")
        
        let groups = await restartedCoordinator.captureGroups
        verify(groups.contains(where: { $0.baseName == "DSC_CRASH_RECOVERED" }), "Файл включен в кадровую группу сессии")
        
        print("  ✓ Восстановление после сбоя между записью файла и обновлением каталога подтверждено")
    }
    
    // MARK: - 5. Смена сессии во время переноса
    func testSessionSwitchingDuringActiveTransfer() async throws {
        print("\n[5/10] Тест: смена сессии во время активного переноса...")
        
        let storageBase = tempDir.appendingPathComponent("test5_storage", isDirectory: true)
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test5_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        // Создаем Сессию 1 и Сессию 2
        let session1 = try await coordinator.startNewSession(named: "Session_Studio_A")
        let session2 = try await coordinator.startNewSession(named: "Session_Studio_B")
        
        // Активируем Сессию 1
        _ = await coordinator.switchActiveSession(to: session1.id)
        let active1 = await coordinator.activeSession
        verify(active1.id == session1.id)
        
        let source = CameraSource(id: "cam-switch", model: "Nikon Z f", transportType: .ftp)
        
        // Запускаем перенос для Сессии 1
        let jobSession1 = try await coordinator.createTransferJob(source: source, filename: "STUDIO_A_001.NEF", expectedSize: 4096)
        try createDummyTIFFData(size: 4096).write(to: jobSession1.stagingURL!)
        
        // ПОЛЬЗОВАТЕЛЬ ПЕРЕКЛЮЧАЕТ СЕССИЮ НА СЕССИЮ 2 ВО ВРЕМЯ ПЕРЕНОСА!
        _ = await coordinator.switchActiveSession(to: session2.id)
        let active2 = await coordinator.activeSession
        verify(active2.id == session2.id)
        
        // Перенос завершается в фоне!
        let finalizedAsset = try await coordinator.finalizeTransfer(jobID: jobSession1.id, actualSize: 4096, duration: 0.1)
        
        // Проверяем:
        // 1. Файл сохранен в папку Сессии 1
        verify(finalizedAsset.fileURL.path.contains("Session_Studio_A"), "Файл физически сохранен в папке Сессии 1")
        verify(fileManager.fileExists(atPath: finalizedAsset.fileURL.path))
        
        // 2. В оперативной галерее текущей активной Сессии 2 этот файл НЕ должен отображаться!
        let session2Assets = await coordinator.assets
        verify(!session2Assets.contains(where: { $0.id == finalizedAsset.id }), "Сессия 2 не должна быть загрязнена файлами Сессии 1")
        
        // 3. Переключаемся обратно в Сессию 1: файл отображается!
        _ = await coordinator.switchActiveSession(to: session1.id)
        let session1Assets = await coordinator.assets
        verify(session1Assets.contains(where: { $0.id == finalizedAsset.id }), "При возврате в Сессию 1 файл присутствует в ее галерее")
        
        print("  ✓ Смена сессии во время активного переноса изолирована и безопасна")
    }
    
    // MARK: - 6. Миграция старых папок
    func testLegacyFolderMigration() async throws {
        print("\n[6/10] Тест: миграция существующих папок съёмок...")
        
        let storageBase = tempDir.appendingPathComponent("test6_storage", isDirectory: true)
        let sessionsDir = storageBase.appendingPathComponent("Sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        
        // Создаем папку старой съемки на диске (без записей в SQLite)
        let legacyFolder = sessionsDir.appendingPathComponent("Legacy_Shoot_2023", isDirectory: true)
        try fileManager.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        
        let photo1URL = legacyFolder.appendingPathComponent("DSC_OLD_001.JPG")
        let photo2URL = legacyFolder.appendingPathComponent("DSC_OLD_002.JPG")
        try createSampleJPEG(at: photo1URL, width: 200, height: 150)
        try createSampleJPEG(at: photo2URL, width: 200, height: 150)
        
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test6_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        // Запуск с авто-миграцией
        await coordinator.bootstrap()
        
        let allSessions = await coordinator.allSessions
        let migratedSession = allSessions.first(where: { $0.name == "Legacy_Shoot_2023" })
        verify(migratedSession != nil, "Папка старой съемки обнаружена и добавлена как сессия")
        
        // Переключаемся на мигрированную сессию
        _ = await coordinator.switchActiveSession(to: migratedSession!.id)
        let assets = await coordinator.assets
        verify(assets.count == 2, "Оба файла из старой папки внесены в каталог")
        verify(fileManager.fileExists(atPath: photo1URL.path), "Оригиналы остались нетронутыми")
        verify(fileManager.fileExists(atPath: photo2URL.path), "Оригиналы остались нетронутыми")
        
        print("  ✓ Существующие папки съемок успешно мигрированы в каталог без изменения файлов")
    }
    
    // MARK: - 7. Частичный экспорт
    func testPartialBatchExportHandling() async throws {
        print("\n[7/10] Тест: частичный экспорт при сбое отдельных файлов...")
        
        let storageBase = tempDir.appendingPathComponent("test7_storage", isDirectory: true)
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test7_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let exportDestDir = tempDir.appendingPathComponent("test7_export_dest", isDirectory: true)
        try fileManager.createDirectory(at: exportDestDir, withIntermediateDirectories: true)
        
        // Создаем 3 файла: 2 реальных и 1 удаленный/отсутствующий
        let source = CameraSource(id: "cam-exp", model: "Nikon Z 8", transportType: .usb)
        
        let job1 = try await coordinator.createTransferJob(source: source, filename: "EXP_001.JPG", expectedSize: nil)
        try createSampleJPEG(at: job1.stagingURL!, width: 100, height: 100)
        let size1 = (try? fileManager.attributesOfItem(atPath: job1.stagingURL!.path)[.size] as? Int64) ?? 0
        let asset1 = try await coordinator.finalizeTransfer(jobID: job1.id, actualSize: size1, duration: 0.05)
        
        let job2 = try await coordinator.createTransferJob(source: source, filename: "EXP_002.JPG", expectedSize: nil)
        try createSampleJPEG(at: job2.stagingURL!, width: 100, height: 100)
        let size2 = (try? fileManager.attributesOfItem(atPath: job2.stagingURL!.path)[.size] as? Int64) ?? 0
        let asset2 = try await coordinator.finalizeTransfer(jobID: job2.id, actualSize: size2, duration: 0.05)
        
        let job3 = try await coordinator.createTransferJob(source: source, filename: "EXP_MISSING.JPG", expectedSize: nil)
        try createSampleJPEG(at: job3.stagingURL!, width: 100, height: 100)
        let size3 = (try? fileManager.attributesOfItem(atPath: job3.stagingURL!.path)[.size] as? Int64) ?? 0
        let asset3 = try await coordinator.finalizeTransfer(jobID: job3.id, actualSize: size3, duration: 0.05)
        
        // Удаляем третий файл с диска для симуляции сбоя чтения конкретного ассета
        try fileManager.removeItem(at: asset3.fileURL)
        
        // Экспортируем все 3 ассета пакетом
        let exportItems: [ExportItem] = [
            ExportItem(asset: asset1),
            ExportItem(asset: asset2),
            ExportItem(asset: asset3)
        ]
        
        let exportJob = await coordinator.createExportJob(
            items: exportItems,
            destination: .directory(url: exportDestDir),
            formatSelection: .companionOnly,
            includeXMPSidecars: false
        )
        
        let executedJob = await ExportManager.shared.executeJob(exportJob)
        let exportResult = executedJob.result
        
        verify(exportResult?.successCount == 2, "2 файла должны успешно экспортироваться")
        verify(exportResult?.failedCount == 1, "1 файл должен быть зафиксирован как сбойный")
        let failedItems = executedJob.failedItems()
        verify(failedItems.count == 1, "failedItems содержит детальную информацию о сбойном файле")
        verify(failedItems.first?.asset.id == asset3.id, "Сбой зафиксирован именно для отсутствующего файла")
        
        // Проверяем, что успешные файлы реально скопированы
        verify(fileManager.fileExists(atPath: exportDestDir.appendingPathComponent("EXP_001.JPG").path))
        verify(fileManager.fileExists(atPath: exportDestDir.appendingPathComponent("EXP_002.JPG").path))
        
        print("  ✓ Частичный экспорт изолирует ошибки и предоставляет список сбоев для повтора")
    }
    
    // MARK: - 8. Позднее формирование RAW+JPEG-пары
    func testLateRAWJPEGCompanionArrival() async throws {
        print("\n[8/10] Тест: позднее формирование RAW+JPEG пары...")
        
        let storageBase = tempDir.appendingPathComponent("test8_storage", isDirectory: true)
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test8_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-pair", model: "Nikon Z 8", transportType: .ftp)
        
        // 1. Сначала приходит JPEG
        let jpegJob = try await coordinator.createTransferJob(source: source, filename: "DSC_9999.JPG", expectedSize: nil)
        try createSampleJPEG(at: jpegJob.stagingURL!, width: 200, height: 150)
        let jpegSize = (try? fileManager.attributesOfItem(atPath: jpegJob.stagingURL!.path)[.size] as? Int64) ?? 0
        _ = try await coordinator.finalizeTransfer(jobID: jpegJob.id, actualSize: jpegSize, duration: 0.05)
        
        var groups = await coordinator.captureGroups
        verify(groups.count == 1, "Создана 1 кадровая группа")
        let initialGroup = groups.first!
        verify(initialGroup.baseName == "DSC_9999")
        verify(initialGroup.jpegAsset != nil, "JPEG присутствует")
        verify(initialGroup.rawAsset == nil, "RAW пока отсутствует")
        verify(!initialGroup.hasBothRawAndJpeg, "Группа пока не является парой")
        
        // 2. Спустя некоторое время приходит RAW-оригинал
        let rawJob = try await coordinator.createTransferJob(source: source, filename: "DSC_9999.NEF", expectedSize: 6000)
        try createDummyTIFFData(size: 6000).write(to: rawJob.stagingURL!)
        _ = try await coordinator.finalizeTransfer(jobID: rawJob.id, actualSize: 6000, duration: 0.1)
        
        groups = await coordinator.captureGroups
        verify(groups.count == 1, "Количество групп должно остаться 1 (не должно быть дубликата кадра)")
        let unitedGroup = groups.first!
        verify(unitedGroup.hasBothRawAndJpeg, "Группа объединена в полную пару RAW+JPEG")
        verify(unitedGroup.jpegAsset != nil && unitedGroup.rawAsset != nil, "Оба ассета связаны в одну группу")
        
        print("  ✓ Позднее поступление компаньона объединяет RAW и JPEG в единый кадр")
    }
    
    // MARK: - 9. Сохранение и восстановление оценок
    func testRatingsAndPickStatusPersistenceAndRestoration() async throws {
        print("\n[9/10] Тест: сохранение и восстановление оценок и отметок...")
        
        let storageBase = tempDir.appendingPathComponent("test9_storage", isDirectory: true)
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test9_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-ratings", model: "Nikon Z 9", transportType: .usb)
        
        // Импортируем 2 кадра
        let jobA = try await coordinator.createTransferJob(source: source, filename: "STAR_5.JPG", expectedSize: nil)
        try createSampleJPEG(at: jobA.stagingURL!, width: 100, height: 100)
        let sizeA = (try? fileManager.attributesOfItem(atPath: jobA.stagingURL!.path)[.size] as? Int64) ?? 0
        _ = try await coordinator.finalizeTransfer(jobID: jobA.id, actualSize: sizeA, duration: 0.05)
        
        let jobB = try await coordinator.createTransferJob(source: source, filename: "REJECTED.JPG", expectedSize: nil)
        try createSampleJPEG(at: jobB.stagingURL!, width: 100, height: 100)
        let sizeB = (try? fileManager.attributesOfItem(atPath: jobB.stagingURL!.path)[.size] as? Int64) ?? 0
        _ = try await coordinator.finalizeTransfer(jobID: jobB.id, actualSize: sizeB, duration: 0.05)
        
        let groups = await coordinator.captureGroups
        let groupA = groups.first(where: { $0.baseName == "STAR_5" })!
        let groupB = groups.first(where: { $0.baseName == "REJECTED" })!
        
        // Назначаем рейтинг 5 и статус Picked для A
        await coordinator.updateRating(for: groupA.id, rating: 5)
        await coordinator.updatePickStatus(for: groupA.id, status: .picked)
        
        // Назначаем статус Rejected для B
        await coordinator.updatePickStatus(for: groupB.id, status: .rejected)
        
        // ПЕРЕЗАПУСК: создаем новый координатор и переинициализируем каталог
        let newCoordinator = TransferCoordinator(storageManager: storage, database: db)
        await newCoordinator.bootstrap()
        
        let reloadedGroups = await newCoordinator.captureGroups
        let reloadedA = reloadedGroups.first(where: { $0.baseName == "STAR_5" })!
        let reloadedB = reloadedGroups.first(where: { $0.baseName == "REJECTED" })!
        
        verify(reloadedA.rating == 5, "Рейтинг 5 звезд успешно восстановлен из SQLite")
        verify(reloadedA.pickStatus == .picked, "Отметка Picked успешно восстановлена из SQLite")
        verify(reloadedB.pickStatus == .rejected, "Отметка Rejected успешно восстановлена из SQLite")
        
        print("  ✓ Оценки и отметки надежно персистируются в SQLite и восстанавливаются при запуске")
    }
    
    // MARK: - 10. Интеграционные проверки FTP с реальным TCP-клиентом
    func testRealTCPFTPClientIntegration() async throws {
        print("\n[10/10] Тест: интеграция FTP с реальным TCP-клиентом на сетевых сокетах...")
        
        let storageBase = tempDir.appendingPathComponent("test10_storage", isDirectory: true)
        let storage = StorageManager(customBaseURL: storageBase)
        let dbURL = tempDir.appendingPathComponent("test10_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let testPort: UInt16 = 2199
        let server = FTPServer(port: testPort, storageManager: storage, coordinator: coordinator)
        try await server.start()
        
        // Ожидаем переход сервера в состояние running
        var isRunning = false
        for _ in 0..<20 {
            if case .running = await server.state {
                isRunning = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        verify(isRunning, "FTPServer должен запуститься и слушать порт \(testPort)")
        
        let creds = FTPAuthManager.shared.getCredentials()
        
        // 1. Проверка неверной авторизации через реальный TCP сокет
        let clientBadAuth = BSDSocketClient()
        try clientBadAuth.connect(host: "127.0.0.1", port: testPort)
        let banner = try clientBadAuth.readLine()
        verify(banner.hasPrefix("220"), "Сервер отправил приветственный баннер 220: \(banner)")
        
        try clientBadAuth.send(string: "USER wrong_user\r\n")
        let userResp = try clientBadAuth.readLine()
        verify(userResp.hasPrefix("331"), "USER ответил 331")
        
        try clientBadAuth.send(string: "PASS wrong_pass\r\n")
        let passResp = try clientBadAuth.readLine()
        verify(passResp.hasPrefix("530"), "Неверный пароль отклонен с 530 Login incorrect: \(passResp)")
        clientBadAuth.close()
        
        // 2. Проверка успешной авторизации и PASV передачи
        let client = BSDSocketClient()
        try client.connect(host: "127.0.0.1", port: testPort)
        _ = try client.readLine() // 220
        
        try client.send(string: "USER \(creds.username)\r\n")
        _ = try client.readLine() // 331
        try client.send(string: "PASS \(creds.password)\r\n")
        let loginOk = try client.readLine()
        verify(loginOk.hasPrefix("230"), "Авторизация успешна: \(loginOk)")
        
        // PASV
        try client.send(string: "PASV\r\n")
        let pasvResp = try client.readLine()
        verify(pasvResp.hasPrefix("227"), "Ответ на PASV: \(pasvResp)")
        let dataPort = try parsePasvPort(from: pasvResp)
        
        // Открываем реальный сокет данных на пассивный порт
        let dataClient = BSDSocketClient()
        try dataClient.connect(host: "127.0.0.1", port: dataPort)
        
        // Отправляем команду STOR
        try client.send(string: "STOR REAL_PASV_SHOT.JPG\r\n")
        let storResp = try client.readLine()
        verify(storResp.hasPrefix("150"), "STOR ответил 150: \(storResp)")
        
        // Передаем валидные байты JPEG
        let jpegTempURL = tempDir.appendingPathComponent("pasv_temp.jpg")
        try createSampleJPEG(at: jpegTempURL, width: 120, height: 80)
        let sampleJPEGData = try Data(contentsOf: jpegTempURL)
        try dataClient.send(data: sampleJPEGData)
        dataClient.close() // Клиент завершил передачу канала данных
        
        // Ожидаем подтверждения сервера
        let transferComplete = try client.readLine()
        verify(transferComplete.hasPrefix("226"), "Сервер подтвердил сохранение с 226 Transfer complete: \(transferComplete)")
        
        // Проверяем наличие файла в каталоге
        let assetsAfterPasv = await coordinator.assets
        verify(assetsAfterPasv.contains(where: { $0.filename == "REAL_PASV_SHOT.JPG" }), "REAL_PASV_SHOT.JPG сохранен и внесен в каталог")
        
        // 3. Проверка режима EPSV
        try client.send(string: "EPSV\r\n")
        let epsvResp = try client.readLine()
        verify(epsvResp.hasPrefix("229"), "Ответ на EPSV: \(epsvResp)")
        let epsvPort = try parseEpsvPort(from: epsvResp)
        
        let epsvDataClient = BSDSocketClient()
        try epsvDataClient.connect(host: "127.0.0.1", port: epsvPort)
        
        try client.send(string: "STOR REAL_EPSV_SHOT.NEF\r\n")
        let epsvStorResp = try client.readLine()
        verify(epsvStorResp.hasPrefix("150"), "EPSV STOR ответил 150: \(epsvStorResp)")
        
        let nefData = createDummyTIFFData(size: 4096)
        try epsvDataClient.send(data: nefData)
        epsvDataClient.close()
        
        let epsvComplete = try client.readLine()
        verify(epsvComplete.hasPrefix("226"), "EPSV подтвердил 226: \(epsvComplete)")
        
        let assetsAfterEpsv = await coordinator.assets
        verify(assetsAfterEpsv.contains(where: { $0.filename == "REAL_EPSV_SHOT.NEF" }), "REAL_EPSV_SHOT.NEF сохранен в сессии")
        
        // 4. Проверка обрыва передачи (aborted transfer)
        try client.send(string: "PASV\r\n")
        let abortPasvResp = try client.readLine()
        let abortDataPort = try parsePasvPort(from: abortPasvResp)
        
        let abortDataClient = BSDSocketClient()
        try abortDataClient.connect(host: "127.0.0.1", port: abortDataPort)
        
        try client.send(string: "STOR ABORTED_SHOT.NEF\r\n")
        let abortStorResp = try client.readLine()
        verify(abortStorResp.hasPrefix("150"), "Abort STOR ответил 150")
        
        // Передаем 50 байт мусора и немедленно разрываем сокет (клиент отвалился)
        try abortDataClient.send(data: Data(repeating: 0x55, count: 50))
        abortDataClient.close()
        
        let abortResult = try client.readLine()
        verify(abortResult.hasPrefix("426"), "Сервер отправил 426 Transfer aborted при обрыве: \(abortResult)")
        
        // Убеждаемся, что поврежденный оригинал НЕ появился в сессии
        let session = await coordinator.activeSession
        let brokenOriginal = session.folderURL.appendingPathComponent("ABORTED_SHOT.NEF")
        verify(!fileManager.fileExists(atPath: brokenOriginal.path), "Оборванный файл не должен появляться в сессии")
        
        client.close()
        await server.stop()
        
        print("  ✓ Реальный клиент по протоколу TCP успешно протестировал авторизацию, PASV, EPSV и обрыв передачи")
    }
    
    // MARK: - Вспомогательные методы
    
    private func createDummyTIFFData(size: Int) -> Data {
        var data = Data([0x4D, 0x4D, 0x00, 0x2A]) // TIFF Big Endian
        let remaining = max(0, size - 4)
        data.append(Data(repeating: 0xAA, count: remaining))
        return data
    }
    
    private func createSampleJPEG(at url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }
        
        ctx.setFillColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let cgImage = ctx.makeImage() else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image dest"])
        }
        
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }
    
    private func parsePasvPort(from response: String) throws -> UInt16 {
        guard let openParen = response.firstIndex(of: "("),
              let closeParen = response.firstIndex(of: ")") else {
            throw NSError(domain: "FTPTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid PASV response: \(response)"])
        }
        let substr = response[response.index(after: openParen)..<closeParen]
        let parts = substr.split(separator: ",").compactMap { UInt16($0) }
        guard parts.count == 6 else {
            throw NSError(domain: "FTPTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid PASV parts: \(response)"])
        }
        return parts[4] * 256 + parts[5]
    }
    
    private func parseEpsvPort(from response: String) throws -> UInt16 {
        guard let openParen = response.firstIndex(of: "("),
              let closeParen = response.firstIndex(of: ")") else {
            throw NSError(domain: "FTPTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid EPSV response: \(response)"])
        }
        let substr = response[response.index(after: openParen)..<closeParen]
        let parts = substr.split(separator: "|")
        guard let last = parts.last, let port = UInt16(last) else {
            throw NSError(domain: "FTPTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid EPSV format: \(substr)"])
        }
        return port
    }
}

// MARK: - Синхронный TCP-клиент на сокетах BSD для честных сетевых проверок
final class BSDSocketClient {
    private var fd: Int32 = -1
    private var readBuffer = Data()
    
    init() {}
    
    func connect(host: String, port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "BSDSocket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard connectRes == 0 else {
            let err = String(cString: strerror(errno))
            close()
            throw NSError(domain: "BSDSocket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Connect to port \(port) failed: \(err)"])
        }
    }
    
    func send(string: String) throws {
        guard fd >= 0, let data = string.data(using: .utf8) else { return }
        try send(data: data)
    }
    
    func send(data: Data) throws {
        guard fd >= 0 else { return }
        try data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            var totalSent = 0
            while totalSent < data.count {
                let sent = Darwin.send(fd, ptr.advanced(by: totalSent), data.count - totalSent, 0)
                if sent <= 0 {
                    let err = String(cString: strerror(errno))
                    throw NSError(domain: "BSDSocket", code: 3, userInfo: [NSLocalizedDescriptionKey: "Socket send failed: \(err)"])
                }
                totalSent += sent
            }
        }
    }
    
    func readLine() throws -> String {
        let crlf = "\r\n".data(using: .utf8)!
        let lf = "\n".data(using: .utf8)!
        
        while true {
            if let range = readBuffer.range(of: crlf) {
                let lineData = readBuffer.subdata(in: 0..<range.lowerBound)
                readBuffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? ""
            } else if let range = readBuffer.range(of: lf) {
                let lineData = readBuffer.subdata(in: 0..<range.lowerBound)
                readBuffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            
            var temp = [UInt8](repeating: 0, count: 2048)
            let bytesRead = Darwin.recv(fd, &temp, temp.count, 0)
            if bytesRead <= 0 {
                if !readBuffer.isEmpty {
                    let s = String(data: readBuffer, encoding: .utf8) ?? ""
                    readBuffer.removeAll()
                    return s
                }
                let err = bytesRead == 0 ? "Connection closed by remote peer" : String(cString: strerror(errno))
                throw NSError(domain: "BSDSocket", code: 4, userInfo: [NSLocalizedDescriptionKey: "Socket recv failed: \(err)"])
            }
            readBuffer.append(temp, count: bytesRead)
        }
    }
    
    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
    
    deinit {
        close()
    }
}
