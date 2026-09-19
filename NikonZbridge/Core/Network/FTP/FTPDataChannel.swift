import Foundation
import Network

/// Результат завершения передачи данных
public struct DataTransferResult: Sendable {
    public let bytesReceived: Int64
    public let duration: TimeInterval
    public let averageSpeedMBs: Double
}

/// Потокобезопасная обертка для CheckedContinuation с защитой от повторного возобновления
private final class SafeContinuationBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var isResolved = false
    private var pendingResult: Result<T, Error>?
    
    func setContinuation(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if isResolved {
            if let result = pendingResult {
                pendingResult = nil
                lock.unlock()
                continuation.resume(with: result)
            } else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            }
            return
        }
        self.continuation = continuation
        lock.unlock()
    }
    
    func resume(returning value: T) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let cont = self.continuation
        self.continuation = nil
        if cont == nil {
            pendingResult = .success(value)
        }
        lock.unlock()
        
        cont?.resume(returning: value)
    }
    
    func resume(throwing error: Error) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let cont = self.continuation
        self.continuation = nil
        if cont == nil {
            pendingResult = .failure(error)
        }
        lock.unlock()
        
        cont?.resume(throwing: error)
    }
}

/// Управляет каналом передачи данных (Passive Mode / EPSV) с контролем свободного места и строгой изоляцией сетевых ошибок
public actor FTPDataChannel {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "nikon.zbridge.ftp.data", qos: .userInitiated)
    private let diskGuard: DiskSpaceGuard
    private var expectedRemoteIP: String?
    
    public private(set) var listeningPort: UInt16 = 0
    private var connectionBox: SafeContinuationBox<NWConnection>?
    
    public init(diskGuard: DiskSpaceGuard = DiskSpaceGuard()) {
        self.diskGuard = diskGuard
    }
    
    /// Запуск прослушивания случайного свободного порта (PASV / EPSV) с опциональной привязкой к IP управляющей сессии
    public func startListening(expectedRemoteIP: String? = nil) async throws -> UInt16 {
        self.expectedRemoteIP = expectedRemoteIP
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true
        
        let nwListener = try NWListener(using: params, on: .any)
        self.listener = nwListener
        
        nwListener.newConnectionHandler = { [weak self] newConn in
            guard let self = self else { return }
            Task {
                await self.handleIncomingDataConnection(newConn)
            }
        }
        
        let box = SafeContinuationBox<UInt16>()
        
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            box.setContinuation(continuation)
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let p = nwListener.port?.rawValue {
                        box.resume(returning: p)
                    }
                case .failed(let error):
                    box.resume(throwing: error)
                default:
                    break
                }
            }
            nwListener.start(queue: self.queue)
        }
        
        self.listeningPort = port
        return port
    }
    
    private func handleIncomingDataConnection(_ connection: NWConnection) {
        // Проверка соответствия входящего подключения удаленному IP управляющей сессии
        if let expected = self.expectedRemoteIP {
            var incomingIP = ""
            if case let .hostPort(host, _) = connection.endpoint {
                switch host {
                case .ipv4(let addr): incomingIP = "\(addr)"
                case .ipv6(let addr): incomingIP = "\(addr)"
                default: break
                }
            }
            if incomingIP != expected {
                connection.cancel()
                return
            }
        }
        
        self.activeConnection = connection
        connection.start(queue: queue)
        if let box = self.connectionBox {
            box.resume(returning: connection)
            self.connectionBox = nil
        }
    }
    
    /// Ожидание подключения камеры к каналу данных с таймаутом и гарантированной отменой
    public func waitForConnection(timeoutSeconds: Double = 15.0) async throws -> NWConnection {
        if let conn = activeConnection {
            return conn
        }
        
        let box = SafeContinuationBox<NWConnection>()
        self.connectionBox = box
        
        return try await withThrowingTaskGroup(of: NWConnection.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        box.setContinuation(continuation)
                    }
                } onCancel: {
                    box.resume(throwing: CancellationError())
                }
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw NSError(domain: "FTPDataChannel", code: 425, userInfo: [NSLocalizedDescriptionKey: "Data connection timeout"])
            }
            
            do {
                let result = try await group.next()!
                group.cancelAll()
                self.connectionBox = nil
                return result
            } catch {
                group.cancelAll()
                box.resume(throwing: CancellationError())
                self.connectionBox = nil
                throw error
            }
        }
    }
    
    /// Чтение порции данных с ограничением по времени простоя и гарантированной отменой сетевого ожидания
    internal func receiveChunkWithTimeout(from connection: NWConnection, timeoutSeconds: Double = 15.0) async throws -> (Data?, Bool) {
        let box = SafeContinuationBox<(Data?, Bool)>()
        
        return try await withThrowingTaskGroup(of: (Data?, Bool).self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        box.setContinuation(continuation)
                        if Task.isCancelled {
                            connection.cancel()
                            box.resume(throwing: CancellationError())
                            return
                        }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { data, _, isComplete, error in
                            if let error = error {
                                box.resume(throwing: error)
                            } else {
                                box.resume(returning: (data, isComplete))
                            }
                        }
                    }
                } onCancel: {
                    connection.cancel()
                    box.resume(throwing: CancellationError())
                }
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw TransferError.connectionLost("Таймаут передачи данных: нет ответа от камеры более \(Int(timeoutSeconds)) с")
            }
            
            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                connection.cancel()
                box.resume(throwing: CancellationError())
                throw error
            }
        }
    }
    
    /// Прием входящего файла и потоковая запись на диск (во временный staging-файл)
    public func receiveFile(
        to destinationURL: URL,
        expectedBytes: Int64? = nil,
        onProgress: (@Sendable (Int64, Double) -> Void)? = nil
    ) async throws -> DataTransferResult {
        // 1. Контроль свободного места перед началом записи
        try diskGuard.validateSpaceBeforeTransfer(at: destinationURL, expectedBytes: expectedBytes ?? 0)
        
        let connection = try await waitForConnection()
        
        // 2. Создаем временный файл
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: destinationURL) else {
            throw NSError(domain: "FTPDataChannel", code: 550, userInfo: [NSLocalizedDescriptionKey: "Failed to open destination file"])
        }
        
        let startTime = Date()
        var totalBytes: Int64 = 0
        var lastSpaceCheckBytes: Int64 = 0
        var isCompleted = false
        
        do {
            while !isCompleted {
                let (chunk, isDone) = try await receiveChunkWithTimeout(from: connection, timeoutSeconds: 15.0)
                
                if let data = chunk, !data.isEmpty {
                    try fileHandle.write(contentsOf: data)
                    totalBytes += Int64(data.count)
                    
                    // 3. Контроль свободного места во время переноса (каждые ~5 МБ)
                    if totalBytes - lastSpaceCheckBytes > 5 * 1024 * 1024 {
                        lastSpaceCheckBytes = totalBytes
                        guard diskGuard.hasEnoughSpace(at: destinationURL, requiredBytes: 0) else {
                            throw TransferError.diskWriteFailed("Заполнение диска: свободное место упало ниже критического резерва")
                        }
                    }
                    
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > 0 {
                        let currentSpeed = (Double(totalBytes) / 1_048_576.0) / elapsed
                        onProgress?(totalBytes, currentSpeed)
                    }
                }
                
                if isDone || chunk == nil || chunk!.isEmpty {
                    isCompleted = true
                }
            }
            
            try fileHandle.close()
            stop()
        } catch {
            try? fileHandle.close()
            // При ошибке передачи или сетевом обрыве — удаляем незавершенный временный файл
            try? FileManager.default.removeItem(at: destinationURL)
            stop()
            throw error
        }
        
        let duration = max(Date().timeIntervalSince(startTime), 0.001)
        let speed = (Double(totalBytes) / 1_048_576.0) / duration
        
        return DataTransferResult(
            bytesReceived: totalBytes,
            duration: duration,
            averageSpeedMBs: speed
        )
    }
    
    /// Остановка и освобождение порта
    public func stop() {
        connectionBox?.resume(throwing: CancellationError())
        connectionBox = nil
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        listeningPort = 0
    }
}
