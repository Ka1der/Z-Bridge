import Foundation
import SQLite3

@main
struct Stage2And3VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 2 И 3 ===")
        
        let tests = Stage2And3VerificationSuite()
        try await tests.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПОВ 2 И 3 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

final class Stage2And3VerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage2_3_Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.tempBaseURL = root
        self.dbURL = root.appendingPathComponent("test_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        try await testTemporaryStagingAndAtomicMove()
        try await testNameCollisionResolutionWithoutOverwrite()
        try await testFilenameSanitizationAndPathTraversalDefense()
        try await testDiskSpaceControlAndSizeMismatch()
        try await testActiveJobProtectionDuringSessionClear()
        try await testSQLitePersistenceAndWALMode()
        try await testStartupCrashRecoveryAndStagingCleanup()
        try await testReconcileMissingFilesAndSessionImport()
        try await testSessionStatsAndLifecycle()
    }
    
    // MARK: - 1. Staging-файл и атомарное перемещение
    func testTemporaryStagingAndAtomicMove() async throws {
        print("\n[1/9] Тест приема во временный файл и атомарного перемещения...")
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-1", model: "Nikon Z 8", transportType: .usb)
        let job = try await coordinator.createTransferJob(source: source, filename: "TEST_ATOMIC.NEF", expectedSize: 1024)
        
        guard let staging = job.stagingURL else {
            assertionFailure("Задание должно иметь stagingURL во временной папке")
            return
        }
        assert(staging.path.contains(".staging"), "stagingURL должен находиться в подпапке .staging")
        assert(staging.pathExtension == "tmp", "Временный файл должен иметь расширение .tmp")
        assert(!FileManager.default.fileExists(atPath: job.destinationURL.path), "До финализации финальный файл НЕ должен существовать на диске!")
        
        // Симулируем запись во временный файл
        var validNEF = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        validNEF.append(Data(repeating: 0x07, count: 1016))
        try validNEF.write(to: staging)
        assert(FileManager.default.fileExists(atPath: staging.path), "Временный файл должен существовать во время записи")
        
        // Финализация
        let asset = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: 1024, duration: 0.05)
        
        assert(!FileManager.default.fileExists(atPath: staging.path), "После атомарного перемещения временный файл должен исчезнуть")
        assert(FileManager.default.fileExists(atPath: asset.fileURL.path), "Файл должен появиться в окончательном расположении")
        assert(asset.fileSize == 1024, "Размер должен быть 1024 байта")
        assert(asset.sha256Checksum != nil, "Должна быть вычислена контрольная сумма SHA-256")
        
        // Проверяем, что в БД запись появилась только после финализации
        let storedAssets = await db.getAssets(for: job.sessionID)
        assert(storedAssets.contains(where: { $0.id == asset.id }), "Ассет должен быть зарегистрирован в БД")
        
        print("  ✓ Запись во временный файл и атомарный move подтверждены")
    }
    
    // MARK: - 2. Разрешение коллизий без перезаписи
    func testNameCollisionResolutionWithoutOverwrite() async throws {
        print("\n[2/9] Тест разрешения конфликтов имен без перезаписи оригинала...")
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-collision", model: "Nikon Z 9", transportType: .ftp)
        
        // 1. Первый кадр DSC_0001.NEF с байтами 0xAA
        let job1 = try await coordinator.createTransferJob(source: source, filename: "DSC_0001.NEF")
        var data1 = Data([0x49, 0x49, 0x2A, 0x00])
        data1.append(Data(repeating: 0xAA, count: 100))
        try data1.write(to: job1.stagingURL!)
        let asset1 = try await coordinator.finalizeTransfer(jobID: job1.id, actualSize: Int64(data1.count), duration: 0.01)
        assert(asset1.filename == "DSC_0001.NEF", "Первый файл должен получить оригинальное имя")
        
        // 2. Второй кадр с ТАКИМ ЖЕ именем DSC_0001.NEF, но другими байтами 0xBB
        let job2 = try await coordinator.createTransferJob(source: source, filename: "DSC_0001.NEF")
        var data2 = Data([0x49, 0x49, 0x2A, 0x00])
        data2.append(Data(repeating: 0xBB, count: 200))
        try data2.write(to: job2.stagingURL!)
        let asset2 = try await coordinator.finalizeTransfer(jobID: job2.id, actualSize: Int64(data2.count), duration: 0.01)
        
        // Проверяем, что коллизия разрешена БЕЗ перезаписи
        assert(asset2.filename == "DSC_0001_1.NEF", "Второй файл должен получить имя DSC_0001_1.NEF, получено: \(asset2.filename)")
        assert(FileManager.default.fileExists(atPath: asset1.fileURL.path), "Оригинальный DSC_0001.NEF должен сохраниться")
        assert(FileManager.default.fileExists(atPath: asset2.fileURL.path), "Новый DSC_0001_1.NEF должен существовать")
        
        let read1 = try Data(contentsOf: asset1.fileURL)
        let read2 = try Data(contentsOf: asset2.fileURL)
        assert(read1 == data1, "Содержимое первого файла не должно измениться!")
        assert(read2 == data2, "Содержимое второго файла должно соответствовать новым байтам!")
        
        print("  ✓ Коллизия имен корректно разрешена: DSC_0001.NEF и DSC_0001_1.NEF не повредили друг друга")
    }
    
    // MARK: - 3. Защита от path traversal
    func testFilenameSanitizationAndPathTraversalDefense() async throws {
        print("\n[3/9] Тест валидации имени и защиты от path traversal...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let session = try await storage.createNewSession(named: "SecuritySession")
        
        // Попытка выхода через ../../etc/passwd
        do {
            _ = try await storage.createStagingURL(for: "../../etc/passwd", in: session, jobID: UUID())
            assertionFailure("Path traversal ../../ должен вызывать ошибку!")
        } catch {
            print("  ✓ Попытка выхода из каталога успешно заблокирована: \(error.localizedDescription)")
        }
        
        // Попытка с нулевым байтом
        do {
            _ = try await storage.createStagingURL(for: "DSC_0001\0.NEF", in: session, jobID: UUID())
            assertionFailure("Нулевой байт должен быть заблокирован!")
        } catch {
            print("  ✓ Имя с нулевым байтом успешно отклонено")
        }
    }
    
    // MARK: - 4. Контроль дискового пространства и несовпадение размера
    func testDiskSpaceControlAndSizeMismatch() async throws {
        print("\n[4/9] Тест контроля дискового пространства и несовпадения размера...")
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        // Guard с искусственным гигантским требованием 10 Петабайт
        let hugeGuard = DiskSpaceGuard(reserveBytes: 10_000_000_000_000_000)
        let storage = StorageManager(customBaseURL: tempBaseURL, diskGuard: hugeGuard)
        let coordinator = TransferCoordinator(storageManager: storage, database: db, diskGuard: hugeGuard)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-disk", model: "Nikon Z 8", transportType: .usb)
        
        // Проверяем отказ до начала записи из-за нехватки места
        do {
            _ = try await coordinator.createTransferJob(source: source, filename: "BIG_PHOTO.NEF", expectedSize: 50 * 1024 * 1024)
            assertionFailure("Должна быть выброшена ошибка нехватки дискового пространства")
        } catch {
            print("  ✓ Контроль места до начала записи успешно сработал: \(error.localizedDescription)")
        }
        
        // Проверяем несовпадение ожидаемого размера (expected != actual)
        let normalGuard = DiskSpaceGuard(reserveBytes: 1024) // обычный порог
        let normalStorage = StorageManager(customBaseURL: tempBaseURL, diskGuard: normalGuard)
        let normalCoordinator = TransferCoordinator(storageManager: normalStorage, database: db, diskGuard: normalGuard)
        await normalCoordinator.bootstrap()
        
        let job = try await normalCoordinator.createTransferJob(source: source, filename: "SIZE_TEST.NEF", expectedSize: 5000)
        // Записываем только 100 байт вместо 5000
        var partialData = Data([0x49, 0x49, 0x2A, 0x00])
        partialData.append(Data(repeating: 0x01, count: 96))
        try partialData.write(to: job.stagingURL!)
        
        do {
            _ = try await normalCoordinator.finalizeTransfer(jobID: job.id, actualSize: Int64(partialData.count), duration: 0.01)
            assertionFailure("Несовпадение размера должно было привести к ошибке верификации")
        } catch {
            print("  ✓ Несовпадение ожидаемого размера корректно отклонено: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 5. Защита активных заданий при очистке/удалении сессии
    func testActiveJobProtectionDuringSessionClear() async throws {
        print("\n[5/9] Тест защиты активных заданий от удаления сессии...")
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-active", model: "Nikon Z f", transportType: .usb)
        let activeJob = try await coordinator.createTransferJob(source: source, filename: "IN_FLIGHT.NEF")
        // Задание находится в состоянии .pending (не терминальное)
        
        do {
            try await coordinator.clearActiveSession()
            assertionFailure("Очистка сессии с активным заданием должна блокироваться!")
        } catch {
            print("  ✓ Очистка сессии с активным заданием успешно заблокирована: \(error.localizedDescription)")
        }
        
        // Отменяем задание
        await coordinator.cancelTransfer(jobID: activeJob.id)
        
        // Теперь очистка должна пройти успешно
        try await coordinator.clearActiveSession()
        print("  ✓ После завершения задания сессия успешно очищена")
    }
    
    // MARK: - 6. Персистентность в SQLite и WAL-режим
    func testSQLitePersistenceAndWALMode() async throws {
        print("\n[6/9] Тест базы данных SQLite (WAL-режим, персистентность сессий и ассетов)...")
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        
        let sessionID = UUID()
        let session = CaptureSession(
            id: sessionID,
            name: "WAL_Test_Session",
            folderURL: tempBaseURL.appendingPathComponent("WAL_Session")
        )
        await db.upsertSession(session, isActive: true)
        
        let assetID = UUID()
        let asset = MediaAsset(
            id: assetID,
            sessionID: sessionID,
            filename: "PERSIST_001.NEF",
            fileURL: tempBaseURL.appendingPathComponent("PERSIST_001.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 45_000_000,
            metadata: AssetMetadata(cameraModel: "Nikon Z 8", iso: 800),
            verificationResult: .valid(checksum: "abcdef123456"),
            sha256Checksum: "abcdef123456"
        )
        await db.upsertAsset(asset)
        
        // Читаем обратно
        let allSessions = await db.getAllSessions()
        assert(allSessions.contains(where: { $0.id == sessionID }), "Сессия должна быть найдена в SQLite")
        
        let active = await db.getActiveSession()
        assert(active?.id == sessionID, "Активная сессия должна быть прочитана из SQLite")
        
        let assets = await db.getAssets(for: sessionID)
        assert(assets.first?.id == assetID, "Ассет должен быть сохранен в SQLite со всеми метаданными")
        assert(assets.first?.sha256Checksum == "abcdef123456", "Контрольная сумма должна быть сохранена")
        assert(assets.first?.metadata.cameraModel == "Nikon Z 8", "Метаданные камеры должны быть сохранены")
        
        print("  ✓ Персистентность SQLite подтверждена")
    }
    
    // MARK: - 7. Восстановление после аварий и очистка остаточных staging файлов
    func testStartupCrashRecoveryAndStagingCleanup() async throws {
        print("\n[7/9] Тест восстановления после сбоев и очистки сиротских .tmp файлов...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let session = await storage.activeSession
        
        // Создаем сиротский .tmp файл в .staging папке
        let stagingFolder = session.folderURL.appendingPathComponent(".staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        let orphanFile = stagingFolder.appendingPathComponent("transfer_abandoned_DSC_9999.tmp")
        try Data([0x00, 0x01, 0x02]).write(to: orphanFile)
        assert(FileManager.default.fileExists(atPath: orphanFile.path), "Сиротский файл должен быть создан")
        
        // Создаем в БД задание со статусом 'Выполнение' (незавершенное до аварии)
        let incompleteJob = TransferJob(
            source: CameraSource(id: "cam-crash", model: "Nikon Z 8", transportType: .usb),
            sourceFileID: "INCOMPLETE.NEF",
            destinationURL: session.folderURL.appendingPathComponent("INCOMPLETE.NEF"),
            sessionID: session.id,
            state: .inProgress(progress: 0.3, bytesTransferred: 300, totalBytes: 1000)
        )
        await db.upsertJob(incompleteJob)
        
        // Запускаем bootstrap нового координатора (симулирует рестарт приложения)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        // 1. Проверяем, что сиротский .tmp файл был удален
        assert(!FileManager.default.fileExists(atPath: orphanFile.path), "Остаточный staging файл должен быть удален при старте!")
        
        // 2. Проверяем, что незавершенное задание переведено в 'Прервано'
        let jobs = await db.getJobs(for: session.id)
        let recovered = jobs.first(where: { $0.id == incompleteJob.id })
        if case .interrupted = recovered?.state {
            print("  ✓ Незавершенное задание корректно переведено в статус .interrupted")
        } else {
            assertionFailure("Ожидался статус .interrupted, получено: \(String(describing: recovered?.state))")
        }
        
        print("  ✓ Очистка сиротских файлов и восстановление прерванных заданий проверены")
    }
    
    // MARK: - 8. Сверка отсутствующих файлов и импорт существующих папок
    func testReconcileMissingFilesAndSessionImport() async throws {
        print("\n[8/9] Тест сверки отсутствующих файлов и импорта папок съемок...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let reconciler = DiskCatalogReconciler()
        
        // 1. Создаем папку на диске вручную, как будто пользователь создал ее в Documents/Sessions
        let manualSessionFolder = tempBaseURL.appendingPathComponent("Sessions", isDirectory: true).appendingPathComponent("Manual_Studio_2026", isDirectory: true)
        try FileManager.default.createDirectory(at: manualSessionFolder, withIntermediateDirectories: true)
        
        // Кладем в нее файл вручную
        let manualFile = manualSessionFolder.appendingPathComponent("MANUAL_0001.NEF")
        try Data([0x49, 0x49, 0x2A, 0x00, 0x01, 0x02, 0x03, 0x04]).write(to: manualFile)
        
        // Запускаем координатор, который выполнит импорт папки и файлов
        let coordinator = TransferCoordinator(storageManager: storage, database: db, reconciler: reconciler)
        await coordinator.bootstrap()
        
        let allSessions = await coordinator.allSessions
        assert(allSessions.contains(where: { $0.name == "Manual_Studio_2026" }), "Внешняя папка должна быть импортирована в каталог сессий")
        
        // 2. Симулируем внешнее удаление файла (пользователь удалил через приложение «Файлы»)
        let testAssetID = UUID()
        let activeSessionID = await coordinator.activeSession.id
        let missingAsset = MediaAsset(
            id: testAssetID,
            sessionID: activeSessionID,
            filename: "DELETED_EXTERNALLY.NEF",
            fileURL: tempBaseURL.appendingPathComponent("DELETED_EXTERNALLY.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 1000
        )
        await db.upsertAsset(missingAsset)
        
        let missingIDs = reconciler.reconcileAssetsWithDisk(knownAssets: [missingAsset])
        assert(missingIDs.contains(testAssetID), "Удаленный файл должен быть определен как отсутствующий")
        
        print("  ✓ Импорт внешних папок и обнаружение отсутствующих файлов подтверждены")
    }
    
    // MARK: - 9. Статистика сессий и жизненный цикл (создание, переименование, закрытие)
    func testSessionStatsAndLifecycle() async throws {
        print("\n[9/9] Тест статистики сессий и операций жизненного цикла...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        // 1. Создание новой сессии
        let session = try await coordinator.startNewSession(named: "Fashion_Shoot")
        let activeAfterStart = await coordinator.activeSession
        assert(activeAfterStart.id == session.id, "Новая сессия должна стать активной")
        
        // 2. Переименование сессии
        let renamed = try await coordinator.renameSession(id: session.id, newName: "Fashion_Shoot_Day1")
        assert(renamed.name == "Fashion_Shoot_Day1", "Имя должно измениться")
        assert(renamed.folderURL.lastPathComponent == "Fashion_Shoot_Day1", "Директория на диске должна быть переименована")
        
        // 3. Завершение сессии
        await coordinator.closeSession(id: session.id)
        let activeAfterClose = await coordinator.activeSession
        assert(activeAfterClose.isClosed == true, "Сессия должна быть помечена как завершенная")
        
        // 4. Проверка статистики
        let stats = await coordinator.getSessionStats(id: session.id)
        assert(stats.filesCount == 0, "Файлов пока 0")
        assert(stats.errorsCount == 0, "Ошибок 0")
        
        print("  ✓ Жизненный цикл сессии и подсчет статистики проверены")
    }
}
