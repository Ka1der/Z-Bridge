import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Менеджер клиентского монитора и внешнего экрана (HDMI / USB-C / AirPlay)
@MainActor
public final class ClientMonitorManager: ObservableObject {
    public static let shared = ClientMonitorManager()
    
    // MARK: - Публичные состояния
    
    @Published public var config: ClientMonitorConfig {
        didSet {
            saveConfig()
        }
    }
    
    /// Кадр, отображаемый на клиентском мониторе в данный момент
    @Published public var displayedGroup: CaptureGroup?
    
    /// Зафиксированный (удерживаемый) кадр при активном режиме Hold
    @Published public var heldGroup: CaptureGroup?
    
    /// Статус подключения внешнего физического монитора или AirPlay
    @Published public var externalDisplayStatus: ExternalDisplayStatus = .disconnected
    
    /// Флаг активности внешнего окна
    @Published public var isExternalWindowActive: Bool = false
    
    // MARK: - Внутренние свойства
    
    private var pendingSwitchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    #if canImport(UIKit)
    private var externalWindow: UIWindow?
    #endif
    
    // MARK: - Инициализация
    
    public init(config: ClientMonitorConfig = ClientMonitorConfig()) {
        self.config = config
        setupExternalDisplayMonitoring()
    }
    
    // MARK: - Логика обработки входящих и обновляемых кадров
    
    /// Обработка нового кадра, поступившего с камеры
    public func handleIncomingGroup(_ group: CaptureGroup) {
        // 1. Если включено удержание — экран клиента остаётся на зафиксированном кадре
        guard !config.isHoldEnabled else {
            return
        }
        
        // 2. Проверка фильтра (например, только отобранные или с рейтингом)
        guard config.filterMode.matches(group: group) else {
            return
        }
        
        // 3. Переключение с учётом заданной задержки (для устранения стробирования при серии)
        let delay = config.switchDelay.seconds
        if delay <= 0.01 {
            pendingSwitchTask?.cancel()
            self.displayedGroup = group
        } else {
            // Отменяем предыдущее отложенное переключение и взводим новое (дебаунс серии)
            pendingSwitchTask?.cancel()
            pendingSwitchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self = self else { return }
                guard !self.config.isHoldEnabled else { return }
                
                self.displayedGroup = group
            }
        }
    }
    
    /// Обработка обновления существующего кадра (выставление рейтинга, флага Pick и т.д.)
    public func handleGroupUpdated(_ group: CaptureGroup) {
        // Обновляем метаданные текущего отображаемого кадра
        if displayedGroup?.id == group.id {
            displayedGroup = group
        }
        
        if heldGroup?.id == group.id {
            heldGroup = group
        }
        
        // Если кадр только что получил статус, удовлетворяющий фильтру клиента (например, фотограф нажал Pick 'P')
        if !config.isHoldEnabled && config.filterMode != .all && config.filterMode.matches(group: group) {
            self.displayedGroup = group
        }
    }
    
    // MARK: - Управление удержанием кадра (Hold / Pin / Freeze)
    
    /// Переключение режима удержания для указанного кадра (или текущего отображаемого)
    public func toggleHold(for group: CaptureGroup? = nil) {
        if config.isHoldEnabled {
            releaseHold()
        } else {
            setHold(true, for: group ?? displayedGroup)
        }
    }
    
    /// Включение или отключение фиксации кадра
    public func setHold(_ enabled: Bool, for group: CaptureGroup? = nil) {
        config.isHoldEnabled = enabled
        if enabled {
            let target = group ?? displayedGroup
            heldGroup = target
            config.heldGroupID = target?.id
            if let t = target {
                displayedGroup = t
            }
        } else {
            heldGroup = nil
            config.heldGroupID = nil
        }
    }
    
    /// Снятие фиксации с возможной актуализацией до последнего кадра сессии
    public func releaseHold(latestGroup: CaptureGroup? = nil) {
        setHold(false, for: nil)
        if let latest = latestGroup, config.filterMode.matches(group: latest) {
            self.displayedGroup = latest
        }
    }
    
    /// Принудительный показ выбранного фотографом кадра на клиентском мониторе
    public func forcePresentGroup(_ group: CaptureGroup) {
        pendingSwitchTask?.cancel()
        if config.isHoldEnabled {
            heldGroup = group
            config.heldGroupID = group.id
        }
        self.displayedGroup = group
    }
    
    // MARK: - Управление внешним экраном (iPadOS USB-C / HDMI / AirPlay)
    
    private func setupExternalDisplayMonitoring() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIScreen.didConnectNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notif in
                guard let self = self, let screen = notif.object as? UIScreen else { return }
                self.attachExternalScreen(screen)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIScreen.didDisconnectNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notif in
                guard let self = self else { return }
                self.detachExternalScreen()
            }
            .store(in: &cancellables)
        
        // Проверка при инициализации
        if UIScreen.screens.count > 1 {
            let secondary = UIScreen.screens[1]
            attachExternalScreen(secondary)
        }
        #endif
    }
    
    #if canImport(UIKit)
    public var externalViewControllerProvider: ((ClientMonitorManager) -> UIViewController)?
    
    private func attachExternalScreen(_ screen: UIScreen) {
        // Очищаем предыдущее окно, если было
        detachExternalScreen()
        
        let bounds = screen.bounds
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let resolutionStr = "\(width)x\(height)"
        let displayName = "Внешний монитор"
        
        let window = UIWindow(frame: bounds)
        window.screen = screen
        
        let vc = externalViewControllerProvider?(self) ?? UIViewController()
        vc.view.backgroundColor = .black
        
        window.rootViewController = vc
        window.isHidden = false
        self.externalWindow = window
        
        self.externalDisplayStatus = .connected(name: displayName, resolution: resolutionStr)
        self.isExternalWindowActive = true
    }
    
    private func detachExternalScreen() {
        if let win = externalWindow {
            win.isHidden = true
            win.rootViewController = nil
            self.externalWindow = nil
        }
        self.externalDisplayStatus = .disconnected
        self.isExternalWindowActive = false
    }
    #endif
    
    // MARK: - Симуляция для тестирования и не-UIKit платформ
    
    public func simulateExternalDisplayConnected(name: String = "External HDMI Display", resolution: String = "3840x2160") {
        self.externalDisplayStatus = .connected(name: name, resolution: resolution)
        self.isExternalWindowActive = true
    }
    
    public func simulateExternalDisplayDisconnected() {
        self.externalDisplayStatus = .disconnected
        self.isExternalWindowActive = false
    }
    
    // MARK: - Сохранение конфигурации
    
    private func saveConfig() {
        // При необходимости можно сохранять в UserDefaults
    }
}

