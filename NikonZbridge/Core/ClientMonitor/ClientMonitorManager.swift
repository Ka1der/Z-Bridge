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
    
    /// Кадр, отображаемый на клиентском мониторе в данный момент (из сессии)
    @Published public var displayedGroup: CaptureGroup?
    
    /// Кадр с камеры USB, отображаемый на клиентском мониторе
    @Published public var displayedCameraFile: CameraFileItem?
    
    /// Прямое изображение для моментального показа (быстрое превью live tethering)
    @Published public var liveDirectImage: PlatformImage?
    
    /// Название файла для прямого изображения
    @Published public var liveDirectTitle: String?
    
    /// Зафиксированный (удерживаемый) кадр при активном режиме Hold
    @Published public var heldGroup: CaptureGroup?
    
    /// Зафиксированный файл с камеры при активном режиме Hold
    @Published public var heldCameraFile: CameraFileItem?
    
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
    
    /// Обработка нового кадра из сессии
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
            self.displayedCameraFile = nil
            self.liveDirectImage = nil
        } else {
            // Отменяем предыдущее отложенное переключение и взводим новое (дебаунс серии)
            pendingSwitchTask?.cancel()
            pendingSwitchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self = self else { return }
                guard !self.config.isHoldEnabled else { return }
                
                self.displayedGroup = group
                self.displayedCameraFile = nil
                self.liveDirectImage = nil
            }
        }
    }
    
    /// Обработка нового снимка, сделанного на подключенную камеру Nikon (Live Tethering)
    public func handleIncomingCameraFile(_ file: CameraFileItem, preview: CGImage? = nil) {
        guard !config.isHoldEnabled else { return }
        guard config.filterMode.matches(file: file) else { return }
        
        let delay = config.switchDelay.seconds
        if delay <= 0.01 {
            pendingSwitchTask?.cancel()
            self.displayedCameraFile = file
            self.displayedGroup = nil
            if let p = preview {
                #if canImport(UIKit)
                self.liveDirectImage = UIImage(cgImage: p)
                #elseif canImport(AppKit)
                self.liveDirectImage = NSImage(cgImage: p, size: NSSize(width: p.width, height: p.height))
                #endif
                self.liveDirectTitle = file.filename
            }
        } else {
            pendingSwitchTask?.cancel()
            pendingSwitchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self = self else { return }
                guard !self.config.isHoldEnabled else { return }
                
                self.displayedCameraFile = file
                self.displayedGroup = nil
                if let p = preview {
                    #if canImport(UIKit)
                    self.liveDirectImage = UIImage(cgImage: p)
                    #elseif canImport(AppKit)
                    self.liveDirectImage = NSImage(cgImage: p, size: NSSize(width: p.width, height: p.height))
                    #endif
                    self.liveDirectTitle = file.filename
                }
            }
        }
    }
    
    /// Установка готового изображения для мгновенного показа
    public func setDirectImage(_ image: PlatformImage, title: String) {
        guard !config.isHoldEnabled else { return }
        self.liveDirectImage = image
        self.liveDirectTitle = title
    }
    
    /// Обработка обновления существующего кадра (выставление рейтинга, флага Pick и т.д.)
    public func handleGroupUpdated(_ group: CaptureGroup) {
        if displayedGroup?.id == group.id {
            displayedGroup = group
        }
        
        if heldGroup?.id == group.id {
            heldGroup = group
        }
        
        if !config.isHoldEnabled && config.filterMode != .all && config.filterMode.matches(group: group) {
            self.displayedGroup = group
        }
    }
    
    // MARK: - Управление удержанием кадра (Hold / Pin / Freeze)
    
    /// Переключение режима удержания для указанного кадра или файла
    public func toggleHold(for group: CaptureGroup? = nil, file: CameraFileItem? = nil) {
        if config.isHoldEnabled {
            releaseHold()
        } else {
            setHold(true, for: group ?? displayedGroup, file: file ?? displayedCameraFile)
        }
    }
    
    /// Включение или отключение фиксации кадра
    public func setHold(_ enabled: Bool, for group: CaptureGroup? = nil, file: CameraFileItem? = nil) {
        config.isHoldEnabled = enabled
        if enabled {
            let targetGroup = group ?? displayedGroup
            let targetFile = file ?? displayedCameraFile
            heldGroup = targetGroup
            heldCameraFile = targetFile
            config.heldGroupID = targetGroup?.id ?? targetFile?.id
            if let tg = targetGroup {
                displayedGroup = tg
            }
            if let tf = targetFile {
                displayedCameraFile = tf
            }
        } else {
            heldGroup = nil
            heldCameraFile = nil
            config.heldGroupID = nil
        }
    }
    
    /// Снятие фиксации с возможной актуализацией до последнего кадра
    public func releaseHold(latestGroup: CaptureGroup? = nil, latestFile: CameraFileItem? = nil) {
        setHold(false, for: nil, file: nil)
        if let latest = latestGroup, config.filterMode.matches(group: latest) {
            self.displayedGroup = latest
            self.displayedCameraFile = nil
        } else if let latestF = latestFile, config.filterMode.matches(file: latestF) {
            self.displayedCameraFile = latestF
            self.displayedGroup = nil
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
        self.displayedCameraFile = nil
    }
    
    public func forcePresentCameraFile(_ file: CameraFileItem) {
        pendingSwitchTask?.cancel()
        if config.isHoldEnabled {
            heldCameraFile = file
            config.heldGroupID = file.id
        }
        self.displayedCameraFile = file
        self.displayedGroup = nil
        self.liveDirectImage = nil
    }
    
    /// Навигация по файлам камеры на клиентском мониторе
    public func showNextCameraFile(in files: [CameraFileItem]) {
        guard !config.isHoldEnabled, !files.isEmpty else { return }
        guard let current = displayedCameraFile, let idx = files.firstIndex(where: { $0.id == current.id }) else {
            if let first = files.first {
                displayedCameraFile = first
                liveDirectImage = nil
            }
            return
        }
        let nextIdx = idx + 1
        if nextIdx < files.count {
            displayedCameraFile = files[nextIdx]
            liveDirectImage = nil
        }
    }
    
    public func showPreviousCameraFile(in files: [CameraFileItem]) {
        guard !config.isHoldEnabled, !files.isEmpty else { return }
        guard let current = displayedCameraFile, let idx = files.firstIndex(where: { $0.id == current.id }) else {
            if let last = files.last {
                displayedCameraFile = last
                liveDirectImage = nil
            }
            return
        }
        let prevIdx = idx - 1
        if prevIdx >= 0 {
            displayedCameraFile = files[prevIdx]
            liveDirectImage = nil
        }
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

