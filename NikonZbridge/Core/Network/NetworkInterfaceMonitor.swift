import Foundation
import Network

/// Тип подключения для связи с камерой Nikon Z
public enum NetworkConnectionType: String, Sendable {
    case usbCable = "USB-кабель"
    case wifi = "Wi-Fi"
}

/// Информация о сетевом адресе для подключения камеры
public struct NetworkAddressInfo: Identifiable, Sendable, Hashable {
    public var id: String { "\(interfaceName)_\(ipAddress)" }
    public let interfaceName: String
    public let ipAddress: String
    public let type: NetworkConnectionType
    
    public init(interfaceName: String, ipAddress: String, type: NetworkConnectionType) {
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.type = type
    }
}

/// Монитор сетевых интерфейсов, фильтрующий только полезные для камеры каналы (Wi-Fi и провод USB-LAN)
public final class NetworkInterfaceMonitor: @unchecked Sendable {
    public static let shared = NetworkInterfaceMonitor()
    
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "nikon.zbridge.network.monitor", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    
    public var onInterfacesChanged: (([NetworkAddressInfo]) -> Void)?
    
    public init() {
        start()
    }
    
    public func start() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self = self else { return }
            self.debounceUpdate()
        }
        pathMonitor.start(queue: queue)
    }
    
    public func stop() {
        pathMonitor.cancel()
    }
    
    private func debounceUpdate() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let addresses = self.fetchCurrentAddresses()
            self.onInterfacesChanged?(addresses)
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    
    /// Получение только релевантных IP для камеры (USB или Wi-Fi)
    public func fetchCurrentAddresses() -> [NetworkAddressInfo] {
        var addresses: [NetworkAddressInfo] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            
            // Игнорируем выключенные интерфейсы и loopback
            if (flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING) { continue }
            if (flags & IFF_LOOPBACK) != 0 { continue }
            
            guard let namePtr = ptr.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)
            
            // СТРОГАЯ ФИЛЬТРАЦИЯ: только Wi-Fi (en0) или сетевые адаптеры USB-LAN (en1, en2...)
            // Полностью игнорируем сотовые (pdp_ip), VPN (utun, ipsec), AirDrop (awdl)
            guard let connectionType = classifyCameraInterface(name: name) else {
                continue
            }
            
            guard let addrPtr = ptr.pointee.ifa_addr else { continue }
            let addr = addrPtr.pointee
            
            // Только IPv4
            if addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let saLen = addr.sa_len > 0 ? socklen_t(addr.sa_len) : socklen_t(MemoryLayout<sockaddr_in>.size)
                
                if getnameinfo(
                    addrPtr,
                    saLen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: hostname)
                    // Исключаем системные link-local мусорные адреса если они не USB
                    addresses.append(NetworkAddressInfo(interfaceName: name, ipAddress: ip, type: connectionType))
                }
            }
        }
        
        // Приоритет: Кабель USB-LAN всегда первый, затем Wi-Fi
        return addresses.sorted { lhs, _ in
            lhs.type == .usbCable
        }
    }
    
    private func classifyCameraInterface(name: String) -> NetworkConnectionType? {
        if name == "en0" {
            return .wifi
        }
        // Внешние Ethernet-адаптеры (USB-C кабель к камере Nikon)
        if name.hasPrefix("en") {
            return .usbCable
        }
        // Все остальные интерфейсы игнорируются
        return nil
    }
}
