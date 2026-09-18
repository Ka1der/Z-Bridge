import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Менеджер жизненного цикла приложения:
/// - Управление автоблокировкой экрана при активной съемке
/// - Обработка переходов scenePhase (.active, .inactive, .background)
/// - Безопасное завершение активных операций в фоне средствами ОС
/// - Синхронизация данных перед приостановкой
@MainActor
public final class LifecycleManager: ObservableObject {
    public static let shared = LifecycleManager()
    
    public static let backgroundLimitationNotice = """
    iOS ограничивает непрерывную работу сетевых серверов в фоновом режиме и при выключенном экране. \
    При сворачивании приложения активная передача завершится в течение ~30 секунд средствами ОС, \
    после чего приём приостановится до возврата в приложение. \
    Для непрерывной студийной съемки рекомендуется держать экран включенным.
    """
    
    private let defaultsKey = "nikon_prevent_sleep_during_shooting"
    
    @Published public var isIdleTimerDisabledDuringShooting: Bool {
        didSet {
            UserDefaults.standard.set(isIdleTimerDisabledDuringShooting, forKey: defaultsKey)
            updateScreenLockState()
        }
    }
    
    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    private var activityToken: NSObjectProtocol?
    private var isCameraActive: Bool = false
    
    public init() {
        let saved = UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
        self.isIdleTimerDisabledDuringShooting = saved
    }
    
    /// Обновление статуса активности камеры (для управления удержанием экрана)
    public func setCameraActive(_ active: Bool) {
        self.isCameraActive = active
        updateScreenLockState()
    }
    
    /// Управление предотвращением сна / блокировки экрана
    public func updateScreenLockState() {
        let shouldKeepAwake = isIdleTimerDisabledDuringShooting && isCameraActive
        
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
        #endif
        
        if shouldKeepAwake {
            if activityToken == nil {
                activityToken = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated],
                    reason: "Nikon Z Active Tethering Ingest"
                )
                DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Активирован режим удержания экрана для съемки")
            }
        } else {
            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
                activityToken = nil
                DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Режим удержания экрана деактивирован")
            }
        }
    }
    
    /// Обработка изменения фазы сцены приложения
    public func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        hasActiveJobs: Bool,
        coordinator: TransferCoordinator,
        onForegroundResume: (@Sendable () -> Void)? = nil
    ) {
        switch newPhase {
        case .background:
            DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Приложение переходит в фон (background)")
            
            #if canImport(UIKit)
            if hasActiveJobs {
                // Запрашиваем у ОС ограниченное дополнительное время для завершения активного файла
                self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CompleteActiveTransfer") { [weak self] in
                    guard let self = self else { return }
                    DiagnosticLogger.shared.log(level: .warning, subsystem: "Lifecycle", message: "Лимит фонового времени ОС исчерпан")
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                }
                DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Запрошен фоновый тайм-слот ОС для завершения передачи")
            }
            #endif
            
        case .inactive:
            DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Приложение переходит в неактивный режим (inactive)")
            
        case .active:
            DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Приложение возвращено на передний план (active)")
            
            #if canImport(UIKit)
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
            #endif
            
            updateScreenLockState()
            onForegroundResume?()
            
        @unknown default:
            break
        }
    }
    
    /// Завершение фонового тайм-слота, если все задачи завершились раньше лимита
    public func endBackgroundTaskIfActive() {
        #if canImport(UIKit)
        if self.backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
            DiagnosticLogger.shared.log(level: .info, subsystem: "Lifecycle", message: "Фоновая задача ОС успешно завершена досрочно")
        }
        #endif
    }
}
