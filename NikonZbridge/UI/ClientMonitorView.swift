import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Полноэкранный режим клиентского монитора для экрана iPhone и iPad
public struct ClientMonitorView: View {
    @ObservedObject var monitorManager: ClientMonitorManager
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var showControls: Bool = true
    @State private var isSettingsSheetPresented: Bool = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var zoomScale: CGFloat = 1.0
    
    public init(monitorManager: ClientMonitorManager, appState: AppState) {
        self.monitorManager = monitorManager
        self.appState = appState
    }
    
    // MARK: - Активный элемент для отображения
    
    private var activeCameraFile: CameraFileItem? {
        monitorManager.displayedCameraFile ?? appState.selectedCameraFile ?? appState.currentUSBManager.catalogFiles.last
    }
    
    private var activeGroup: CaptureGroup? {
        monitorManager.displayedGroup ?? appState.filteredGroups.first
    }
    
    private var activeTitle: String {
        if let direct = monitorManager.liveDirectTitle {
            return direct
        }
        if let file = activeCameraFile {
            return file.filename
        }
        if let group = activeGroup {
            return group.baseName
        }
        return ""
    }
    
    private var activeRating: Int {
        if let file = activeCameraFile {
            return file.rating
        }
        if let group = activeGroup {
            return group.rating
        }
        return 0
    }
    
    private var isPicked: Bool {
        if let group = activeGroup {
            return group.pickStatus == .picked
        }
        return false
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. Основное изображение кадра
            mainContent
                .scaleEffect(zoomScale)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { val in
                            guard zoomScale <= 1.05 else { return }
                            if abs(val.translation.width) > abs(val.translation.height) * 1.2 {
                                if val.translation.width < -40 {
                                    goToNext()
                                } else if val.translation.width > 40 {
                                    goToPrevious()
                                }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        zoomScale = zoomScale > 1.05 ? 1.0 : 2.5
                    }
                }
                .onTapGesture(count: 1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                    if showControls {
                        resetHideTimer()
                    }
                }
            
            // 2. Тонкий информационный оверлей статуса
            if monitorManager.config.showSubtleOverlay && !activeTitle.isEmpty {
                subtleInfoOverlay
            }
            
            // 3. Всплывающие элементы управления для фотографа
            if showControls {
                floatingControlsOverlay
            }
        }
        .onAppear {
            resolveInitialDisplay()
            resetHideTimer()
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            ClientMonitorControlSheet(monitorManager: monitorManager, appState: appState)
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
    }
    
    // MARK: - Центральная область контента
    
    @ViewBuilder
    private var mainContent: some View {
        if let direct = monitorManager.liveDirectImage {
            #if canImport(UIKit)
            Image(uiImage: direct)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
                .transition(.opacity)
                .id("direct_\(activeTitle)")
            #elseif canImport(AppKit)
            Image(nsImage: direct)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
                .transition(.opacity)
                .id("direct_\(activeTitle)")
            #endif
        } else if let file = activeCameraFile {
            ClientMonitorCameraFileImageView(item: file, usbManager: appState.currentUSBManager)
                .id(file.id)
                .transition(.opacity)
        } else if let group = activeGroup {
            ClientMonitorImageView(group: group)
                .id(group.id)
                .transition(.opacity)
        } else {
            emptyWaitingView
        }
    }
    
    // MARK: - Экран ожидания съемки
    
    private var emptyWaitingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(AppTheme.Colors.accent)
            
