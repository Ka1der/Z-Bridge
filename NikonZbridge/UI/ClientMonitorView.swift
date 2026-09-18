import SwiftUI

/// Полноэкранный режим клиентского монитора для экрана iPad
public struct ClientMonitorView: View {
    @ObservedObject var monitorManager: ClientMonitorManager
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var showControls: Bool = true
    @State private var isSettingsSheetPresented: Bool = false
    @State private var hideControlsTask: Task<Void, Never>?
    
    public init(monitorManager: ClientMonitorManager, appState: AppState) {
        self.monitorManager = monitorManager
        self.appState = appState
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Основное изображение кадра
            if let group = monitorManager.displayedGroup ?? appState.filteredGroups.first {
                ClientMonitorImageView(group: group)
                    .id(group.id)
                    .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Ожидание снимков с камеры Nikon...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            
            // Тонкий ненавязчивый оверлей статуса
            if monitorManager.config.showSubtleOverlay, let group = monitorManager.displayedGroup ?? appState.filteredGroups.first {
                VStack {
                    HStack {
                        if monitorManager.config.isHoldEnabled {
                            HStack(spacing: 5) {
                                Image(systemName: "pin.fill")
                                Text("УДЕРЖАНИЕ (HOLD)")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.9))
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                        }
                        
                        Spacer()
                        
                        if group.rating > 0 {
                            HStack(spacing: 3) {
                                ForEach(1...group.rating, id: \.self) { _ in
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
                        
                        if group.pickStatus == .picked {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                                .padding(5)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    HStack {
                        Text(group.baseName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            
            // Всплывающие элементы управления для фотографа при касании экрана
            if showControls {
                VStack {
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Выход")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        // Кнопка удержания (Hold)
                        Button {
                            monitorManager.toggleHold(for: appState.selectedGroup)
                            resetHideTimer()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: monitorManager.config.isHoldEnabled ? "pin.slash.fill" : "pin.fill")
                                Text(monitorManager.config.isHoldEnabled ? "Отпустить" : "Удержать")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(monitorManager.config.isHoldEnabled ? Color.orange : Color.white.opacity(0.2))
                            .clipShape(Capsule())
                        }
                        
                        // Кнопка открытия настроек монитора
                        Button {
                            isSettingsSheetPresented = true
                            resetHideTimer()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
            if showControls {
                resetHideTimer()
            }
        }
        .onAppear {
            if monitorManager.displayedGroup == nil {
                monitorManager.displayedGroup = appState.filteredGroups.first
            }
            resetHideTimer()
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            ClientMonitorControlSheet(monitorManager: monitorManager, appState: appState)
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
    }
    
    private func resetHideTimer() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 секунды
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }
}

/// Специальный чистый хостинг-контейнер для внешнего экрана без каких-либо оверлеев системы
public struct ClientMonitorCleanHostingView: View {
    @ObservedObject var monitorManager: ClientMonitorManager
    
    public init(monitorManager: ClientMonitorManager) {
        self.monitorManager = monitorManager
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let group = monitorManager.displayedGroup {
                ClientMonitorImageView(group: group)
                    .id(group.id)
                    .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Ожидание первого кадра...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            
            // Тонкий оверлей статуса
            if monitorManager.config.showSubtleOverlay, let group = monitorManager.displayedGroup {
                VStack {
                    HStack {
                        if monitorManager.config.isHoldEnabled {
                            HStack(spacing: 5) {
                                Image(systemName: "pin.fill")
                                Text("УДЕРЖАНИЕ (HOLD)")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        if group.rating > 0 {
                            HStack(spacing: 2) {
                                ForEach(1...group.rating, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.system(size: 10))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(20)
                    
                    Spacer()
                    
                    HStack {
                        Text(group.baseName)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        Spacer()
                    }
                    .padding(20)
                }
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
    }
}

/// Отображение превью кадра для клиентского монитора
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
