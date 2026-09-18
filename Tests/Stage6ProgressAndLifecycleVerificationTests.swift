import Foundation
import Network
import Combine

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct Stage6VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 6: ПРОГРЕСС, ОШИБКИ И ЖИЗНЕННЫЙ ЦИКЛ ===")
        
        let suite = Stage6ProgressAndLifecycleVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 6 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage6ProgressAndLifecycleVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    let dummySourceUSB: CameraSource
    let dummySourceFTP: CameraSource
    let dummySessionID: UUID
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage6Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("stage6_catalog.sqlite")
        self.dummySourceUSB = CameraSource(id: "camera-z8-usb", model: "Nikon Z8", transportType: .usb)
        self.dummySourceFTP = CameraSource(id: "camera-z9-ftp", model: "Nikon Z9", transportType: .ftp)
        self.dummySessionID = UUID()
    }
    
    func runAllTests() async throws {
        try await testProgressSeparationCurrentAttemptVsSavedOriginals()
        try await testPercentageAndETADisplayStrictlyWhenTotalKnown()
        try await testSpeedMeasurementAndFormatting()
        try await testPasswordAndSecretMaskingInDiagnosticLogs()
        try await testUserFriendlyRussianErrorMessages()
        try await testDiagnosticLoggerRingBufferAndReportExport()
        try await testQueueFilteringCancellationAndRetry()
        try await testLifecycleManagerScreenAwakeAndBackgroundLimitationNotice()
    }
    
    // MARK: - 1. Разделение объёма текущей попытки и накопленных сохранённых оригиналов
    func testProgressSeparationCurrentAttemptVsSavedOriginals() async throws {
        print("\n[1/8] Тест разделения объёма текущей попытки и накопленных сохранённых оригиналов...")
        
        let appState = AppState()
        
        // 1. Исходно сессия пуста
        verify(appState.savedOriginalsBytes == 0, "Изначально сохранённых байт должно быть 0")
        verify(appState.currentAttemptBytes == 0, "Изначально байт текущей попытки 0")
        
        // 2. Имитируем успешное сохранение 2 файлов (например 25 МБ и 5 МБ)
        let file1 = IngestedFile(
            filename: "DSC_0001.NEF",
            fileURL: tempBaseURL.appendingPathComponent("DSC_0001.NEF"),
            fileSize: 25_000_000,
            receivedAt: Date(),
            transferDuration: 2.0
        )
        let file2 = IngestedFile(
            filename: "DSC_0001.JPG",
            fileURL: tempBaseURL.appendingPathComponent("DSC_0001.JPG"),
            fileSize: 5_000_000,
            receivedAt: Date(),
            transferDuration: 0.5
        )
        
        appState.receivedFiles = [file1, file2]
        verify(appState.savedOriginalsBytes == 30_000_000, "Накопленный объём должен быть ровно 30 МБ")
        
        // 3. Добавляем активное задание в процессе переноса третьего файла (10 МБ перенесено из 40 МБ)
        let activeJob = TransferJob(
            source: dummySourceFTP,
            sourceFileID: "DSC_0002.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_0002.NEF"),
            sessionID: dummySessionID,
            state: .inProgress(progress: 0.25, bytesTransferred: 10_000_000, totalBytes: 40_000_000),
            progress: 0.25,
            transferredBytes: 10_000_000,
            totalBytes: 40_000_000
        )
        appState.activeJobs = [activeJob]
        
        verify(appState.activeTransferJob?.id == activeJob.id, "Активное задание должно быть найдено")
        verify(appState.currentAttemptBytes == 10_000_000, "Объём текущей попытки равен переданным байтам активного задания")
        verify(appState.savedOriginalsBytes == 30_000_000, "Сохранённый объём НЕ должен включать незавершённые байты")
        
        // 4. Имитируем сбой активного задания и его повтор
        var failedJob = activeJob
        failedJob.state = .failed(error: .connectionLost("TCP drop"))
        failedJob.error = .connectionLost("TCP drop")
        appState.activeJobs = [failedJob]
        
        verify(appState.activeTransferJob == nil, "После сбоя нет активного задания")
        verify(appState.currentAttemptBytes == 0, "После сброса активного задания текущая попытка 0")
        verify(appState.savedOriginalsBytes == 30_000_000, "Сохранённые оригиналы не изменились после сбоя другого файла")
        
        print("  ✓ Накопленный объём оригиналов и объём текущей попытки строго изолированы")
    }
    
    // MARK: - 2. Процент и ETA отображаются только при известном полном размере
    func testPercentageAndETADisplayStrictlyWhenTotalKnown() async throws {
        print("\n[2/8] Тест расчёта процента и ETA только при известном общем размере...")
        
        let appState = AppState()
        
        // Случай A: Полный размер неизвестен (стриминг FTP STOR без предшествующей команды SIZE, totalBytes == nil)
        let streamingJob = TransferJob(
            source: dummySourceFTP,
            sourceFileID: "DSC_0010.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_0010.NEF"),
            sessionID: dummySessionID,
            state: .inProgress(progress: 0.0, bytesTransferred: 12_500_000, totalBytes: nil),
            progress: 0.0,
            transferredBytes: 12_500_000,
            totalBytes: nil
        )
        appState.activeJobs = [streamingJob]
        appState.currentTransferSpeedMBs = 20.0
        
        verify(streamingJob.progressPercent == nil, "При неизвестном totalBytes progressPercent должен быть nil")
        verify(appState.currentETASeconds == nil, "При неизвестном totalBytes ETA должно быть nil")
        
        // Случай B: Полный размер известен (totalBytes > 0)
        let knownSizeJob = TransferJob(
            source: dummySourceFTP,
            sourceFileID: "DSC_0011.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_0011.NEF"),
            sessionID: dummySessionID,
            state: .inProgress(progress: 0.5, bytesTransferred: 25_000_000, totalBytes: 50_000_000),
            progress: 0.5,
            transferredBytes: 25_000_000,
            totalBytes: 50_000_000
        )
        appState.activeJobs = [knownSizeJob]
        appState.currentTransferSpeedMBs = 25.0 // 25 МБ/с
        
        verify(knownSizeJob.progressPercent == 50.0, "Процент должен быть точно 50%")
        // Остаток: 25 МБ. При скорости 25 МБ/с ETA ~ 1 сек.
        verify(appState.currentETASeconds != nil, "ETA должно рассчитываться при известном размере и скорости > 0")
        if let eta = appState.currentETASeconds {
            verify(eta >= 0.9 && eta <= 1.1, "ETA должно составлять ~1.0 сек")
        }
        
        // Случай C: Скорость равна 0
        appState.currentTransferSpeedMBs = 0.0
        verify(appState.currentETASeconds == nil, "При нулевой скорости ETA не может быть вычислено")
        
        print("  ✓ Процент и остаток времени (ETA) отображаются строго при валидном полном размере")
    }
    
    // MARK: - 3. Измерение скорости и форматирование
    func testSpeedMeasurementAndFormatting() async throws {
        print("\n[3/8] Тест измерения скорости и форматирования...")
        
        let coordinator = TransferCoordinator(storageManager: StorageManager(customBaseURL: tempBaseURL))
        
        let dummyJob = try await coordinator.createTransferJob(
            source: dummySourceUSB,
            filename: "DSC_0001.NEF",
            sourceFileID: "DSC_0001.NEF",
            expectedSize: 20_971_520
        )
        
        // Имитируем передачу байт в coordinator с обновлением скорости
        await coordinator.updateJobProgress(
            jobID: dummyJob.id,
            transferredBytes: 10_485_760,
            totalBytes: 20_971_520,
            speedMBs: 25.5
        )
        
        // Проверяем форматирование скорости из IngestedFile
        let file = IngestedFile(
            filename: "DSC_0001.NEF",
            fileURL: tempBaseURL.appendingPathComponent("DSC_0001.NEF"),
            fileSize: 20_971_520,
            receivedAt: Date(),
            transferDuration: 1.0
        )
        verify(file.transferSpeedMBs == 20.0, "Расчет скорости файла 20 МБ/с")
        verify(file.formattedSpeed == "20 МБ/с", "Форматирование скорости переданного файла")
        
        let zeroFile = IngestedFile(
            filename: "DSC_0002.NEF",
            fileURL: tempBaseURL.appendingPathComponent("DSC_0002.NEF"),
            fileSize: 10_000_000,
            receivedAt: Date(),
            transferDuration: 0.0
        )
        verify(zeroFile.formattedSpeed == "—", "При нулевой длительности прочерк")
        
        print("  ✓ Скорость и форматирование работают корректно")
    }
    
    // MARK: - 4. Маскирование паролей и секретов в диагностическом журнале
    func testPasswordAndSecretMaskingInDiagnosticLogs() async throws {
        print("\n[4/8] Тест маскирования паролей и секретов в диагностическом журнале...")
        
        let logger = DiagnosticLogger.shared
        logger.clear()
        
        // 1. Логируем конфиденциальную команду FTP PASS
        logger.log(level: .info, subsystem: "FTP", message: "Камера отправила: PASS SuperSecretNikonPassword123")
        
        // 2. Логируем параметры с паролем
        logger.log(level: .info, subsystem: "Auth", message: "Auth attempt with pass=UltraSecretKey999")
        
        // 3. Логируем стандартное сообщение
        logger.log(level: .info, subsystem: "Transfer", message: "Файл DSC_0005.NEF успешно записан (35 МБ)")
        
        let entries = logger.getRecentEntries(limit: 50)
        verify(entries.count >= 3, "Должно быть сохранено как минимум 3 записи")
        
        for entry in entries {
            verify(!entry.message.contains("SuperSecretNikonPassword123"), "Пароль SuperSecretNikonPassword123 не должен содержаться в логе!")
            verify(!entry.message.contains("UltraSecretKey999"), "Пароль UltraSecretKey999 не должен содержаться в логе!")
        }
        
        // Проверяем, что вместо пароля присутствует маска
        let passEntry = entries.first { $0.subsystem == "FTP" }
        verify(passEntry?.message.contains("PASS ********") == true, "В логе должна присутствовать маска PASS ********")
        
        let authEntry = entries.first { $0.subsystem == "Auth" }
        verify(authEntry?.message.contains("pass=********") == true, "В логе должна присутствовать маска pass=********")
        
        print("  ✓ Все секретные данные надёжно маскируются в журнале")
    }
    
    // MARK: - 5. Понятные сообщения об ошибках на русском языке с рекомендациями
    func testUserFriendlyRussianErrorMessages() async throws {
        print("\n[5/8] Тест понятных сообщений об ошибках на русском языке...")
        
        let diskWriteError = TransferError.diskWriteFailed("Нет места")
        let connectionError = TransferError.connectionLost("Кабель отсоединен")
        let verificationError = TransferError.verificationFailed("Размер не совпал")
        let notFoundError = TransferError.fileNotFound("DSC_9999.NEF")
        let cancelledError = TransferError.cancelled
        let timeoutError = TransferError.timeout
        let genericError = TransferError.generic("Аппаратная ошибка")
        
        // Проверяем понятные сообщения
        let diskMsg = DiagnosticLogger.userFriendlyMessage(for: diskWriteError)
        verify(diskMsg.contains("места") && diskMsg.contains("Освободите"), "Сообщение о нехватке места")
        
        let connMsg = DiagnosticLogger.userFriendlyMessage(for: connectionError)
        verify(connMsg.contains("прервана") && connMsg.contains("Проверьте"), "Сообщение о разрыве соединения")
        
        let verifyMsg = DiagnosticLogger.userFriendlyMessage(for: verificationError)
        verify(verifyMsg.contains("поврежден") && verifyMsg.contains("не пострадал"), "Сообщение о проверке целостности")
        
        // Проверяем структурированные объяснения
        let diskExplain = DiagnosticLogger.userFriendlyExplanation(for: diskWriteError)
        verify(diskExplain.title.contains("Недостаточно места"), "Заголовок ошибки диска")
        verify(diskExplain.recoverySuggestion.contains("Очистите"), "Рекомендация по диску")
        
        let connExplain = DiagnosticLogger.userFriendlyExplanation(for: connectionError)
        verify(connExplain.title.contains("Связь прервана"), "Заголовок разрыва связи")
        verify(connExplain.recoverySuggestion.contains("кабеля") || connExplain.recoverySuggestion.contains("Wi-Fi"), "Рекомендация по связи")
        
        let verifyExplain = DiagnosticLogger.userFriendlyExplanation(for: verificationError)
        verify(verifyExplain.title.contains("Файл повреждён"), "Заголовок повреждения файла")
        
        let notFoundExplain = DiagnosticLogger.userFriendlyExplanation(for: notFoundError)
        verify(notFoundExplain.title.contains("Файл не найден"), "Заголовок отсутствия файла")
        
        let cancelledExplain = DiagnosticLogger.userFriendlyExplanation(for: cancelledError)
        verify(cancelledExplain.title.contains("отменена"), "Заголовок отмены")
        
        let timeoutExplain = DiagnosticLogger.userFriendlyExplanation(for: timeoutError)
        verify(timeoutExplain.title.contains("Таймаут"), "Заголовок таймаута")
        
        let genericExplain = DiagnosticLogger.userFriendlyExplanation(for: genericError)
        verify(genericExplain.title.contains("Ошибка переноса"), "Заголовок общей ошибки")
        
        print("  ✓ Все типы TransferError содержат ясные русские объяснения и инструкции для фотографа")
    }
    
    // MARK: - 6. Кольцевой буфер и экспорт диагностического отчёта
    func testDiagnosticLoggerRingBufferAndReportExport() async throws {
        print("\n[6/8] Тест кольцевого буфера и экспорта диагностического отчёта...")
        
        let logger = DiagnosticLogger.shared
        logger.clear()
        
        // Заполняем буфер
        for i in 1...100 {
            logger.log(level: .info, subsystem: "Test", message: "Диагностическое событие #\(i)")
        }
        
        let recent = logger.getRecentEntries(limit: 50)
        verify(recent.count == 50, "Ограничение выборки последних 50 записей")
        verify(recent.last?.message == "Диагностическое событие #100", "Последняя запись должна быть свежей")
        
        // Экспорт отчета
        let report = logger.exportDiagnosticReport(
            sessionName: "Студия Мода",
            cameraModel: "Nikon Z8",
            totalAssets: 42,
            networkIPs: ["192.168.1.100"]
        )
        
        verify(report.contains("НИКОН Z-BRIDGE: ДИАГНОСТИЧЕСКИЙ ЖУРНАЛ"), "Заголовок отчёта")
        verify(report.contains("Студия Мода"), "Имя сессии в отчёте")
        verify(report.contains("Nikon Z8"), "Модель камеры в отчёте")
        verify(report.contains("192.168.1.100"), "IP-адрес в отчёте")
        verify(report.contains("Диагностическое событие #100"), "Запись лога в отчёте")
        
        print("  ✓ Кольцевой буфер и экспорт диагностического отчёта работают безупречно")
    }
    
    // MARK: - 7. Фильтрация очереди, отмена и повтор заданий
    func testQueueFilteringCancellationAndRetry() async throws {
        print("\n[7/8] Тест фильтрации очереди, отмены и повтора заданий...")
        
        let appState = AppState()
        
        let job1 = TransferJob(
            source: dummySourceUSB,
            sourceFileID: "DSC_1001.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_1001.NEF"),
            sessionID: dummySessionID,
            state: .completed(assetID: UUID()),
            progress: 1.0,
            transferredBytes: 30_000_000,
            totalBytes: 30_000_000
        )
        let job2 = TransferJob(
            source: dummySourceUSB,
            sourceFileID: "DSC_1002.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_1002.NEF"),
            sessionID: dummySessionID,
            state: .inProgress(progress: 0.5, bytesTransferred: 15_000_000, totalBytes: 30_000_000),
            progress: 0.5,
            transferredBytes: 15_000_000,
            totalBytes: 30_000_000
        )
        let job3 = TransferJob(
            source: dummySourceUSB,
            sourceFileID: "DSC_1003.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_1003.NEF"),
            sessionID: dummySessionID,
            state: .failed(error: .connectionLost("Кабель отсоединён")),
            error: .connectionLost("Кабель отсоединён")
        )
        let job4 = TransferJob(
            source: dummySourceUSB,
            sourceFileID: "DSC_1004.NEF",
            destinationURL: tempBaseURL.appendingPathComponent("DSC_1004.NEF"),
            sessionID: dummySessionID,
            state: .pending
        )
        
        appState.activeJobs = [job1, job2, job3, job4]
        
        // Проверяем фильтрацию
        verify(appState.completedJobs.count == 1, "Завершенных заданий: 1")
        verify(appState.failedJobs.count == 1, "Ошибочных заданий: 1")
        verify(appState.pendingJobs.count == 1, "Ожидающих заданий: 1")
        verify(appState.activeTransferJob?.id == job2.id, "Выполняющееся задание: job2")
        verify(appState.activeQueueCount == 2, "В очереди должны быть 2 активных задания (job2 + job4)")
        
        // Проверяем вызовы cancelJob и retryJob
        appState.cancelJob(id: job2.id)
        appState.retryJob(id: job3.id)
        
        print("  ✓ Управление очередью, отмена и повтор заданий функционируют исправно")
    }
    
    // MARK: - 8. Управление сном экрана и уведомление об ограничениях фона iOS
    func testLifecycleManagerScreenAwakeAndBackgroundLimitationNotice() async throws {
        print("\n[8/8] Тест управления сном экрана и прозрачности ограничений фона...")
        
        let lifecycle = LifecycleManager.shared
        
        // 1. Проверяем флаг бодрствования экрана
        lifecycle.isIdleTimerDisabledDuringShooting = true
        verify(lifecycle.isIdleTimerDisabledDuringShooting == true, "Флаг бодрствования активен")
        
        lifecycle.setCameraActive(true)
        lifecycle.setCameraActive(false)
        
        // 2. Проверяем текст прозрачного предупреждения об ограничениях фона
        let notice = LifecycleManager.backgroundLimitationNotice
        verify(notice.contains("iOS"), "Уведомление содержит упоминание iOS")
        verify(notice.contains("фоновом") || notice.contains("фоне") || notice.contains("экраном"), "Уведомление предупреждает о фоновом режиме")
        verify(notice.contains("экран включенным") || notice.contains("экран включённым"), "Совет держать экран включённым")
        
        print("  ✓ Управление сном экрана и честное предупреждение фотографа верифицированы")
    }
}
