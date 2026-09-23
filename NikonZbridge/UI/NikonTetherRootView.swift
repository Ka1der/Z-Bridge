import SwiftUI

/// Главный экран раздела «Снимки» NikonZbridge в дизайн-системе Liquid Glass
public struct NikonTetherRootView: View {
    @ObservedObject var appState: AppState
    public var showsSheets: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingClearAlert = false
    
    public init(appState: AppState, showsSheets: Bool = false) {
        self.appState = appState
        self.showsSheets = showsSheets
    }
    
    public init() {
        self.init(appState: AppState(), showsSheets: true)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let layoutMode = AdaptiveLayoutResolver.resolve(
                width: geometry.size.width,
                dynamicTypeSize: dynamicTypeSize
            )
            
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("Источник снимков", selection: $appState.photoSource) {
                        ForEach(PhotoSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)

                    if appState.photoSource == .camera {
                        USBCameraBrowserView(
                            usbManager: appState.currentUSBManager,
                            sessionName: appState.currentSession?.name,
                            selectedFileIDs: $appState.selectedCameraFileIDs,
                            formatFilter: $appState.cameraFormatFilter
                        )
                    } else {
                        switch layoutMode {
                        case .wide:
                            wideContentView(geometry: geometry)
                        case .narrow:
                            narrowContentView(geometry: geometry)
                        }
                    }
                }
                
                // Всплывающее уведомление о новом кадре во время активной инспекции
                if let notification = appState.pendingIncomingFrameNotification {
                    VStack {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                            Text(notification)
                                .font(AppTheme.Typography.subheadlineBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            
                            Button {
                                appState.switchToPendingGroup()
                            } label: {
                                Text("Показать")
                                    .font(AppTheme.Typography.captionBold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.Colors.accent)
                                    .foregroundStyle(Color.white)
                                    .clipShape(Capsule())
                            }
                            
                            Button {
                                appState.dismissPendingNotification()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(AppTheme.Typography.captionBold)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            }
                            .accessibilityLabel("Закрыть уведомление")
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, 6)
                        .glassPill(shadowRadius: 10, shadowY: 4)
                        .padding(.top, 45)
                        
                        Spacer()
                    }
                }
                
                // Плавающая панель массовых действий при множественном выборе
                if appState.photoSource == .session && appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
                    VStack {
                        Spacer()
                        BatchActionBarView(appState: appState)
                            .padding(.bottom, AppTheme.Spacing.md)
                    }
                }
                
