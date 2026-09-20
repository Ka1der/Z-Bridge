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
            AppTheme.Colors.background.ignoresSafeArea()
            
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
        HStack(spacing: AppTheme.Spacing.sm) {
            // Кнопка названия сессии с переходом к истории
            Button {
                isShowingSessionSheet = true
            } label: {
                HStack(spacing: AppTheme.Spacing.xs + 1) {
                    Image(systemName: "folder")
                        .font(.subheadline)
                    Text(appState.currentSession?.name ?? "Сессия")
                        .font(AppTheme.Typography.subheadlineBold)
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: AppTheme.Dimensions.buttonHeight)
                .glassPill()
            }
            .accessibilityLabel("Сессия: \(appState.currentSession?.name ?? "Сессия")")
            .accessibilityHint("Нажмите для перехода к истории сессий")
            
            // Один статус подключения (ConnectionStatusView)
            ConnectionStatusView(
                status: connectionStatusState,
                title: appState.connectionStatusTitle,
                shortTitle: appState.shortConnectionStatusTitle,
                iconName: connectionStatusIcon,
                style: .pill,
                action: {
                    isShowingConnectionSheet = true
                }
            )
            
            Spacer(minLength: AppTheme.Spacing.xs)
            
            // Подписанная кнопка «Импортировать»
            PrimaryImportButton(
                isReadingCatalog: appState.usbConnected && !appState.currentUSBManager.isCatalogReady,
                unimportedCount: appState.currentUSBManager.catalogFiles.filter { $0.status == .notImported }.count,
                action: {
                    if appState.usbConnected {
                        appState.isUSBBrowserPresented = true
                    } else {
                        isShowingConnectionSheet = true
                    }
                }
            )
            
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
                Image(systemName: "ellipsis")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                    .glassSurface(shape: Circle())
            }
            .accessibilityLabel("Дополнительные действия")
        }
    }
    
    private var connectionStatusState: ConnectionStatusView.Status {
        if appState.isCameraConnected {
            return .connected
        } else if appState.isCameraConnecting {
            return .connecting
        } else if appState.isServerRunning {
            return .idle
        } else {
            return .disconnected
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
        TransferProgressStrip(
            filename: job.filename,
            transferredBytes: job.transferredBytes,
            totalBytes: job.totalBytes,
            speedMBs: appState.currentTransferSpeedMBs,
            isUSB: job.source.transportType == .usb,
            onTap: {
                appState.isQueuePresented = true
            },
            onCancel: {
                appState.cancelJob(id: job.id)
            }
        )
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
