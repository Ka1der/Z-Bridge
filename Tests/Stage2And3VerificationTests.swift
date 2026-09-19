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
        defer {
            try? FileManager.default.removeItem(at: tempBaseURL)
        }
        try await testTemporaryStagingAndAtomicMove()
        try await testNameCollisionResolutionWithoutOverwrite()
        try await testFilenameSanitizationAndPathTraversalDefense()
        try await testDiskSpaceControlAndSizeMismatch()
        try await testActiveJobProtectionDuringSessionClear()
        try await testSQLitePersistenceAndWALMode()
        try await testStartupCrashRecoveryAndStagingCleanup()
        try await testReconcileMissingFilesAndSessionImport()
        try await testSessionStatsAndLifecycle()
        try await testDuplicateSessionNamesCreateIsolatedFoldersAndDeleteProtection()
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
    
    // MARK: - 5. Защита активных заданий при очистке/удалении сессии и создании новой съемки
    func testActiveJobProtectionDuringSessionClear() async throws {
        print("\n[5/10] Тест защиты активных заданий от удаления сессии и их сохранения при startNewSession...")
        
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "cam-active", model: "Nikon Z f", transportType: .usb)
        let sessionA = await coordinator.activeSession
        
        // 1. Создаем задание переноса в sessionA
        let activeJob = try await coordinator.createTransferJob(source: source, filename: "IN_FLIGHT.NEF")
        assert(!activeJob.state.isTerminal, "Задание должно быть нетерминальным (.pending)")
        
        // Попытка очистить активную сессию с выполняющимся заданием должна блокироваться
        do {
            try await coordinator.clearActiveSession()
            assertionFailure("Очистка сессии с активным заданием должна блокироваться!")
        } catch {
            print("  ✓ Очистка сессии с активным заданием успешно заблокирована: \(error.localizedDescription)")
        }
        
        // 2. Создаем новую сессию (startNewSession)
        let sessionB = try await coordinator.startNewSession(named: "Session_B_Live")
        assert(sessionB.id != sessionA.id, "Должна быть создана новая сессия")
        
        // ВАЖНО: Проверяем, что незавершенное задание sessionA НЕ потеряно после startNewSession!
        let preservedJob = await coordinator.jobs[activeJob.id]
        assert(preservedJob != nil, "Незавершенное задание обязано сохраниться в coordinator.jobs после startNewSession!")
        assert(preservedJob?.sessionID == sessionA.id, "Задание должно сохранить корректный sessionID предыдущей сессии!")
        
        // 3. Проверяем, что удаление sessionA БЛОКИРУЕТСЯ, пока ее перенос не завершен
        do {
            try await coordinator.deleteSession(id: sessionA.id)
            assertionFailure("Удаление предыдущей сессии с незавершенными переносами должно блокироваться!")
        } catch {
            print("  ✓ Защита от удаления предыдущей сессии с активными заданиями успешно сработала: \(error.localizedDescription)")
        }
        
        // 4. Завершаем перенос в sessionA
        if let staging = activeJob.stagingURL {
            let data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00] + [UInt8](repeating: 0x77, count: 100))
            try data.write(to: staging)
            let asset = try await coordinator.finalizeTransfer(jobID: activeJob.id, actualSize: Int64(data.count), duration: 0.05)
            assert(asset.sessionID == sessionA.id, "Ассет должен быть сохранен для sessionA")
            assert(FileManager.default.fileExists(atPath: asset.fileURL.path), "Файл должен быть записан в папку sessionA")
        }
        
        // 5. Теперь, когда задание завершено, сессию sessionA можно безопасно удалить
        try await coordinator.deleteSession(id: sessionA.id)
        print("  ✓ После завершения переноса сессия успешно удалена, незавершенные задания сохранены")
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
        
        // Добавляем реальный ассет в сессию перед переименованием
        let source = CameraSource(id: "cam-1", model: "Nikon Z 8", transportType: .usb)
        let job = try await coordinator.createTransferJob(source: source, filename: "DSC_0001.NEF", expectedSize: 1024)
        if let staging = job.stagingURL {
            let data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00] + [UInt8](repeating: 0x55, count: 1016))
            try data.write(to: staging)
            _ = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: 1024, duration: 0.05)
        }
        
        let initialAssets = await coordinator.assets
        assert(initialAssets.count == 1, "Должен быть зарегистрирован 1 ассет")
        let oldAssetURL = initialAssets[0].fileURL
        assert(FileManager.default.fileExists(atPath: oldAssetURL.path), "Файл ассета должен существовать на диске")
        assert(oldAssetURL.path.contains("Fashion_Shoot"), "Путь ассета должен содержать старое имя сессии")
        
        // 2. Переименование сессии с существующими файлами
        let renamed = try await coordinator.renameSession(id: session.id, newName: "Fashion_Shoot_Day1")
        assert(renamed.name == "Fashion_Shoot_Day1", "Имя должно измениться")
        assert(renamed.folderURL.lastPathComponent == "Fashion_Shoot_Day1", "Директория на диске должна быть переименована")
        
        // Проверяем, что пути ассетов обновились на диске, в памяти и в SQLite каталоге!
        assert(!FileManager.default.fileExists(atPath: oldAssetURL.path), "Старый путь файла больше НЕ должен существовать на диске!")
        
        let assetsAfterRename = await coordinator.assets
        assert(assetsAfterRename.count == 1, "Ассет должен остаться в сессии")
        let newAssetURL = assetsAfterRename[0].fileURL
        assert(newAssetURL.path.contains("Fashion_Shoot_Day1"), "Путь ассета в координаторе должен указывать на новое имя сессии!")
        assert(FileManager.default.fileExists(atPath: newAssetURL.path), "Файл по новому пути ДОЛЖЕН реально существовать на диске!")
        
        let dbAssets = await db.getAssets(for: session.id)
        assert(dbAssets[0].fileURL.path.contains("Fashion_Shoot_Day1"), "В SQLite базе данных путь ассета ДОЛЖЕН быть обновлен на новую папку!")
        assert(FileManager.default.fileExists(atPath: dbAssets[0].fileURL.path), "Файл из базы данных должен реально существовать!")
        
        let reconciler = DiskCatalogReconciler()
        let missing = reconciler.reconcileAssetsWithDisk(knownAssets: assetsAfterRename)
        assert(missing.isEmpty, "Ни один ассет не должен быть помечен как missing после переименования папки!")
        
        let groups = await coordinator.captureGroups
        assert(!groups.isEmpty, "CaptureGroups должны быть перестроены")
        assert(groups[0].primaryAsset?.fileURL.path.contains("Fashion_Shoot_Day1") == true, "Primary asset в группе должен иметь обновленный URL")
        
        // 3. Завершение сессии
        await coordinator.closeSession(id: session.id)
        let activeAfterClose = await coordinator.activeSession
        assert(activeAfterClose.isClosed == true, "Сессия должна быть помечена как завершенная")
        
        // 4. Проверка статистики
        let stats = await coordinator.getSessionStats(id: session.id)
        assert(stats.filesCount == 1, "Файлов должно быть 1")
        assert(stats.errorsCount == 0, "Ошибок 0")
        
        print("  ✓ Жизненный цикл сессии, переименование с путями ассетов и подсчет статистики проверены")
    }
    
    // MARK: - 10. Изоляция папок при одинаковых именах сессий и защита от случайного удаления
    func testDuplicateSessionNamesCreateIsolatedFoldersAndDeleteProtection() async throws {
        print("\n[10/10] Тест уникальности папок при дублировании имен сессий и защиты при удалении...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        // 1. Создаем две сессии с абсолютно одинаковым именем
        let session1 = try await coordinator.startNewSession(named: "Portraits")
        let session2 = try await coordinator.startNewSession(named: "Portraits")
        
        assert(session1.name == "Portraits", "Первая сессия должна называться Portraits, получено: \(session1.name)")
        assert(session2.name == "Portraits_1", "Вторая сессия должна получить суффикс Portraits_1, получено: \(session2.name)")
        assert(session1.folderURL != session2.folderURL, "Папки сессий на диске ДОЛЖНЫ быть разными!")
        assert(session1.folderURL.lastPathComponent == "Portraits", "Папка первой сессии должна быть Portraits")
        assert(session2.folderURL.lastPathComponent == "Portraits_1", "Папка второй сессии должна быть Portraits_1")
        assert(FileManager.default.fileExists(atPath: session1.folderURL.path), "Папка первой сессии должна существовать на диске")
        assert(FileManager.default.fileExists(atPath: session2.folderURL.path), "Папка второй сессии должна существовать на диске")
        
        // 2. Создаем файлы в обеих сессиях
        let file1URL = session1.folderURL.appendingPathComponent("shoot_1.jpg")
        let file2URL = session2.folderURL.appendingPathComponent("shoot_2.jpg")
        let dummyData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        try dummyData.write(to: file1URL)
        try dummyData.write(to: file2URL)
        
        assert(FileManager.default.fileExists(atPath: file1URL.path), "Файл 1 должен быть записан на диск")
        assert(FileManager.default.fileExists(atPath: file2URL.path), "Файл 2 должен быть записан на диск")
        
        // 3. Проверяем, что попытка переименовать session2 в имя session1 (Portraits) отклоняется
        do {
            _ = try await coordinator.renameSession(id: session2.id, newName: "Portraits")
            assertionFailure("Переименование в существующую сессию Portraits должно вызывать ошибку!")
        } catch {
            print("  ✓ Переименование сессии в имя уже существующей сессии успешно заблокировано")
        }
        
        // 4. Удаляем session1
        try await coordinator.deleteSession(id: session1.id)
        
        // 5. Проверяем, что папка session1 удалена, а папка session2 и ее файлы ЦЕЛЫ!
        assert(!FileManager.default.fileExists(atPath: session1.folderURL.path), "Папка session1 должна быть удалена")
        assert(FileManager.default.fileExists(atPath: session2.folderURL.path), "Папка session2 ОБЯЗАНА сохраниться на диске!")
        assert(FileManager.default.fileExists(atPath: file2URL.path), "Файл session2 ОБЯЗАН сохраниться на диске и не быть удаленным!")
        
        // 6. Проверка защитного механизма deleteSessionDirectory:
        // Если две сессии когда-либо ссылаются на одну и ту же папку внутри baseStorageURL,
        // удаление одной не должно удалять общую папку, а удаление последней должно удалить её.
        let sharedFolder = storage.baseStorageURL.appendingPathComponent("SharedDangerFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedFolder, withIntermediateDirectories: true)
        let dangerFile = sharedFolder.appendingPathComponent("important.nef")
        try dummyData.write(to: dangerFile)
        
        let sessionSharedA = CaptureSession(name: "SharedA", folderURL: sharedFolder)
        let sessionSharedB = CaptureSession(name: "SharedB", folderURL: sharedFolder)
        await storage.registerSession(sessionSharedA)
        await storage.registerSession(sessionSharedB)
        
        // Удаляем sessionSharedA — папка не должна быть удалена с диска, так как sessionSharedB ссылается на нее
        try await storage.deleteSessionDirectory(sessionID: sessionSharedA.id, activeJobCount: 0)
        assert(FileManager.default.fileExists(atPath: sharedFolder.path), "Общая папка НЕ должна быть удалена, пока существует другая сессия с тем же путем!")
        assert(FileManager.default.fileExists(atPath: dangerFile.path), "Файлы в общей папке НЕ должны быть повреждены!")
        
        // Удаляем последнюю оставшуюся сессию sessionSharedB — теперь папка может быть безопасно удалена
        try await storage.deleteSessionDirectory(sessionID: sessionSharedB.id, activeJobCount: 0)
        assert(!FileManager.default.fileExists(atPath: sharedFolder.path), "После удаления последней сессии папка должна быть удалена")
        
        // 7. Отдельный сценарий: папка за пределами baseStorageURL и ее содержимое защищены от удаления
        let outsideFolder = tempBaseURL.appendingPathComponent("OutsideDangerFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        let outsideFile = outsideFolder.appendingPathComponent("outside_important.nef")
        try dummyData.write(to: outsideFile)
        
        let sessionOutside = CaptureSession(name: "OutsideSession", folderURL: outsideFolder)
        await storage.registerSession(sessionOutside)
        
        // Удаляем сессию sessionOutside: защита границ хранилища не должна позволить удалить внешнюю папку и файлы
        try await storage.deleteSessionDirectory(sessionID: sessionOutside.id, activeJobCount: 0)
        assert(FileManager.default.fileExists(atPath: outsideFolder.path), "Папка вне baseStorageURL НЕ должна быть удалена защитным барьером путей!")
        assert(FileManager.default.fileExists(atPath: outsideFile.path), "Файлы в папке вне baseStorageURL НЕ должны быть повреждены!")
        
        print("  ✓ Изоляция папок при одинаковых названиях, защита общих папок и защита путей вне хранилища подтверждены")
    }
}
