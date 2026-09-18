import Foundation

/// Набор проверок для валидации Этапа 1: Единая модель импорта
@main
struct Stage1VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 1: ЕДИНАЯ МОДЕЛЬ ИМПОРТА ===")
        
        let tests = Stage1VerificationSuite()
        try await tests.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 1 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

final class Stage1VerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage1Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("stage1_catalog.sqlite")
    }
    
    private func makeCoordinator() async -> TransferCoordinator {
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        return coordinator
    }
    
    func runAllTests() async throws {
        try await testModelPropertiesAndCapabilities()
        try await testSessionAndJobBindingImmutability()
        try await testTransferLifecycleAndVerificationSuccess()
        try await testCorruptedFileVerification()
        try await testCaptureGroupRAWandJPEGLinking()
        try await testUSBPullVsFTPPushBehavior()
        try await testExportJobLifecycle()
    }
    
    // MARK: - Тест 1: Проверка моделей и возможностей транспортов
    func testModelPropertiesAndCapabilities() async throws {
        print("\n[1/7] Тест моделей и возможностей транспортов...")
        
        let usbSource = CameraSource(id: "usb-1", model: "Nikon Z 8", transportType: .usb)
        assert(usbSource.transportType.canInitiateDownload == true, "USB должен поддерживать Pull")
        assert(usbSource.transportType.supportsAppRetry == true, "USB должен поддерживать повтор со стороны приложения")
        
        let ftpSource = CameraSource(id: "ftp-1", model: "Nikon Z 9", transportType: .ftp)
        assert(ftpSource.transportType.canInitiateDownload == false, "FTP не может инициировать скачивание со стороны приложения (только Push от камеры)")
        assert(ftpSource.transportType.supportsAppRetry == false, "FTP не может повторять запрос самостоятельно")
        
        print("  ✓ Модели CameraSource и CameraTransportType проверены")
    }
    
    // MARK: - Тест 2: Привязка пути и сессии к заданию (Иммутабельность при смене активной сессии)
    func testSessionAndJobBindingImmutability() async throws {
        print("\n[2/7] Тест иммутабельности привязки сессии и пути сохранения...")
        
        let coordinator = await makeCoordinator()
        
        let sessionA = await coordinator.activeSession
        let usbSource = CameraSource(id: "cam-1", model: "Nikon Z 8", transportType: .usb)
        
        // Создаем задание в Сессии A
        let job = try await coordinator.createTransferJob(source: usbSource, filename: "DSC_0001.NEF")
        assert(job.sessionID == sessionA.id, "Задание должно быть привязано к sessionID активной сессии A")
        assert(job.destinationURL.path.contains(sessionA.name), "Путь сохранения задания должен указывать на папку сессии A")
        
        // Переключаем активную сессию на новую Сессию B
        let sessionB = try await coordinator.startNewSession(named: "Session_B")
        let currentActive = await coordinator.activeSession
        assert(currentActive.id == sessionB.id, "Активной должна стать сессия B")
        
        // Проверяем, что созданное ранее задание НЕ изменило свое назначение и сессию после возврата к Session A!
        await coordinator.switchActiveSession(to: sessionA.id)
        let storedJob = await coordinator.jobs[job.id]
        assert(storedJob != nil, "Задание должно присутствовать в координаторе после возврата к Session A")
        assert(storedJob!.sessionID == sessionA.id, "Смена активной сессии не должна менять sessionID уже созданного задания!")
        assert(storedJob!.destinationURL.path.contains(sessionA.name), "Смена активной сессии не должна менять destinationURL уже созданного задания!")
        assert(!storedJob!.destinationURL.path.contains(sessionB.name), "Задание из сессии A ни в коем случае не должно сохраняться в папку сессии B")
        
        print("  ✓ Иммутабельность привязки задания к сессии и каталогу подтверждена")
    }
    
    // MARK: - Тест 3: Жизненный цикл переноса и успешная верификация
    func testTransferLifecycleAndVerificationSuccess() async throws {
        print("\n[3/7] Тест жизненного цикла переноса (pending -> inProgress -> verifying -> completed)...")
        
        let coordinator = await makeCoordinator()
        
        let source = CameraSource(id: "cam-test", model: "Nikon Z 6III", transportType: .usb)
        let job = try await coordinator.createTransferJob(source: source, filename: "TEST_001.NEF")
        assert(job.state == .pending, "Начальное состояние задания должно быть pending")
        
        // Симулируем прогресс передачи
        await coordinator.updateJobProgress(jobID: job.id, transferredBytes: 512, totalBytes: 1024, speedMBs: 150.0)
        let inProgressJob = await coordinator.jobs[job.id]
        if case .inProgress(let progress, let bytes, _) = inProgressJob!.state {
            assert(bytes == 512, "Переданные байты должны совпадать")
            assert(progress == 0.5, "Прогресс должен быть 0.5")
        } else {
            assertionFailure("Ожидалось состояние inProgress")
        }
        
        // Записываем валидный TIFF заголовок (0x49 0x49 0x2A 0x00)
        var validNEFData = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        validNEFData.append(Data(repeating: 0x01, count: 1016))
        let writeURL = job.stagingURL ?? job.destinationURL
        try validNEFData.write(to: writeURL)
        
        // Финализация переноса
        let asset = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: Int64(validNEFData.count), duration: 0.1)
        
        let completedJob = await coordinator.jobs[job.id]
        assert(completedJob!.state.isSuccess, "Задание должно перейти в состояние completed")
        assert(asset.format.isRAW, "Формат должен быть RAW")
        assert(asset.fileSize == 1024, "Размер должен быть 1024")
        assert(asset.verificationResult.isValid, "Результат проверки должен быть валидным")
        
        print("  ✓ Жизненный цикл переноса и верификация NEF успешно завершены")
    }
    
    // MARK: - Тест 4: Обнаружение поврежденного файла (верифкация)
    func testCorruptedFileVerification() async throws {
        print("\n[4/7] Тест обнаружения поврежденного файла при верификации...")
        
        let coordinator = await makeCoordinator()
        
        let source = CameraSource(id: "cam-corrupt", model: "Nikon Z f", transportType: .ftp)
        let job = try await coordinator.createTransferJob(source: source, filename: "CORRUPT.NEF")
        
        // Записываем битый файл (невалидный заголовок)
        let corruptedData = Data([0x00, 0x00, 0x00, 0x00, 0x11, 0x22])
        let writeURL = job.stagingURL ?? job.destinationURL
        try corruptedData.write(to: writeURL)
        
        do {
            _ = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: Int64(corruptedData.count), duration: 0.05)
            assertionFailure("Верификация поврежденного файла должна была завершиться ошибкой")
        } catch {
            let failedJob = await coordinator.jobs[job.id]
            if case .failed(let transferErr) = failedJob!.state {
                if case .verificationFailed = transferErr {
                    print("  ✓ Корректно зафиксирована ошибка верификации: \(transferErr.localizedDescription)")
                } else {
                    assertionFailure("Ожидалась ошибка verificationFailed, получено \(transferErr)")
                }
            } else {
                assertionFailure("Задание должно перейти в состояние failed")
            }
        }
    }
    
    // MARK: - Тест 5: Группировка кадров (связывание RAW + JPEG)
    func testCaptureGroupRAWandJPEGLinking() async throws {
        print("\n[5/7] Тест связывания RAW и JPEG в CaptureGroup одного кадра...")
        
        let coordinator = await makeCoordinator()
        
        let source = CameraSource(id: "cam-sync", model: "Nikon Z 8", transportType: .usb)
        
        // 1. Приходит RAW: DSC_1234.NEF
        let rawJob = try await coordinator.createTransferJob(source: source, filename: "DSC_1234.NEF")
        var rawData = Data([0x49, 0x49, 0x2A, 0x00])
        rawData.append(Data(repeating: 0xAA, count: 64))
        try rawData.write(to: rawJob.stagingURL ?? rawJob.destinationURL)
        _ = try await coordinator.finalizeTransfer(jobID: rawJob.id, actualSize: Int64(rawData.count), duration: 0.02)
        
        // 2. Приходит JPEG: DSC_1234.JPG
        let jpgJob = try await coordinator.createTransferJob(source: source, filename: "DSC_1234.JPG")
        var jpgData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        jpgData.append(Data(repeating: 0xBB, count: 64))
        try jpgData.write(to: jpgJob.stagingURL ?? jpgJob.destinationURL)
        _ = try await coordinator.finalizeTransfer(jobID: jpgJob.id, actualSize: Int64(jpgData.count), duration: 0.01)
        
        // Проверяем список групп в координаторе
        let groups = await coordinator.captureGroups
        let targetGroup = groups.first(where: { $0.baseName == "DSC_1234" })
        assert(targetGroup != nil, "Должна быть создана группа DSC_1234")
        assert(targetGroup!.hasBothRawAndJpeg, "Группа должна содержать и RAW, и JPEG кадры")
        assert(targetGroup!.rawAsset?.filename == "DSC_1234.NEF", "RAW ассет должен быть привязан")
        assert(targetGroup!.jpegAsset?.filename == "DSC_1234.JPG", "JPEG ассет должен быть привязан")
        assert(targetGroup!.primaryAsset?.format.isRAW == true, "Основным ассетом должен быть выбран RAW")
        
        print("  ✓ RAW и JPEG успешно связаны в единый CaptureGroup (DSC_1234)")
    }
    
    // MARK: - Тест 6: Поведение USB (Pull + Retry) vs FTP (Push + Interrupted)
    func testUSBPullVsFTPPushBehavior() async throws {
        print("\n[6/7] Тест различий транспортов USB (Pull, Retry) и FTP (Push, No retry)...")
        
        let coordinator = await makeCoordinator()
        
        // 1. Проверяем USB retry
        let mockUSB = MockCameraTransport(type: .usb)
        await coordinator.registerTransport(mockUSB)
        
        let usbJob = try await coordinator.createTransferJob(source: mockUSB.connectedSource!, filename: "RETRY_ME.NEF")
        await coordinator.failTransfer(jobID: usbJob.id, error: .timeout)
        
        try await coordinator.retryTransfer(jobID: usbJob.id)
        assert(mockUSB.downloadRequestedCount == 1, "USB должен был запросить скачивание при retry")
        let retriedJob = await coordinator.jobs[usbJob.id]
        assert(retriedJob?.attempts == 1, "Число попыток должно увеличиться")
        
        // 2. Проверяем FTP retry
        let mockFTP = MockCameraTransport(type: .ftp)
        await coordinator.registerTransport(mockFTP)
        
        let ftpJob = try await coordinator.createTransferJob(source: mockFTP.connectedSource!, filename: "CAMERA_PUSH.NEF")
        await coordinator.interruptTransfer(jobID: ftpJob.id, reason: "Камера разорвала соединение")
        
        do {
            try await coordinator.retryTransfer(jobID: ftpJob.id)
            assertionFailure("FTP не должен разрешать retry со стороны приложения")
        } catch {
            print("  ✓ FTP корректно отклонил запрос на повтор со стороны приложения")
        }
        
        print("  ✓ Различия USB и FTP подтверждены")
    }
    
    // MARK: - Тест 7: Задание экспорта (ExportJob)
    func testExportJobLifecycle() async throws {
        print("\n[7/7] Тест создания и обновления ExportJob...")
        
        let coordinator = await makeCoordinator()
        
        let assetID = UUID()
        let exportJob = await coordinator.createExportJob(
            assetIDs: [assetID],
            destination: .directory(url: tempBaseURL)
        )
        assert(exportJob.state == .pending, "Начальный статус экспорта должен быть pending")
        
        var completedExport = exportJob
        completedExport.state = .completed(exportedURLs: [tempBaseURL.appendingPathComponent("export.jpg")])
        completedExport.result = ExportResult(totalCount: 1, successCount: 1, failedCount: 0)
        await coordinator.updateExportJob(completedExport)
        
        let stored = await coordinator.exportJobs[exportJob.id]
        assert(stored?.result?.isAllSuccessful == true, "Экспорт должен быть успешно зафиксирован")
        print("  ✓ Жизненный цикл ExportJob проверен")
    }
}

// MARK: - Mock Camera Transport
final class MockCameraTransport: CameraTransport, @unchecked Sendable {
    let transportType: CameraTransportType
    var isConnected: Bool = true
    var connectedSource: CameraSource?
    weak var delegate: CameraTransportDelegate?
    var downloadRequestedCount = 0
    
    init(type: CameraTransportType) {
        self.transportType = type
        self.connectedSource = CameraSource(id: "mock-\(type.rawValue)", model: "Mock Z", transportType: type)
    }
    
    func start() async throws {}
    func stop() async {}
    
    func requestDownload(fileID: String, into job: TransferJob) async throws {
        guard transportType.canInitiateDownload else {
            throw TransferError.generic("Pull не поддерживается")
        }
        downloadRequestedCount += 1
    }
}