            Text(tr("Клиентский экран готов", "Client Monitor Ready"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            Text(tr(
                "Сделайте снимок на подключенной камере Nikon — фото сразу появится здесь на весь экран.",
                "Take a photo on your connected Nikon camera — it will immediately appear here fullscreen."
            ))
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            
            if appState.currentUSBManager.isConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.Colors.statusGreen)
                        .frame(width: 8, height: 8)
                    Text(appState.currentUSBManager.cameraName ?? "Nikon Z")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.statusGreen)
                    Text("• Live Tethering")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.Colors.statusGreen.opacity(0.18))
                .clipShape(Capsule())
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Информационный оверлей
    
    private var subtleInfoOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                // Статус удержания (Hold)
                if monitorManager.config.isHoldEnabled {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.fill")
                        Text(tr("УДЕРЖАНИЕ (HOLD)", "FREEZE (HOLD)"))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.9))
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                } else if appState.currentUSBManager.isConnected {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(AppTheme.Colors.statusGreen)
                            .frame(width: 6, height: 6)
                        Text(appState.currentUSBManager.cameraName ?? "Nikon Z")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Рейтинг и метка отбора
                HStack(spacing: 6) {
                    if activeRating > 0 {
                        HStack(spacing: 3) {
                            ForEach(1...activeRating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.system(size: 11))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    
                    if isPicked {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            // Название текущего файла внизу
            HStack {
                Text(activeTitle)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Всплывающие контролы управления
    
    private var floatingControlsOverlay: some View {
        VStack {
            // Верхняя панель
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text(tr("Выход", "Close"))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Кнопка удержания (Hold)
                Button {
                    monitorManager.toggleHold(for: activeGroup, file: activeCameraFile)
                    resetHideTimer()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: monitorManager.config.isHoldEnabled ? "pin.slash.fill" : "pin.fill")
                        Text(monitorManager.config.isHoldEnabled ? tr("Отпустить", "Release") : tr("Удержать", "Hold"))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(monitorManager.config.isHoldEnabled ? Color.orange : Color.white.opacity(0.2))
                    .clipShape(Capsule())
                }
                
                // Кнопка настроек монитора
                Button {
                    isSettingsSheetPresented = true
                    resetHideTimer()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Spacer()
            
            // Нижняя панель навигации (Предыдущий / Следующий кадр)
            HStack(spacing: 24) {
                Button {
                    goToPrevious()
                    resetHideTimer()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        zoomScale = zoomScale > 1.05 ? 1.0 : 2.5
                    }
                    resetHideTimer()
                } label: {
                    Text(zoomScale > 1.05 ? "1x" : "100%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                
                Button {
                    goToNext()
                    resetHideTimer()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, 24)
        }
        .transition(.opacity)
    }
    
    // MARK: - Вспомогательные методы
    
    private func resolveInitialDisplay() {
        if monitorManager.displayedGroup == nil && monitorManager.displayedCameraFile == nil {
            if let activeUSB = appState.selectedCameraFile ?? appState.currentUSBManager.catalogFiles.last {
                monitorManager.displayedCameraFile = activeUSB
            } else if let firstGroup = appState.filteredGroups.first {
                monitorManager.displayedGroup = firstGroup
            }
        }
    }
    
    private func goToPrevious() {
        if !appState.currentUSBManager.catalogFiles.isEmpty {
            monitorManager.showPreviousCameraFile(in: appState.currentUSBManager.catalogFiles)
        } else if !appState.filteredGroups.isEmpty {
            if let current = monitorManager.displayedGroup, let idx = appState.filteredGroups.firstIndex(where: { $0.id == current.id }), idx > 0 {
                monitorManager.displayedGroup = appState.filteredGroups[idx - 1]
            }
        }
    }
    
    private func goToNext() {
        if !appState.currentUSBManager.catalogFiles.isEmpty {
            monitorManager.showNextCameraFile(in: appState.currentUSBManager.catalogFiles)
        } else if !appState.filteredGroups.isEmpty {
            if let current = monitorManager.displayedGroup, let idx = appState.filteredGroups.firstIndex(where: { $0.id == current.id }), idx + 1 < appState.filteredGroups.count {
                monitorManager.displayedGroup = appState.filteredGroups[idx + 1]
            }
        }
    }
    
    private func resetHideTimer() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                showControls = false
            }
        }
    }
}

// MARK: - Отображение фото с USB-камеры с мгновенным показом миниатюры и подгрузкой 4K

public struct ClientMonitorCameraFileImageView: View {
    let item: CameraFileItem
    @ObservedObject var usbManager: USBCameraManager
    @State private var highResImage: PlatformImage?
    
    public init(item: CameraFileItem, usbManager: USBCameraManager) {
        self.item = item
        self.usbManager = usbManager
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let highRes = highResImage {
                    #if canImport(UIKit)
                    Image(uiImage: highRes)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    #elseif canImport(AppKit)
                    Image(nsImage: highRes)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    #endif
                } else if let thumb = item.thumbnail {
                    #if canImport(UIKit)
                    Image(uiImage: UIImage(cgImage: thumb))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    #elseif canImport(AppKit)
                    Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height)))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    #endif
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.6))
                        .onAppear {
                            usbManager.requestThumbnail(for: item)
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: item.id) {
                await loadHighRes()
            }
        }
    }
    
    private func loadHighRes() async {
        if let cg = await usbManager.requestHighResolutionPreview(for: item, maxPixelSize: 3840) {
            if Task.isCancelled { return }
            #if canImport(UIKit)
            self.highResImage = UIImage(cgImage: cg)
            #elseif canImport(AppKit)
            self.highResImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            #endif
        }
    }
}

// MARK: - Отображение фото из сессии (CaptureGroup)

public struct ClientMonitorImageView: View {
    let group: CaptureGroup
    @State private var previewImage: PlatformImage?
    
    public init(group: CaptureGroup) {
        self.group = group
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = previewImage {
                    #if canImport(UIKit)
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    #elseif canImport(AppKit)
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                    #endif
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.5))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: group.id) {
                await loadPreview()
            }
        }
    }
    
    private func loadPreview() async {
        guard let asset = group.primaryAsset else { return }
        let result = await PreviewPipeline.shared.loadThumbnail(for: asset.fileURL, maxPixelSize: 3840)
        if Task.isCancelled { return }
        if case .success(let img) = result {
            self.previewImage = img
        }
    }
}

// MARK: - Чистый полноэкранный контейнер для внешнего монитора (HDMI / USB-C / AirPlay)

public struct ClientMonitorCleanHostingView: View {
    @ObservedObject var monitorManager: ClientMonitorManager
    
    public init(monitorManager: ClientMonitorManager) {
        self.monitorManager = monitorManager
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let direct = monitorManager.liveDirectImage {
                #if canImport(UIKit)
                Image(uiImage: direct)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                #elseif canImport(AppKit)
                Image(nsImage: direct)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                #endif
            } else if let file = monitorManager.displayedCameraFile ?? USBCameraManager.shared.catalogFiles.last {
                ClientMonitorCameraFileImageView(item: file, usbManager: USBCameraManager.shared)
                    .id(file.id)
            } else if let group = monitorManager.displayedGroup {
                ClientMonitorImageView(group: group)
                    .id(group.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(tr("Ожидание первого кадра...", "Waiting for first shot..."))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            
            // Тонкий оверлей статуса для внешнего монитора
            if monitorManager.config.showSubtleOverlay {
                VStack {
                    HStack {
                        if monitorManager.config.isHoldEnabled {
                            HStack(spacing: 5) {
                                Image(systemName: "pin.fill")
                                Text(tr("УДЕРЖАНИЕ (HOLD)", "FREEZE (HOLD)"))
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.9))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                    }
                    .padding(20)
                    
                    Spacer()
                    
                    if let title = monitorManager.liveDirectTitle ?? monitorManager.displayedCameraFile?.filename ?? monitorManager.displayedGroup?.baseName {
                        HStack {
                            Text(title)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            Spacer()
                        }
                        .padding(20)
                    }
                }
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
    }
}
