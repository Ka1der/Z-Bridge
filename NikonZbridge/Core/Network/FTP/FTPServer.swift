import Foundation
import Network

/// Статус работы сервера Ingest
public enum FTPServerState: Sendable, Equatable {
    case stopped
    case starting
    case running(port: UInt16)
    case failed(String)
}

/// Высокопроизводительный сервер для приема фотографий с камер Nikon Z
public actor FTPServer {
    public static let defaultPort: UInt16 = 2121
    public static let defaultMaxClients: Int = 5
    
    public private(set) var state: FTPServerState = .stopped
    public private(set) var activeClientCount: Int = 0
    public private(set) var isReceivingEnabled: Bool = true
    public let maxClients: Int
    
    private let port: UInt16
    private let storageManager: StorageManager
    private let coordinator: TransferCoordinator
    private var listener: NWListener?
    private var activeConnections: [UUID: FTPConnection] = [:]
    private let queue = DispatchQueue(label: "nikon.zbridge.ftp.server", qos: .userInitiated)
    
    // Callbacks для UI
    public var onFileReceived: (@Sendable (IngestedFile) -> Void)?
    public var onTransferProgress: (@Sendable (Int64, Double) -> Void)?
    public var onClientConnectionChanged: (@Sendable (Int) -> Void)?
    public var onStateChanged: (@Sendable (FTPServerState) -> Void)?
    
    public init(
        port: UInt16 = defaultPort,
        maxClients: Int = defaultMaxClients,
        storageManager: StorageManager = StorageManager.shared,
        coordinator: TransferCoordinator = TransferCoordinator.shared
    ) {
        self.port = port
        self.maxClients = maxClients
        self.storageManager = storageManager
        self.coordinator = coordinator
    }
    
    public func setReceivingEnabled(_ enabled: Bool) {
        self.isReceivingEnabled = enabled
    }
    
    public func setCallbacks(
        onFileReceived: (@Sendable (IngestedFile) -> Void)? = nil,
        onTransferProgress: (@Sendable (Int64, Double) -> Void)? = nil,
        onClientConnectionChanged: (@Sendable (Int) -> Void)? = nil,
        onStateChanged: (@Sendable (FTPServerState) -> Void)? = nil
    ) {
        if let cb = onFileReceived { self.onFileReceived = cb }
        if let cb = onTransferProgress { self.onTransferProgress = cb }
        if let cb = onClientConnectionChanged { self.onClientConnectionChanged = cb }
        if let cb = onStateChanged { self.onStateChanged = cb }
    }
    
    /// Запуск сервера
    public func start() throws {
        guard state == .stopped else { return }
        self.state = .starting
        onStateChanged?(.starting)
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true
        
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            let err = "Invalid port \(port)"
            self.state = .failed(err)
            onStateChanged?(.failed(err))
            throw NSError(domain: "FTPServer", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
        let nwListener = try NWListener(using: params, on: nwPort)
        self.listener = nwListener
        
        nwListener.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            Task {
                await self.handleListenerState(newState)
            }
        }
        
        nwListener.newConnectionHandler = { [weak self] newConn in
            guard let self = self else { return }
            Task {
                await self.handleNewConnection(newConn)
            }
        }
        
        nwListener.start(queue: queue)
    }
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            self.state = .running(port: port)
            onStateChanged?(.running(port: port))
        case .failed(let error):
            let desc = error.localizedDescription
            self.state = .failed(desc)
            onStateChanged?(.failed(desc))
        case .cancelled:
            self.state = .stopped
            onStateChanged?(.stopped)
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        // 1. Проверка явного переключателя приема
        guard isReceivingEnabled else {
            let reject = FTPResponse(code: 421, message: "FTP receiving is disabled in application settings").formatted
            if let data = reject.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                connection.cancel()
            }
            return
        }
        
        // 2. Ограничение максимального числа клиентов
        guard activeConnections.count < maxClients else {
            let reject = FTPResponse.tooManyConnections.formatted
            if let data = reject.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                connection.cancel()
            }
            return
        }
        
        // 3. Определяем локальный IP устройства на текущем соединении
        var localIP = "127.0.0.1"
        if case let .hostPort(host, _) = connection.currentPath?.localEndpoint {
            switch host {
            case .ipv4(let addr):
                localIP = "\(addr)"
            default:
                break
            }
        }
        
        // Если через endpoint не определился, берем из монитора интерфейсов
        if localIP == "127.0.0.1" {
            let addrs = NetworkInterfaceMonitor.shared.fetchCurrentAddresses()
            if let first = addrs.first {
                localIP = first.ipAddress
            }
        }
        
        let connID = UUID()
        let fileReceivedCallback = self.onFileReceived
        let transferProgressCallback = self.onTransferProgress
        let coord = self.coordinator
        
        let ftpConn = FTPConnection(
            connection: connection,
            storageManager: storageManager,
            coordinator: coordinator,
            localIPAddress: localIP,
            onFileReceived: { file in
                fileReceivedCallback?(file)
            },
            onTransferProgress: { bytes, speed in
                transferProgressCallback?(bytes, speed)
            },
            onDisconnect: { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.removeConnection(id: connID)
                }
            }
        )
        
        activeConnections[connID] = ftpConn
        activeClientCount = activeConnections.count
        onClientConnectionChanged?(activeClientCount)
        
        Task {
            let source = ftpConn.cameraSource
            await coord.transport(FTPCameraTransportAdapter(server: self), didDiscoverSource: source)
            await ftpConn.start()
        }
    }
    
    private func removeConnection(id: UUID) {
        guard let conn = activeConnections.removeValue(forKey: id) else { return }
        activeClientCount = activeConnections.count
        onClientConnectionChanged?(activeClientCount)
        
        let coord = self.coordinator
        Task {
            let sourceID = conn.cameraSource.id
            await coord.transport(FTPCameraTransportAdapter(server: self), didDisconnectSource: sourceID)
        }
    }
    
    /// Остановка сервера с закрытием всех клиентских сессий и сбросом слушателя
    public func stop() async {
        for conn in activeConnections.values {
            await conn.cleanup()
        }
        activeConnections.removeAll()
        activeClientCount = 0
        onClientConnectionChanged?(0)
        
        listener?.cancel()
        listener = nil
        self.state = .stopped
        onStateChanged?(.stopped)
    }
    
    /// Предсказуемый перезапуск сервера после сбоя или смены конфигурации
    public func restart() async throws {
        await stop()
        try await Task.sleep(nanoseconds: 200_000_000) // пауза для полного освобождения сокета ОС
        try start()
    }
}

/// Адаптер FTPServer для протокола CameraTransport
public final class FTPCameraTransportAdapter: CameraTransport, @unchecked Sendable {
    public let transportType: CameraTransportType = .ftp
    public weak var delegate: CameraTransportDelegate?
    
    private let server: FTPServer
    
    public init(server: FTPServer) {
        self.server = server
    }
    
    public var isConnected: Bool {
        return true
    }
    
    public var connectedSource: CameraSource? {
        CameraSource(id: "ftp-server", model: "Nikon Z", transportType: .ftp)
    }
    
    public func start() async throws {
        try await server.start()
    }
    
    public func stop() async {
        await server.stop()
    }
}
