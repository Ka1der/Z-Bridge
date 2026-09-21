import SwiftUI

/// Режим компоновки адаптивного каркаса
public enum AppLayoutMode: Equatable, Sendable {
    case narrow // Нижняя навигация (Liquid Glass Dock)
    case wide   // Боковая панель (Liquid Glass Sidebar)
}

/// Чистый резолвер компоновки на основе доступной ширины окна и масштаба системного шрифта (Dynamic Type).
/// Полностью исключает привязку исключительно к UIDevice.userInterfaceIdiom.
public struct AdaptiveLayoutResolver: Sendable {
    /// Базовый порог ширины в pt при стандартном размере текста (Large)
    public static let baseBreakpointWidth: CGFloat = 680.0
    
    /// Вычисляет режим компоновки исходя из ширины окна и масштаба системного шрифта (Dynamic Type)
    public static func resolve(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> AppLayoutMode {
        let scale: CGFloat
        switch dynamicTypeSize {
        case .xSmall, .small:
            scale = 0.95
        case .medium, .large:
            scale = 1.00
        case .xLarge:
            scale = 1.08
        case .xxLarge:
            scale = 1.16
        case .xxxLarge:
            scale = 1.25
        case .accessibility1:
            scale = 1.35
        case .accessibility2:
            scale = 1.48
        case .accessibility3:
            scale = 1.62
        case .accessibility4:
            scale = 1.76
        case .accessibility5:
            scale = 1.90
        @unknown default:
            scale = 1.00
        }
        
        let dynamicBreakpoint = baseBreakpointWidth * scale
        return width >= dynamicBreakpoint ? .wide : .narrow
    }
}

/// Единый адаптивный каркас приложения NikonZbridge в концепции «Liquid Glass».
/// 
/// Особенности:
/// - Единый экземпляр AppState хранится на уровне корневого представления (@StateObject)
///   и никогда не пересоздаётся при смене разделов, вращении экрана или изменении размера окна;
/// - Разделы приложения: 1. Снимки, 2. Камера, 3. Сессии;
/// - На узком окне (iPhone, узкий Split View iPad) используется нижняя плавающая навигация;
/// - На широком окне (iPad, широкий Split View, ландшафтный iPhone) — боковая панель;
/// - Настройки доступны в обеих компоновках;
/// - Модальные окна централизованы на уровне каркаса и сохраняют открытое состояние при смене компоновок;
/// - Никаких повторных вызовов bootstrap из onAppear.
public struct AdaptiveAppShellView: View {
    @StateObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    
    public init(appState: AppState? = nil) {
        if let appState {
            self._appState = StateObject(wrappedValue: appState)
        } else {
            self._appState = StateObject(wrappedValue: AppState())
        }
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let layoutMode = AdaptiveLayoutResolver.resolve(
                width: geometry.size.width,
                dynamicTypeSize: dynamicTypeSize
            )
            
            Group {
                switch layoutMode {
                case .wide:
                    WideAppShellView(appState: appState)
                case .narrow:
                    NarrowAppShellView(appState: appState)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        // MARK: - Централизованные модальные окна (сохраняются при вращении и ресайзе)
        .sheet(isPresented: $appState.isShowingConnectionSheet) {
            ConnectionSheetView(appState: appState)
        }
        .sheet(isPresented: $appState.isSettingsPresented) {
            ConnectionSheetView(appState: appState)
        }
        .sheet(isPresented: $appState.isShowingSessionSheet) {
            SessionManagementSheetView(appState: appState)
        }
        .sheet(isPresented: $appState.isShowingFilterSheet) {
            GalleryFilterSheetView(appState: appState)
        }
        .sheet(isPresented: $appState.isUSBBrowserPresented) {
            USBCameraBrowserView(usbManager: appState.currentUSBManager, sessionName: appState.currentSession?.name)
        }
        .sheet(isPresented: $appState.isQueuePresented) {
            TransferQueueView(appState: appState)
        }
        .sheet(isPresented: $appState.isWizardPresented) {
            ConnectionWizardView(appState: appState)
        }
        .sheet(isPresented: $appState.isMatrixPresented) {
            CompatibilityMatrixView()
        }
        .sheet(isPresented: $appState.isComparePresented) {
            CompareView(appState: appState, initialGroupA: appState.selectedGroup, initialGroupB: appState.compareCandidateGroup)
        }
        .sheet(isPresented: $appState.isExportSheetPresented) {
            ExportSheetView(appState: appState, groups: appState.exportTargetGroups)
        }
        .sheet(isPresented: $appState.isClientControlSheetPresented) {
            ClientMonitorControlSheet(monitorManager: appState.clientMonitorManager, appState: appState)
        }
        .fullScreenCover(isPresented: $appState.isClientMonitorPresented) {
            ClientMonitorView(monitorManager: appState.clientMonitorManager, appState: appState)
        }
        .onChange(of: scenePhase) { newPhase in
            appState.handleScenePhaseChange(newPhase)
        }
    }
}
