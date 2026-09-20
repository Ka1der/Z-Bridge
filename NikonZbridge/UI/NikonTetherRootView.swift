import SwiftUI

/// Главный экран NikonZbridge с адаптивной и минималистичной разметкой
public struct NikonTetherRootView: View {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingConnectionSheet = false
    @State private var isShowingSessionSheet = false
    @State private var isShowingFilterSheet = false
    @State private var isShowingClearAlert = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. ВЕРХНЯЯ ПАНЕЛЬ: название сессии, один статус, кнопка «Импортировать», меню дополнительных действий
                topHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                
                // 1a. КОМПАКТНЫЙ ПРОГРЕСС-БАР ПЕРЕНОСА (при активной передаче)
                if let activeJob = appState.activeTransferJob {
                    compactTransferBar(job: activeJob)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                
                // 2. КОМПАКТНЫЙ СТАТУС-БАННЕР (при наличии сохраненных снимков в сессии)
                if let banner = appState.mainScreenState.compactBanner {
                    compactBannerView(banner)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                
                // 3. ВТОРИЧНАЯ ПАНЕЛЬ ГАЛЕРЕИ (скрывается, когда галерея пуста)
                if appState.mainScreenState.hasPhotos && !appState.mainScreenState.areAllPhotosFilteredOut {
                    galleryControlsBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                
                Divider()
                
                // 4. ОСНОВНАЯ ОБЛАСТЬ КОНТЕНТА
                mainContentArea
            }
            
            // Всплывающее уведомление о новом кадре во время активной инспекции
            if let notification = appState.pendingIncomingFrameNotification {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.green)
                        Text(notification)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        
                        Button {
                            appState.switchToPendingGroup()
                        } label: {
                            Text("Показать")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        
                        Button {
                            appState.dismissPendingNotification()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Закрыть уведомление")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 45)
                    
                    Spacer()
                }
            }
            
            // Плавающая панель массовых действий при множественном выборе
            if appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
                VStack {
                    Spacer()
                    BatchActionBarView(appState: appState)
                        .padding(.bottom, 16)
                }
            }
            
            // Невидимые триггеры клавиатурных команд iPad
            keyboardShortcutsView
        }
        .sheet(isPresented: $isShowingConnectionSheet) {
            ConnectionSheetView(appState: appState)
        }
        .sheet(isPresented: $isShowingSessionSheet) {
            SessionManagementSheetView(appState: appState)
        }
        .sheet(isPresented: $isShowingFilterSheet) {
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
        .alert("Очистить все снимки?", isPresented: $isShowingClearAlert) {
            Button("Очистить", role: .destructive) {
                appState.clearGallery()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
    
    // MARK: - 1. Top HUD
    
    private var topHUD: some View {
        HStack(spacing: 8) {
            // Кнопка названия сессии с переходом к истории
            Button {
                isShowingSessionSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.subheadline)
                    Text(appState.currentSession?.name ?? "Сессия")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemFill))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Сессия: \(appState.currentSession?.name ?? "Сессия")")
            .accessibilityHint("Нажмите для перехода к истории сессий")
            
            // Один статус подключения (не передает статус только цветом)
            Button {
                isShowingConnectionSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: connectionStatusIcon)
                        .font(.subheadline)
                        .foregroundStyle(connectionStatusColor)
                    
                    ViewThatFits(in: .horizontal) {
                        Text(appState.connectionStatusTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(appState.shortConnectionStatusTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemFill))
                .clipShape(Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Статус подключения: \(appState.connectionStatusTitle)")
            .accessibilityHint("Нажмите для открытия настроек подключения")
            
            Spacer(minLength: 4)
            
            // Подписанная кнопка «Импортировать»
            Button {
                if appState.usbConnected {
                    appState.isUSBBrowserPresented = true
                } else {
                    isShowingConnectionSheet = true
                }
            } label: {
                HStack(spacing: 5) {
                    if appState.usbConnected && !appState.currentUSBManager.isCatalogReady {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                        Text("Чтение...")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.subheadline)
                        
                        ViewThatFits(in: .horizontal) {
                            Text("Импортировать")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            
                            Text("Импорт")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                        }
                        
                        let unimported = appState.currentUSBManager.catalogFiles.filter { $0.status == .notImported }.count
                        if unimported > 0 {
                            Text("\(unimported)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.35))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .accessibilityLabel(appState.usbConnected && !appState.currentUSBManager.isCatalogReady ? "Идет чтение карты памяти камеры" : "Импортировать снимки с камеры")
            .accessibilityHint("Нажмите для выбора и загрузки снимков с карты памяти камеры")
            
            // Меню дополнительных действий
            Menu {
                // Очередь переноса
                Button {
                    appState.isQueuePresented = true
                } label: {
                    if appState.activeQueueCount > 0 {
                        Label("Очередь загрузки (\(appState.activeQueueCount))", systemImage: "tray.and.arrow.down")
                    } else {
                        Label("Очередь загрузки", systemImage: "tray.and.arrow.down")
                    }
                }
                
                // Клиентский монитор
                Button {
                    appState.presentClientControlSheet()
                } label: {
                    Label(
                        appState.clientMonitorManager.config.isHoldEnabled
                            ? "Клиентский монитор (HOLD)"
                            : (appState.clientMonitorManager.externalDisplayStatus.isConnected ? "Клиентский монитор (HDMI)" : "Клиентский монитор"),
                        systemImage: appState.clientMonitorManager.externalDisplayStatus.isConnected ? "tv.fill" : "tv"
                    )
                }
                
                // Экспорт сессии
                Button {
                    appState.presentExportForSession()
                } label: {
                    Label("Экспорт сессии...", systemImage: "square.and.arrow.up")
                }
                
                Divider()
                
                // Настройки и мастер подключения
                Button {
                    isShowingConnectionSheet = true
                } label: {
                    Label("Настройки подключения...", systemImage: "gearshape")
                }
                
                Button {
                    appState.isWizardPresented = true
                } label: {
                    Label("Мастер подключения...", systemImage: "wand.and.stars")
                }
                
                Button {
                    appState.isMatrixPresented = true
                } label: {
                    Label("Таблица совместимости XMP...", systemImage: "info.circle")
                }
                
                Divider()
                
                // Автопросмотр новых кадров
                Button {
                    appState.isAutoScrollEnabled.toggle()
                } label: {
                    Label(
                        appState.isAutoScrollEnabled ? "Автопросмотр: Вкл" : "Автопросмотр: Выкл",
                        systemImage: appState.isAutoScrollEnabled ? "checkmark.circle.fill" : "circle"
                    )
                }
                
                Divider()
                
                // Очистить снимки
                Button(role: .destructive) {
                    isShowingClearAlert = true
                } label: {
                    Label("Очистить галерею...", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemFill))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Дополнительные действия")
        }
    }
    
    private var connectionStatusIcon: String {
        if appState.usbConnected {
            return "cable.connector"
        } else if appState.isServerRunning && appState.connectedClients > 0 {
            return "wifi"
        } else if appState.isServerRunning {
            return "wifi.badge.questionmark"
        } else if appState.isCameraConnecting {
            return "arrow.triangle.2.circlepath"
        } else {
            return "bolt.slash"
        }
    }
    
    private var connectionStatusColor: Color {
        if appState.isCameraConnected {
            return .green
        } else if appState.isCameraConnecting {
            return .orange
        } else {
            return .secondary
        }
    }
    
    // MARK: - 2. Вторичная панель управления галереей
    
    @ViewBuilder
    private var galleryControlsBar: some View {
        HStack(spacing: 8) {
            // Счетчик кадров
            Text("\(appState.filteredGroups.count) из \(appState.totalFramesCount) кадров")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            
            if appState.pairedCount > 0 {
                Text("• \(appState.pairedCount) пар")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            
            Spacer()
            
            // Меню выбора вида (Сетка, Просмотр, Список, Таблица)
            Menu {
                Picker("Режим отображения", selection: $appState.viewMode) {
                    Label("Сетка", systemImage: "square.grid.2x2").tag(ViewMode.icons)
                    Label("Просмотр", systemImage: "photo.fill").tag(ViewMode.viewer)
                    Label("Список", systemImage: "list.bullet").tag(ViewMode.list)
                    Label("Таблица", systemImage: "tablecells").tag(ViewMode.table)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.viewMode.iconName)
                    Text(appState.viewMode.rawValue)
                        .font(.caption.bold())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemFill))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Режим отображения: \(appState.viewMode.rawValue)")
            .accessibilityHint("Нажмите для выбора между сеткой, просмотром, списком и таблицей")
            
            // Кнопка панели «Фильтры»
            Button {
                isShowingFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text("Фильтры")
                        .font(.caption.bold())
                    
                    if appState.activeFilterCount > 0 {
                        Text("\(appState.activeFilterCount)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(appState.hasActiveFilters ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: appState.hasActiveFilters ? .tertiarySystemFill : .secondarySystemFill))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Фильтры" + (appState.activeFilterCount > 0 ? ", активно: \(appState.activeFilterCount)" : ""))
            .accessibilityHint("Нажмите для настройки фильтров формата, рейтинга и отбора")
            
            // Быстрый сброс фильтров при их активности
            if appState.hasActiveFilters {
                Button {
                    appState.resetFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Сбросить все фильтры")
            }
            
            // Кнопка режима множественного выбора
            Button {
                withAnimation {
                    appState.isSelectionMode.toggle()
                    if !appState.isSelectionMode {
                        appState.clearSelection()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(appState.isSelectionMode ? "Готово" : "Выбрать")
                        .font(.caption.bold())
                }
                .foregroundStyle(appState.isSelectionMode ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: appState.isSelectionMode ? .tertiarySystemFill : .secondarySystemFill))
                .clipShape(Capsule())
            }
            .accessibilityLabel(appState.isSelectionMode ? "Завершить выбор" : "Включить выбор кадров")
        }
    }
    
    // MARK: - 3. Main Content Area
    
    @ViewBuilder
    private var mainContentArea: some View {
        if let emptyState = appState.mainScreenState.emptyState {
            mainScreenEmptyContentView(emptyState)
        } else {
            switch appState.viewMode {
            case .icons:
                IconsGridView(
                    groups: appState.filteredGroups,
                    selectedGroup: appState.selectedGroup,
                    isSelectionMode: appState.isSelectionMode,
                    selectedGroupIDs: appState.selectedGroupIDs,
                    onToggleSelect: { group in
                        appState.toggleSelectGroup(group)
                    }
                ) { group in
                    appState.selectedGroup = group
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .viewer
                    }
                }
            case .viewer:
                viewerView
            case .list:
                PhotoListView(
                    groups: appState.filteredGroups,
                    selectedGroup: appState.selectedGroup,
                    isSelectionMode: appState.isSelectionMode,
                    selectedGroupIDs: appState.selectedGroupIDs,
                    onToggleSelect: { group in
                        appState.toggleSelectGroup(group)
                    }
                ) { group in
                    appState.selectedGroup = group
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .viewer
                    }
                }
            case .table:
                PhotoTableView(
                    groups: appState.filteredGroups,
                    selectedGroup: appState.selectedGroup,
                    isSelectionMode: appState.isSelectionMode,
                    selectedGroupIDs: appState.selectedGroupIDs,
                    onToggleSelect: { group in
                        appState.toggleSelectGroup(group)
                    }
                ) { group in
                    appState.selectedGroup = group
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .viewer
                    }
                }
            }
        }
    }
    
    // MARK: - Mode: Viewer
    
    private var viewerView: some View {
        VStack(spacing: 0) {
            if let currentGroup = appState.selectedGroup ?? appState.filteredGroups.first {
                PhotoDetailView(group: currentGroup, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let currentFile = appState.selectedFile ?? appState.filteredFiles.first {
                PhotoDetailView(file: currentFile, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            bottomFilmstrip
        }
    }
    
    // MARK: - Bottom Filmstrip
    
    private var bottomFilmstrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(appState.filteredGroups.count) из \(appState.totalFramesCount) кадров")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                if appState.pairedCount > 0 {
                    Text("• \(appState.pairedCount) пар")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                Spacer()
                
                // Кнопка возврата к сетке
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .icons
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("Сетка")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: 44)
                }
                .padding(.trailing, 8)
                
                // Переключатель «Автопросмотр»
                Button {
                    appState.isAutoScrollEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isAutoScrollEnabled ? "bolt.circle.fill" : "bolt.circle")
                        Text("Автопросмотр")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(appState.isAutoScrollEnabled ? Color.accentColor : .secondary)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 16)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(appState.filteredGroups) { group in
                            FilmstripTile(
                                group: group,
                                isSelected: appState.selectedGroup?.id == group.id
                            )
                            .id(group.id)
                            .onTapGesture {
                                appState.selectedGroup = group
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 72)
                .onChange(of: appState.filteredGroups.first?.id) { _, newID in
                    if appState.isAutoScrollEnabled, let id = newID {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .leading)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    // MARK: - Compact Transfer Bar (Активная передача)
    
    @ViewBuilder
    private func compactTransferBar(job: TransferJob) -> some View {
        Button {
            appState.isQueuePresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: job.source.transportType == .usb ? "cable.connector" : "wifi")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(job.filename)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let total = job.totalBytes, total > 0 {
                            let progress = min(max(Double(job.transferredBytes) / Double(total), 0.0), 1.0)
                            Text(String(format: "%.0f%%", progress * 100))
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        let transferredMB = Double(job.transferredBytes) / 1_048_576.0
                        if let total = job.totalBytes, total > 0 {
                            let totalMB = Double(total) / 1_048_576.0
                            Text(String(format: "%.1f / %.1f МБ", transferredMB, totalMB))
                        } else {
                            Text(String(format: "%.1f МБ", transferredMB))
                        }
                        
                        if appState.currentTransferSpeedMBs > 0.05 {
                            Text(String(format: "• %.1f МБ/с", appState.currentTransferSpeedMBs))
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                
                // Индикатор прогресса
                if let total = job.totalBytes, total > 0 {
                    let progress = min(max(Double(job.transferredBytes) / Double(total), 0.0), 1.0)
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(maxWidth: 70)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                }
                
                Spacer()
                
                // Кнопка отмены активного задания
                Button(role: .destructive) {
                    appState.cancelJob(id: job.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отменить передачу файла")
                
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Активная передача \(job.filename). Нажмите для открытия очереди.")
    }
    
    // MARK: - Compact Banner & Empty Content Views
    
    @ViewBuilder
    private func compactBannerView(_ banner: MainScreenCompactBanner) -> some View {
        HStack(spacing: 10) {
            Image(systemName: banner.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(bannerIconColor(for: banner.style))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                if let msg = banner.message {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if banner.showsProgress {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
            }
            
            Spacer()
            
            if let action = banner.action {
                Button {
                    appState.handleMainScreenAction(action.type)
                } label: {
                    if let icon = action.systemImage {
                        Label(action.title, systemImage: icon)
                            .font(.caption.bold())
                    } else {
                        Text(action.title)
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bannerBackgroundColor(for: banner.style))
        .cornerRadius(8)
    }
    
    private func bannerIconColor(for style: MainScreenCompactBanner.Style) -> Color {
        switch style {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .success: return .green
        }
    }
    
    private func bannerBackgroundColor(for style: MainScreenCompactBanner.Style) -> Color {
        switch style {
        case .error: return Color.red.opacity(0.18)
        case .warning: return Color.orange.opacity(0.18)
        case .info: return Color.blue.opacity(0.15)
        case .success: return Color.green.opacity(0.15)
        }
    }
    
    @ViewBuilder
    private func mainScreenEmptyContentView(_ state: MainScreenEmptyState) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
                    .frame(width: 130, height: 130)
                
                Image(systemName: state.systemImage)
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(Color.accentColor)
            }
            
            VStack(spacing: 8) {
                Text(state.title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(state.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                if state.showsProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.top, 4)
                }
            }
            
            HStack(spacing: 12) {
                if let secondary = state.secondaryAction {
                    Button {
                        appState.handleMainScreenAction(secondary.type)
                    } label: {
                        if let icon = secondary.systemImage {
                            Label(secondary.title, systemImage: icon)
                                .font(.caption.bold())
                        } else {
                            Text(secondary.title)
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
                
                if let primary = state.primaryAction {
                    Button {
                        appState.handleMainScreenAction(primary.type)
                    } label: {
                        if let icon = primary.systemImage {
                            Label(primary.title, systemImage: icon)
                                .font(.subheadline.bold())
                        } else {
                            Text(primary.title)
                                .font(.subheadline.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - iPad Keyboard Shortcuts
    
    @ViewBuilder
    private var keyboardShortcutsView: some View {
        ZStack {
            // Рейтинг 0..5
            Button("") { applyRating(0) }.keyboardShortcut("0", modifiers: [])
            Button("") { applyRating(1) }.keyboardShortcut("1", modifiers: [])
            Button("") { applyRating(2) }.keyboardShortcut("2", modifiers: [])
            Button("") { applyRating(3) }.keyboardShortcut("3", modifiers: [])
            Button("") { applyRating(4) }.keyboardShortcut("4", modifiers: [])
            Button("") { applyRating(5) }.keyboardShortcut("5", modifiers: [])
            
            // Флаги: P (Pick), X (Reject), U (Unflag)
            Button("") { applyPickStatus(.picked) }.keyboardShortcut("p", modifiers: [])
            Button("") { applyPickStatus(.rejected) }.keyboardShortcut("x", modifiers: [])
            Button("") { applyPickStatus(.unflagged) }.keyboardShortcut("u", modifiers: [])
            
            // Навигация
            Button("") { appState.selectPreviousGroup() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { appState.selectNextGroup() }.keyboardShortcut(.rightArrow, modifiers: [])
            
            // Зум и сравнение
            Button("") { appState.isUserInspecting.toggle() }.keyboardShortcut(.space, modifiers: [])
            Button("") { appState.isUserInspecting.toggle() }.keyboardShortcut("z", modifiers: [])
            Button("") {
                if appState.canCompareSelected {
                    appState.presentCompareForSelected()
                } else if let sel = appState.selectedGroup ?? appState.filteredGroups.first {
                    appState.compareCandidateGroup = appState.filteredGroups.first(where: { $0.id != sel.id }) ?? sel
                    appState.isComparePresented.toggle()
                }
            }.keyboardShortcut("c", modifiers: [])
            
            // Клиентский монитор: H (Hold / Удержание), M (Monitor / Показ)
            Button("") { appState.toggleClientMonitorHold() }.keyboardShortcut("h", modifiers: [])
            Button("") { appState.presentClientMonitor() }.keyboardShortcut("m", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
    
    private func applyRating(_ rating: Int) {
        if appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
            appState.batchSetRating(rating)
        } else if let sel = appState.selectedGroup {
            appState.setRating(rating, for: sel)
        }
    }
    
    private func applyPickStatus(_ status: PickStatus) {
        if appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
            appState.batchSetPickStatus(status)
        } else if let sel = appState.selectedGroup {
            appState.setPickStatus(status, for: sel)
        }
    }
}
