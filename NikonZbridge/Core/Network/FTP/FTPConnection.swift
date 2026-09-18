import Foundation
import Network

/// Обработчик сессии одной подключенной камеры Nikon
public actor FTPConnection {
    private let connection: NWConnection
    private let storageManager: StorageManager
    private let coordinator: TransferCoordinator
    private let localIPAddress: String
    private let queue = DispatchQueue(label: "nikon.zbridge.ftp.session", qos: .userInitiated)
    private let authManager: FTPAuthManager
    
    private var dataChannel: FTPDataChannel?
    private var currentDirectory: String = "/"
    private var inputBuffer = Data()
    
    private var isAuthenticated = false
    private var attemptedUsername: String?
    private var lastActivityDate = Date()
    private var idleTask: Task<Void, Never>?
    
    public let id = UUID()
    public let cameraSource: CameraSource
    public let onFileReceived: (@Sendable (IngestedFile) -> Void)?
    public let onTransferProgress: (@Sendable (Int64, Double) -> Void)?
    public let onDisconnect: (@Sendable () -> Void)?
    
    public init(
        connection: NWConnection,
        storageManager: StorageManager = .shared,
        coordinator: TransferCoordinator = .shared,
        localIPAddress: String,
        authManager: FTPAuthManager = .shared,
        onFileReceived: (@Sendable (IngestedFile) -> Void)? = nil,
        onTransferProgress: (@Sendable (Int64, Double) -> Void)? = nil,
        onDisconnect: (@Sendable () -> Void)? = nil
    ) {
        self.connection = connection
        self.storageManager = storageManager
        self.coordinator = coordinator
        self.localIPAddress = localIPAddress
        self.authManager = authManager
        self.onFileReceived = onFileReceived
        self.onTransferProgress = onTransferProgress
        self.onDisconnect = onDisconnect
        self.cameraSource = CameraSource(
            id: "ftp-\(UUID().uuidString.prefix(8))",
            model: "Nikon Z",
            transportType: .ftp
        )
    }
    
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Task {
                    await self.send(FTPResponse.banner)
                    await self.startIdleMonitor()
                    await self.readLoop()
                }
            case .failed, .cancelled:
                Task {
                    await self.cleanup()
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
    
    private func startIdleMonitor() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // каждые 10 секунд
                guard let self = self else { break }
                let timedOut = await self.checkIdleTimeout()
                if timedOut {
                    break
                }
            }
        }
    }
    
    private func checkIdleTimeout() async -> Bool {
        // Лимит времени простоя: 120 секунд
        if Date().timeIntervalSince(lastActivityDate) > 120.0 {
            await send(FTPResponse.idleTimeout)
            await cleanup()
            return true
        }
        return false
    }
    
    /// Чтение командных строк из сокета
    private func readLoop() async {
        while true {
            do {
                let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    self.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if isComplete && (data == nil || data!.isEmpty) {
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(returning: data)
                        }
                    }
                }
                
                guard let data = chunk, !data.isEmpty else {
                    // Клиент разорвал соединение
                    await cleanup()
                    break
                }
                
                lastActivityDate = Date()
                inputBuffer.append(data)
                
                // Ограничение максимального размера входного буфера команд (1024 байта)
                if inputBuffer.count > 1024 {
                    let crlf = "\r\n".data(using: .utf8)!
                    let lf = "\n".data(using: .utf8)!
                    if inputBuffer.range(of: crlf) == nil && inputBuffer.range(of: lf) == nil {
                        inputBuffer.removeAll()
                        await send(FTPResponse.lineTooLong)
                        continue
                    }
                }
                
                await processBufferedLines()
            } catch {
                await cleanup()
                break
            }
        }
    }
    
    /// Извлечение и исполнение строк команд
    private func processBufferedLines() async {
        let crlf = "\r\n".data(using: .utf8)!
        let lf = "\n".data(using: .utf8)!
        
        while true {
            let delimiterRange: Range<Data.Index>?
            let delimiterLength: Int
            
            if let range = inputBuffer.range(of: crlf) {
                delimiterRange = range
                delimiterLength = crlf.count
            } else if let range = inputBuffer.range(of: lf) {
                delimiterRange = range
                delimiterLength = lf.count
            } else {
                break
            }
            
            guard let range = delimiterRange else { break }
            let lineData = inputBuffer.subdata(in: 0..<range.lowerBound)
            inputBuffer.removeSubrange(0..<(range.lowerBound + delimiterLength))
            
            if lineData.count > 1024 {
                await send(FTPResponse.lineTooLong)
                continue
            }
            
            if let lineStr = String(data: lineData, encoding: .utf8) ?? String(data: lineData, encoding: .ascii) {
                let command = FTPCommand.parse(lineStr)
                await execute(command: command)
            }
        }
    }
    
    /// Выполнение команды FTP протокола с проверкой прав доступа и защитой от фиктивных статусов
    private func execute(command: FTPCommand) async {
        lastActivityDate = Date()
        
        switch command {
        case .user(let user):
            attemptedUsername = user
            await send(FTPResponse.userOkNeedPass)
            
        case .pass(let pass):
            let username = attemptedUsername ?? ""
            if authManager.validate(username: username, password: pass) {
                isAuthenticated = true
                await send(FTPResponse.loginOk)
            } else {
                isAuthenticated = false
                await send(FTPResponse.loginFailed)
            }
            
        case .syst:
            await send(FTPResponse.systemType)
            
        case .feat:
            // Честное объявление строго поддерживаемых возможностей (без шифрования и докачки)
            let featResponse = "211-Features:\r\n EPSV\r\n PASV\r\n UTF8\r\n211 End\r\n"
            await sendRaw(featResponse)
            
        case .noop:
            await send(FTPResponse.commandOk)
            
        case .quit:
            await send(FTPResponse.bye)
            await cleanup()
            
        case .auth:
            // Не заявляем шифрование обычного FTP: открытый TCP-инжест
            await send(FTPResponse.securityNotSupported)
            
        case .rest:
            // Безопасная повторная отправка целого файла: возобновление с позиции не поддерживается
            await send(FTPResponse.resumeNotSupported)
            
        // Все остальные команды требуют предварительной аутентификации:
        case .pwd:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await send(FTPResponse.currentDirectory(currentDirectory))
            
        case .cwd(let dir):
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            currentDirectory = dir.isEmpty ? "/" : dir
            await send(FTPResponse.commandOk)
            
        case .cdup:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            currentDirectory = "/"
            await send(FTPResponse.commandOk)
            
        case .type:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await send(FTPResponse.binaryMode)
            
        case .pasv:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await handlePasv()
            
        case .epsv:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await handleEpsv()
            
        case .stor(let filename):
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await handleStor(filename: filename)
            
        case .size(let filename):
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            // Не возвращаем фиктивный успех: проверяем реальное наличие файла
            let active = await coordinator.activeSession
            let targetURL = active.folderURL.appendingPathComponent(filename)
            if let attr = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
               let size = attr[.size] as? Int64 {
                await send(FTPResponse(code: 213, message: "\(size)"))
            } else {
                await send(FTPResponse.fileUnavailable)
            }
            
        case .mdtm(let filename):
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            let active = await coordinator.activeSession
            let targetURL = active.folderURL.appendingPathComponent(filename)
            if let attr = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
               let date = attr[.modificationDate] as? Date {
                let df = DateFormatter()
                df.dateFormat = "yyyyMMddHHmmss"
                df.timeZone = TimeZone(secondsFromGMT: 0)
                await send(FTPResponse(code: 213, message: df.string(from: date)))
            } else {
                await send(FTPResponse.fileUnavailable)
            }
            
        case .dele, .mkd, .rmd:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            // Честный отказ: не выдавать фиктивный успех для нереализованных действий
            await send(FTPResponse.commandNotImplemented)
            
        case .port, .eprt:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await send(FTPResponse(code: 502, message: "Active mode disabled, please use PASV/EPSV"))
            
        case .retr:
            guard isAuthenticated else { await send(FTPResponse.notLoggedIn); return }
            await send(FTPResponse.fileUnavailable)
            
        case .unknown:
            await send(FTPResponse.commandNotImplemented)
        }
    }
    
    private func extractRemoteClientIP() -> String? {
        if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint {
            switch host {
            case .ipv4(let addr): return "\(addr)"
            case .ipv6(let addr): return "\(addr)"
            default: break
            }
        }
        if case let .hostPort(host, _) = connection.endpoint {
            switch host {
            case .ipv4(let addr): return "\(addr)"
            case .ipv6(let addr): return "\(addr)"
            default: break
            }
        }
        return nil
    }
    
    private func handlePasv() async {
        // 1. Закрываем предыдущий пассивный канал при повторном PASV/EPSV
        if let existing = self.dataChannel {
            await existing.stop()
            self.dataChannel = nil
        }
        
        do {
            let clientIP = extractRemoteClientIP()
            let channel = FTPDataChannel()
            let port = try await channel.startListening(expectedRemoteIP: clientIP)
            self.dataChannel = channel
            
            // 2. Выбираем адрес PASV по фактическому сетевому пути соединения (Wi-Fi / Ethernet)
            var ip = localIPAddress
            if case let .hostPort(host, _) = connection.currentPath?.localEndpoint {
                switch host {
                case .ipv4(let addr):
                    ip = "\(addr)"
                default:
                    break
                }
            }
            if ip.isEmpty || ip == "0.0.0.0" {
                ip = "127.0.0.1"
            }
            
            await send(FTPResponse.passiveMode(ip: ip, port: port))
        } catch {
            await send(FTPResponse.cannotOpenData)
        }
    }
    
    private func handleEpsv() async {
        // 1. Закрываем предыдущий пассивный канал при повторном PASV/EPSV
        if let existing = self.dataChannel {
            await existing.stop()
            self.dataChannel = nil
        }
        
        do {
            let clientIP = extractRemoteClientIP()
            let channel = FTPDataChannel()
            let port = try await channel.startListening(expectedRemoteIP: clientIP)
            self.dataChannel = channel
            await send(FTPResponse.extendedPassiveMode(port: port))
        } catch {
            await send(FTPResponse.cannotOpenData)
        }
    }
    
    private func handleStor(filename: String) async {
        guard let channel = self.dataChannel else {
            await send(FTPResponse.cannotOpenData)
            return
        }
        
        // Создаем задание переноса в координаторе с безопасным staging-путем и контролем места
        let job: TransferJob
        do {
            job = try await coordinator.createTransferJob(
                source: cameraSource,
                filename: filename,
                expectedSize: nil
            )
        } catch {
            await send(FTPResponse.cannotOpenData)
            return
        }
        
        await send(FTPResponse.fileOkBeginData)
        
        let writeTargetURL = job.stagingURL ?? job.destinationURL
        
        do {
            let progressCallback = self.onTransferProgress
            let coord = self.coordinator
            let jobID = job.id
            
            let result = try await channel.receiveFile(
                to: writeTargetURL,
                expectedBytes: job.totalBytes
            ) { bytes, speed in
                progressCallback?(bytes, speed)
                Task {
                    await coord.updateJobProgress(
                        jobID: jobID,
                        transferredBytes: bytes,
                        totalBytes: nil,
                        speedMBs: speed
                    )
                }
            }
            
            // 8. Отправлять успешное завершение передачи (226) ТОЛЬКО после безопасного сохранения
            let asset = try await coordinator.finalizeTransfer(
                jobID: jobID,
                actualSize: result.bytesReceived,
                duration: result.duration
            )
            
            onFileReceived?(IngestedFile(from: asset))
            await send(FTPResponse.transferComplete)
        } catch {
            await coordinator.interruptTransfer(jobID: job.id, reason: error.localizedDescription)
            await send(FTPResponse.transferAborted)
        }
        
        self.dataChannel = nil
    }
    
    private func send(_ response: FTPResponse) async {
        await sendRaw(response.formatted)
    }
    
    private func sendRaw(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed({ _ in
                continuation.resume()
            }))
        }
    }
    
    public func cleanup() async {
        idleTask?.cancel()
        idleTask = nil
        
        if let dc = dataChannel {
            await dc.stop()
            dataChannel = nil
        }
        connection.cancel()
        onDisconnect?()
    }
}
