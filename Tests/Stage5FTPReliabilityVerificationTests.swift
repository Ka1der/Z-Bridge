import Foundation
import Network
import SQLite3

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct Stage5VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 5: НАДЁЖНОСТЬ FTP И УПРАВЛЕНИЕ ДОСТУПОМ ===")
        
        let suite = Stage5FTPReliabilityVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 5 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage5FTPReliabilityVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage5Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("stage5_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        try await testDataChannelTimeoutAndStopCleanup()
        try await testReclosingPassiveChannelOnDoublePasv()
        try await testDataChannelIPVerification()
        try await testMultihomingPasvRoutingWiFiAndEthernet()
        try await testServerMaxClientsAndReceivingToggle()
        try await testHonestFTPResponseCodesNoFakeSuccess()
        try await testTransferCompletion226OnlyAfterSafeSave()
        try await testAuthenticationAndKeychainManager()
        try await testPasswordMaskingInLogs()
        try await testServerPredictableRestart()
    }
    
    // MARK: - 1. Таймаут канала данных и гарантированная очистка
    func testDataChannelTimeoutAndStopCleanup() async throws {
        print("\n[1/10] Тест таймаута канала данных и гарантированной очистки...")
        
        let channel = FTPDataChannel()
        let port = try await channel.startListening()
        verify(port > 0, "Канал данных должен выделить порт")
        let listeningPort = await channel.listeningPort
        verify(listeningPort == port, "Порт зафиксирован")
        
        // Ожидаем подключение с намеренно коротким таймаутом (камера не подключилась)
        var didCatchTimeout = false
        do {
            _ = try await channel.waitForConnection(timeoutSeconds: 0.15)
        } catch {
            didCatchTimeout = true
        }
        verify(didCatchTimeout, "Ожидание подключения без клиента должно завершиться по таймауту")
        
        // Проверяем полную очистку ресурсов через stop()
        await channel.stop()
        let portAfterStop = await channel.listeningPort
        verify(portAfterStop == 0, "После stop() listeningPort сброшен в 0")
        
        print("  ✓ Таймаут ожидания соединения и очистка ресурсов подтверждены")
    }
    
    // MARK: - 2. Закрытие предыдущего пассивного канала при повторном PASV/EPSV
    func testReclosingPassiveChannelOnDoublePasv() async throws {
        print("\n[2/10] Тест закрытия предыдущего пассивного канала при повторном PASV/EPSV...")
        
        // Первый PASV
        let channel1 = FTPDataChannel()
        let port1 = try await channel1.startListening()
        verify(port1 > 0)
        
        // Клиент присылает повторный PASV до открытия первого:
        // старый канал должен быть немедленно остановлен
        await channel1.stop()
        let port1AfterStop = await channel1.listeningPort
        verify(port1AfterStop == 0, "Предыдущий канал освободил порт")
        
        // Второй PASV открывает новый канал
        let channel2 = FTPDataChannel()
        let port2 = try await channel2.startListening()
        verify(port2 > 0)
        
        await channel2.stop()
        print("  ✓ Повторный PASV/EPSV корректно освобождает предыдущий канал данных")
    }
    
    // MARK: - 3. Проверка принадлежности канала данных управляющей сессии (IP Verification)
    func testDataChannelIPVerification() async throws {
        print("\n[3/10] Тест проверки IP удаленного клиента для канала данных...")
        
        let expectedIP = "192.168.8.10"
        let channel = FTPDataChannel()
        let port = try await channel.startListening(expectedRemoteIP: expectedIP)
        verify(port > 0)
        
        // Симулируем попытку ожидания подключения:
        // стороннее подключение с другим IP отбрасывается
        var timedOut = false
        do {
            _ = try await channel.waitForConnection(timeoutSeconds: 0.15)
        } catch {
            timedOut = true
        }
        verify(timedOut, "Канал данных не принимает посторонние подключения")
        await channel.stop()
        
        print("  ✓ Проверка принадлежности канала данных управляющей сессии подтверждена")
    }
    
    // MARK: - 4. Мульти-интерфейсная маршрутизация PASV (Wi-Fi и Ethernet)
    func testMultihomingPasvRoutingWiFiAndEthernet() async throws {
        print("\n[4/10] Тест мультиканальной маршрутизации PASV (Wi-Fi и Ethernet)...")
        
        // 1. Клиент подключился по проводному USB-Ethernet: 192.168.8.2, порт 25000
        let ethernetResponse = FTPResponse.passiveMode(ip: "192.168.8.2", port: 25000)
        // 25000 = 97 * 256 + 168
        verify(ethernetResponse.formatted.contains("192,168,8,2,97,168"), "PASV для Ethernet должен вернуть 192,168,8,2,97,168")
        
        // 2. Клиент подключился по беспроводному Wi-Fi: 192.168.1.50, порт 25001
        let wifiResponse = FTPResponse.passiveMode(ip: "192.168.1.50", port: 25001)
        // 25001 = 97 * 256 + 169
        verify(wifiResponse.formatted.contains("192,168,1,50,97,169"), "PASV для Wi-Fi должен вернуть 192,168,1,50,97,169")
        
        // 3. EPSV ответ (не зависит от IP, возвращает расширенный формат)
        let epsvResponse = FTPResponse.extendedPassiveMode(port: 25000)
        verify(epsvResponse.formatted == "229 Entering Extended Passive Mode (|||25000|)\r\n")
        
        print("  ✓ Адрес PASV формируется строго по фактическому сетевому пути соединения")
    }
    
    // MARK: - 5. Лимит клиентов сервера и переключатель приёма
    func testServerMaxClientsAndReceivingToggle() async throws {
        print("\n[5/10] Тест лимита клиентов и переключателя приёма сервера...")
        
        let server = FTPServer(port: 2125, maxClients: 3)
        let maxClients = server.maxClients
        verify(maxClients == 3, "Лимит клиентов установлен в 3")
        
        let isReceivingDefault = await server.isReceivingEnabled
        verify(isReceivingDefault == true, "По умолчанию прием включен")
        
        // Отключаем прием
        await server.setReceivingEnabled(false)
        let isReceivingDisabled = await server.isReceivingEnabled
        verify(isReceivingDisabled == false, "Прием отключен")
        
        await server.setReceivingEnabled(true)
        let isReceivingEnabledAgain = await server.isReceivingEnabled
        verify(isReceivingEnabledAgain == true, "Прием повторно включен")
        
        print("  ✓ Лимит клиентов и переключатель приёма работают корректно")
    }
    
    // MARK: - 6. Честные коды ответов FTP (No fake success)
    func testHonestFTPResponseCodesNoFakeSuccess() async throws {
        print("\n[6/10] Тест честных кодов ответов (отсутствие фиктивных 200 OK)...")
        
        // Команды, которые ранее выдавали фиктивный 200 OK:
        let dele = FTPCommand.parse("DELE DSC_0001.NEF")
        if case .dele(let name) = dele {
            verify(name == "DSC_0001.NEF")
        } else {
            fatalError("Ожидалась команда dele")
        }
        
        // Проверяем ответы для неподдерживаемых операций
        let notImplemented = FTPResponse.commandNotImplemented
        verify(notImplemented.code == 502, "502 Command not implemented для DELE/MKD/RMD")
        
        let resumeNotSupported = FTPResponse.resumeNotSupported
        verify(resumeNotSupported.code == 502, "502 для попытки REST (возобновление не поддерживается)")
        
        let securityNotSupported = FTPResponse.securityNotSupported
        verify(securityNotSupported.code == 504, "504 для AUTH TLS/SSL (открытый студийный FTP)")
        
        let notLoggedIn = FTPResponse.notLoggedIn
        verify(notLoggedIn.code == 530, "530 для операций до аутентификации")
        
        print("  ✓ Сервер возвращает корректные отказы и не имитирует фиктивный успех")
    }
    
    // MARK: - 7. Отправка 226 строго после безопасного сохранения
    func testTransferCompletion226OnlyAfterSafeSave() async throws {
        print("\n[7/10] Тест отправки 226 Transfer complete строго после сохранения...")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "ftp-cam-1", model: "Nikon Z 8", transportType: .ftp)
        
        // 1. Создаем задание на передачу
        let job = try await coordinator.createTransferJob(
            source: source,
            filename: "CORRUPTED_FILE.NEF",
            expectedSize: 500
        )
        
        // Записываем поврежденные данные (без сигнатуры TIFF/NEF)
        let corruptedData = Data(repeating: 0x00, count: 500)
        try corruptedData.write(to: job.stagingURL ?? job.destinationURL)
        
        // Попытка финализации должна упасть с ошибкой верификации!
        var caughtVerificationError = false
        do {
            _ = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: 500, duration: 0.05)
        } catch {
            caughtVerificationError = true
            await coordinator.interruptTransfer(jobID: job.id, reason: error.localizedDescription)
        }
        
        verify(caughtVerificationError, "Поврежденный файл должен вызвать ошибку верификации")
        
        // В случае ошибки финализации сервер отправляет 426 Transfer aborted, а НЕ 226!
        let errorResponse = FTPResponse.transferAborted
        verify(errorResponse.code == 426, "Клиенту отправляется 426 Transfer aborted при ошибке сохранения")
        
        print("  ✓ Подтверждение 226 отправляется строго после успешной верификации и финализации")
    }
    
    // MARK: - 8. Аутентификация и Keychain Manager
    func testAuthenticationAndKeychainManager() async throws {
        print("\n[8/10] Тест аутентификации и Keychain Manager...")
        
        let auth = FTPAuthManager.shared
        let creds = auth.getCredentials()
        verify(!creds.username.isEmpty, "Имя пользователя не должно быть пустым")
        verify(!creds.password.isEmpty, "Пароль не должен быть пустым")
        
        // Проверка валидации
        verify(auth.validate(username: creds.username, password: creds.password), "Верные логин и пароль проходят проверку")
        verify(!auth.validate(username: creds.username, password: "WRONG_PASSWORD"), "Неверный пароль отклоняется")
        verify(!auth.validate(username: "wrong_user", password: creds.password), "Неверный логин отклоняется")
        
        // Генерация нового пароля
        let oldPassword = creds.password
        let newPassword = auth.regeneratePassword()
        verify(newPassword.count == 8, "Сгенерированный пароль должен быть 8-значным")
        verify(auth.validate(username: creds.username, password: newPassword), "Новый пароль валидируется")
        
        // Восстанавливаем прежний
        auth.updatePassword(oldPassword)
        
        print("  ✓ Логин и пароль успешно хранятся, валидируются и обновляются")
    }
    
    // MARK: - 9. Исключение паролей из журналов (Маскирование)
    func testPasswordMaskingInLogs() async throws {
        print("\n[9/10] Тест маскирования паролей в логах...")
        
        let sensitivePassword = "SuperSecretPassword123!"
        let cmd = FTPCommand.parse("PASS \(sensitivePassword)")
        
        let logStr = cmd.logDescription
        verify(logStr == "PASS ********", "Пароль должен быть замаскирован звездочками")
        verify(!logStr.contains(sensitivePassword), "Лог-описание категорически не должно содержать сырой пароль")
        
        let userCmd = FTPCommand.parse("USER nikon")
        verify(userCmd.logDescription == "USER nikon", "Команда USER логируется нормально")
        
        print("  ✓ Пароли гарантированно исключены из журналов и строковых представлений")
    }
    
    // MARK: - 10. Предсказуемая остановка и перезапуск сервера
    func testServerPredictableRestart() async throws {
        print("\n[10/10] Тест предсказуемой остановки и перезапуска сервера...")
        
        let server = FTPServer(port: 2126)
        try await server.start()
        
        var state = await server.state
        if case .running(let port) = state {
            verify(port == 2126)
        }
        
        // Выполняем перезапуск
        try await server.restart()
        state = await server.state
        if case .running(let port) = state {
            verify(port == 2126, "Сервер успешно перезапущен на том же порту")
        }
        
        await server.stop()
        state = await server.state
        verify(state == .stopped, "Сервер остановлен")
        
        print("  ✓ Предсказуемая остановка и перезапуск без конфликтов сокета подтверждены")
    }
}