                // Невидимые триггеры клавиатурных команд iPad
                if appState.photoSource == .session { keyboardShortcutsView }
            }
        }
        .onChange(of: appState.photoSource) { source in
            if source == .camera { appState.exitViewer() }
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isShowingConnectionSheet }, set: { appState.isShowingConnectionSheet = $0 })) {
            ConnectionSheetView(appState: appState)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isShowingSessionSheet }, set: { appState.isShowingSessionSheet = $0 })) {
            SessionManagementSheetView(appState: appState)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isShowingFilterSheet }, set: { appState.isShowingFilterSheet = $0 })) {
            GalleryFilterSheetView(appState: appState)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isQueuePresented }, set: { appState.isQueuePresented = $0 })) {
            TransferQueueView(appState: appState)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isWizardPresented }, set: { appState.isWizardPresented = $0 })) {
            ConnectionWizardView(appState: appState)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isMatrixPresented }, set: { appState.isMatrixPresented = $0 })) {
            CompatibilityMatrixView()
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isComparePresented }, set: { appState.isComparePresented = $0 })) {
            CompareView(appState: appState, initialGroupA: appState.selectedGroup, initialGroupB: appState.compareCandidateGroup)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isExportSheetPresented }, set: { appState.isExportSheetPresented = $0 })) {
            ExportSheetView(appState: appState, groups: appState.exportTargetGroups)
        }
        .sheet(isPresented: Binding(get: { showsSheets && appState.isClientControlSheetPresented }, set: { appState.isClientControlSheetPresented = $0 })) {
            ClientMonitorControlSheet(monitorManager: appState.clientMonitorManager, appState: appState)
        }
        .fullScreenCover(isPresented: Binding(get: { showsSheets && appState.isClientMonitorPresented }, set: { appState.isClientMonitorPresented = $0 })) {
            ClientMonitorView(monitorManager: appState.clientMonitorManager, appState: appState)
        }
        .onChange(of: scenePhase) { newPhase in
            if showsSheets {
                appState.handleScenePhaseChange(newPhase)
            }
        }
        .alert("Очистить все снимки?", isPresented: $isShowingClearAlert) {
            Button("Очистить", role: .destructive) {
                appState.clearGallery()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
    
    // MARK: - Широкая компоновка (iPad, ландшафтный режим)
    
    @ViewBuilder
    private func wideContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            topHUD
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.xs)
                .padding(.bottom, AppTheme.Spacing.xs)
            
            if let activeJob = appState.activeTransferJob {
                compactTransferBar(job: activeJob)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.xs)
            }
            
            if let banner = appState.mainScreenState.compactBanner {
                compactBannerView(banner)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.xs)
            }
            
            if let emptyState = appState.mainScreenState.emptyState {
                mainScreenEmptyContentView(emptyState)
            } else {
                switch appState.viewMode {
                case .list:
                    if appState.mainScreenState.hasPhotos && !appState.mainScreenState.areAllPhotosFilteredOut {
                        galleryControlsBar
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.bottom, AppTheme.Spacing.xs)
                    }
                    Divider()
                        .padding(.horizontal, AppTheme.Spacing.md)
                    PhotoListView(
                        groups: appState.filteredGroups,
                        selectedGroup: appState.selectedGroup,
                        isSelectionMode: appState.isSelectionMode,
                        selectedGroupIDs: appState.selectedGroupIDs,
                        onToggleSelect: { appState.toggleSelectGroup($0) },
                        onSelect: { group in appState.selectedGroup = group }
                    )
                case .table:
                    if appState.mainScreenState.hasPhotos && !appState.mainScreenState.areAllPhotosFilteredOut {
                        galleryControlsBar
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.bottom, AppTheme.Spacing.xs)
                    }
                    Divider()
                        .padding(.horizontal, AppTheme.Spacing.md)
                    PhotoTableView(
                        groups: appState.filteredGroups,
                        selectedGroup: appState.selectedGroup,
                        isSelectionMode: appState.isSelectionMode,
                        selectedGroupIDs: appState.selectedGroupIDs,
                        onToggleSelect: { appState.toggleSelectGroup($0) },
                        onSelect: { group in appState.selectedGroup = group }
                    )
                case .icons, .viewer:
                    // Широкое окно по макету: крупное фото слева и сетка миниатюр рядом справа
                    HStack(spacing: 0) {
                        // Левая панель: большая фотография с компактными действиями под ней
                        let currentGroup = appState.selectedGroup ?? appState.filteredGroups.first
                        if let currentGroup {
                            PhotoDetailView(
                                group: currentGroup,
                                appState: appState,
                                showsTopHUD: false
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ZStack {
                                AppTheme.Colors.photoBackground
                                Text("Выберите кадр для просмотра")
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        Divider()
                        
                        // Правая панель: управление («Снимки · 24», фильтры) и миниатюры рядом
                        VStack(spacing: 0) {
                            galleryControlsBar
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .padding(.vertical, AppTheme.Spacing.xs)
                            
                            Divider()
                            
                            IconsGridView(
                                groups: appState.filteredGroups,
                                selectedGroup: appState.selectedGroup,
                                isSelectionMode: appState.isSelectionMode,
                                selectedGroupIDs: appState.selectedGroupIDs,
                                onToggleSelect: { appState.toggleSelectGroup($0) },
                                onSelect: { group in
                                    appState.selectedGroup = group
                                }
                            )
                        }
                        .frame(width: min(400, max(300, geometry.size.width * 0.38)))
                        .background(AppTheme.Colors.surfacePrimary.opacity(0.6))
                    }
                }
            }
        }
    }
    
    // MARK: - Узкая компоновка (iPhone, узкий Split View)
    
    @ViewBuilder
    private func narrowContentView(geometry: GeometryProxy) -> some View {
        if appState.viewMode == .viewer {
            viewerView
        } else {
            VStack(spacing: 0) {
                topHUD
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.xs)
                    .padding(.bottom, AppTheme.Spacing.xs)
                
                if let activeJob = appState.activeTransferJob {
                    compactTransferBar(job: activeJob)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.bottom, AppTheme.Spacing.xs)
                }
                
                if let banner = appState.mainScreenState.compactBanner {
                    compactBannerView(banner)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.bottom, AppTheme.Spacing.xs)
                }
                
                if appState.mainScreenState.hasPhotos && !appState.mainScreenState.areAllPhotosFilteredOut {
                    galleryControlsBar
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.bottom, AppTheme.Spacing.xs)
                }
                
                Divider()
                    .padding(.horizontal, AppTheme.Spacing.md)
                
                mainContentArea
            }
        }
    }
    
    // MARK: - 1. Top HUD
    
    private var topHUD: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            // Основная строка заголовка: название сессии и статус камеры слева, действия справа
            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                // Название сессии + статус камеры (в 2 аккуратные строки слева)
                Button {
                    appState.isShowingSessionSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(appState.currentSession?.name ?? "Сессия")
                                .font(AppTheme.Typography.title3.weight(.heavy))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                        
                        ConnectionStatusView(
                            status: connectionStatusState,
                            title: appState.connectionStatusTitle,
                            shortTitle: appState.shortConnectionStatusTitle,
                            iconName: connectionStatusIcon,
                            style: .inline,
                            action: {
                                appState.isShowingConnectionSheet = true
                            }
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сессия: \(appState.currentSession?.name ?? "Сессия"), \(appState.connectionStatusTitle)")
                .accessibilityHint("Нажмите для управления сессиями")
                
                Spacer(minLength: AppTheme.Spacing.xs)
                
                // Правый блок: кнопка «Импорт» и меню дополнительных действий •••
                HStack(spacing: AppTheme.Spacing.xs + 2) {
                    PrimaryImportButton(
                        isReadingCatalog: appState.usbConnected && !appState.currentUSBManager.isCatalogReady,
                        unimportedCount: appState.currentUSBManager.catalogFiles.filter { $0.status == .notImported }.count,
                        action: {
                            if appState.usbConnected {
                                appState.isUSBBrowserPresented = true
                            } else {
                                appState.isShowingConnectionSheet = true
                            }
                        }
                    )
                    
                    moreActionsMenu
                }
            }
            
            // Вторая строка: плашка карты памяти камеры по макету (если USB подключен и каталог готов)
            if appState.usbConnected && appState.currentUSBManager.isCatalogReady && !appState.currentUSBManager.catalogFiles.isEmpty {
                let totalFiles = appState.currentUSBManager.catalogFiles.count
                let unimportedFiles = appState.currentUSBManager.catalogFiles.filter { $0.status == .notImported }.count
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                    
                    Text(unimportedFiles > 0 ? "На карте \(totalFiles) файлов (новых: \(unimportedFiles))" : "На карте \(totalFiles) файлов")
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        appState.isUSBBrowserPresented = true
                    } label: {
                        Text("Выбрать")
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.accent)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(AppTheme.Colors.accent.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Выбрать снимки с карты памяти камеры")
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 6)
                .glassPill()
            }
        }
    }
    
    // MARK: - Меню дополнительных действий
    
    private var moreActionsMenu: some View {
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
                appState.isShowingConnectionSheet = true
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                .glassSurface(shape: Circle())
        }
        .accessibilityLabel("Дополнительные действия")
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
    
    // MARK: - 2. Панель управления галереей над сеткой
    
    @ViewBuilder
    private var galleryControlsBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Заголовок с числом кадров по макету («Снимки · 24»)
            HStack(spacing: 4) {
                Text("Снимки · \(appState.filteredGroups.count)")
                    .font(AppTheme.Typography.headline.weight(.heavy))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                if appState.filteredGroups.count != appState.totalFramesCount {
                    Text("из \(appState.totalFramesCount)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                
                if appState.pairedCount > 0 {
                    Text("• \(appState.pairedCount) пар")
                        .font(AppTheme.Typography.caption2Bold)
                        .foregroundStyle(AppTheme.Colors.statusGreen)
                }
            }
            
            Spacer()
            
            // Меню вида (Сетка, Список, Таблица) и сортировки
            Menu {
                Section("Режим отображения") {
                    Picker("Режим", selection: $appState.viewMode) {
                        Label("Сетка", systemImage: "square.grid.2x2").tag(ViewMode.icons)
                        Label("Список", systemImage: "list.bullet").tag(ViewMode.list)
                        Label("Таблица", systemImage: "tablecells").tag(ViewMode.table)
                    }
                }
                
                Section("Сортировка") {
                    Picker("Порядок", selection: Binding(
                        get: { appState.sortOrder },
                        set: { appState.setSortOrder($0) }
                    )) {
                        ForEach(SortOrderOption.allCases) { opt in
                            Label(opt.title, systemImage: opt.iconName).tag(opt)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                    .glassSurface(shape: Circle())
            }
            .accessibilityLabel("Вид и сортировка")
            
            // Кнопка панели «Фильтры» со счетчиком
            Button {
                appState.isShowingFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .bold))
                    
                    Text("Фильтры")
                        .font(AppTheme.Typography.captionBold)
                    
                    if appState.activeFilterCount > 0 {
                        Text("\(appState.activeFilterCount)")
                            .font(AppTheme.Typography.caption2Bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.Colors.accent)
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(appState.hasActiveFilters ? AppTheme.Colors.accent : AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.sm + 2)
                .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                .glassPill()
            }
            .accessibilityLabel("Фильтры" + (appState.activeFilterCount > 0 ? ", активно: \(appState.activeFilterCount)" : ""))
            
            // Кнопка быстрого сброса фильтров
            if appState.hasActiveFilters {
                Button {
                    appState.resetFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сбросить все фильтры")
            }
            
            // Кнопка режима множественного выбора «Выбрать»
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
                        .font(.system(size: 13, weight: .bold))
                    Text(appState.isSelectionMode ? "Готово" : "Выбрать")
                        .font(AppTheme.Typography.captionBold)
                }
                .foregroundStyle(appState.isSelectionMode ? Color.white : AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.sm + 2)
                .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                .background(
                    Group {
                        if appState.isSelectionMode {
                            AppTheme.Colors.accent.clipShape(Capsule())
                        } else {
                            Color.clear
                        }
                    }
                )
                .glassPill()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.isSelectionMode ? "Завершить выбор" : "Включить выбор кадров")
        }
    }
    
    // MARK: - 3. Основная область контента (узкий экран)
    
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
    
    // MARK: - 4. Режим детального просмотра (Viewer - узкий экран)
    
    private var viewerView: some View {
        VStack(spacing: 0) {
            // Верхняя навигационная плашка режима «Просмотр» по макету
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.exitViewer()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Снимки")
                            .font(AppTheme.Typography.subheadlineBold)
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Вернуться к сетке снимков")
                
                Spacer()
                
                Text(appState.selectedGroup?.baseName ?? appState.selectedFile?.filename ?? "Снимок")
                    .font(AppTheme.Typography.headline.weight(.heavy))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                moreActionsMenu
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.xs)
            .padding(.bottom, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.surfacePrimary.opacity(0.85))
            
            // Основная область кадра с зумом и инспектором
            if let currentGroup = appState.selectedGroup ?? appState.filteredGroups.first {
                PhotoDetailView(group: currentGroup, appState: appState, showsTopHUD: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let currentFile = appState.selectedFile ?? appState.filteredFiles.first {
                PhotoDetailView(file: currentFile, appState: appState, showsTopHUD: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            bottomFilmstrip
        }
    }
    
    // MARK: - Bottom Filmstrip (Горизонтальная лента миниатюр)
    
    private var bottomFilmstrip: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            HStack {
                Text("\(appState.filteredGroups.count) из \(appState.totalFramesCount) кадров")
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                
                if appState.pairedCount > 0 {
                    Text("• \(appState.pairedCount) пар")
                        .font(AppTheme.Typography.caption2Bold)
                        .foregroundStyle(AppTheme.Colors.statusGreen)
                }
                
                Spacer()
                
                // Кнопка возврата к сетке
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.exitViewer()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("Сетка")
                    }
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                }
                .buttonStyle(.plain)
                .padding(.trailing, AppTheme.Spacing.sm)
                
                // Переключатель «Автопросмотр»
                Button {
                    appState.isAutoScrollEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isAutoScrollEnabled ? "bolt.circle.fill" : "bolt.circle")
                        Text("Автопросмотр")
                    }
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(appState.isAutoScrollEnabled ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                    .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AppTheme.Spacing.xs + 2) {
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
                    .padding(.horizontal, AppTheme.Spacing.md)
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
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(AppTheme.Colors.surfacePrimary.opacity(0.95))
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
    
    // MARK: - Compact Banner
    
    @ViewBuilder
    private func compactBannerView(_ banner: MainScreenCompactBanner) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: banner.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(bannerIconColor(for: banner.style))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(AppTheme.Typography.captionBold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                if let msg = banner.message {
                    Text(msg)
                        .font(AppTheme.Typography.caption2)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            
            if banner.showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppTheme.Colors.accent)
            }
            
            Spacer()
            
            if let action = banner.action {
                Button {
                    appState.handleMainScreenAction(action.type)
                } label: {
                    if let icon = action.systemImage {
                        Label(action.title, systemImage: icon)
                            .font(AppTheme.Typography.captionBold)
                    } else {
                        Text(action.title)
                            .font(AppTheme.Typography.captionBold)
                    }
                }
                .buttonStyle(.appPrimary)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(bannerBackgroundColor(for: banner.style))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
    
    private func bannerIconColor(for style: MainScreenCompactBanner.Style) -> Color {
        switch style {
        case .error: return AppTheme.Colors.statusRed
        case .warning: return AppTheme.Colors.statusOrange
        case .info: return AppTheme.Colors.accent
        case .success: return AppTheme.Colors.statusGreen
        }
    }
    
    private func bannerBackgroundColor(for style: MainScreenCompactBanner.Style) -> Color {
        switch style {
        case .error: return AppTheme.Colors.statusRed.opacity(0.18)
        case .warning: return AppTheme.Colors.statusOrange.opacity(0.18)
        case .info: return AppTheme.Colors.accent.opacity(0.15)
        case .success: return AppTheme.Colors.statusGreen.opacity(0.15)
        }
    }
    
    // MARK: - 5. Пустые состояния в стиле Liquid Glass
    
    @ViewBuilder
    private func mainScreenEmptyContentView(_ state: MainScreenEmptyState) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.Spacing.lg) {
                Spacer(minLength: AppTheme.Spacing.md)
                
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.surfacePrimary)
                        .frame(width: 104, height: 104)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
                    
                    Image(systemName: state.systemImage)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(emptyStateIconColor(for: state.kind))
                }
                
                VStack(spacing: AppTheme.Spacing.xs) {
                    Text(state.title)
                        .font(AppTheme.Typography.title2.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text(state.description)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.md)
                    
                    if state.showsProgress {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(AppTheme.Colors.accent)
                            .padding(.top, AppTheme.Spacing.xs)
                    }
                }
                
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        if let secondary = state.secondaryAction {
                            emptyStateButton(secondary, isPrimary: false)
                        }
                        if let primary = state.primaryAction {
                            emptyStateButton(primary, isPrimary: true)
                        }
                    }
                    VStack(spacing: AppTheme.Spacing.sm) {
                        if let primary = state.primaryAction {
                            emptyStateButton(primary, isPrimary: true)
                        }
                        if let secondary = state.secondaryAction {
                            emptyStateButton(secondary, isPrimary: false)
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.xs)
                
                Spacer(minLength: AppTheme.Spacing.md)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }
    
    @ViewBuilder
    private func emptyStateButton(_ action: MainScreenAction, isPrimary: Bool) -> some View {
        Button {
            appState.handleMainScreenAction(action.type)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs + 2) {
                if let icon = action.systemImage {
                    Image(systemName: icon)
                }
                Text(action.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .modifier(EmptyStateButtonModifier(isPrimary: isPrimary))
    }
    
    private struct EmptyStateButtonModifier: ViewModifier {
        let isPrimary: Bool
        func body(content: Content) -> some View {
            if isPrimary {
                content.buttonStyle(.appPrimary)
            } else {
                content.buttonStyle(.appSecondaryGlass)
            }
        }
    }
    
    private func emptyStateIconColor(for kind: MainScreenEmptyState.Kind) -> Color {
        switch kind {
        case .error:
            return AppTheme.Colors.statusRed
        case .cardReady:
            return AppTheme.Colors.statusGreen
        case .connecting, .readingCard, .transferring:
            return AppTheme.Colors.statusOrange
        case .allFilteredOut, .cardEmptyOrNoMatchingFiles:
            return AppTheme.Colors.accent
        case .disconnected, .ftpWaiting:
            return AppTheme.Colors.textSecondary
        }
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
        if appState.photoSource == .session && appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
            appState.batchSetRating(rating)
        } else if let sel = appState.selectedGroup {
            appState.setRating(rating, for: sel)
        }
    }
    
    private func applyPickStatus(_ status: PickStatus) {
        if appState.photoSource == .session && appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
            appState.batchSetPickStatus(status)
        } else if let sel = appState.selectedGroup {
            appState.setPickStatus(status, for: sel)
        }
    }
}
