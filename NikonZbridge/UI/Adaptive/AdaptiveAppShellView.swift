import SwiftUI

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
