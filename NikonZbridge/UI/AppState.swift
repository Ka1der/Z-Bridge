import Foundation
import SwiftUI
import Combine

public enum ViewMode: String, CaseIterable, Identifiable {
    case viewer = "Просмотр"
    case icons = "Иконки"
    case list = "Список"
    case table = "Таблица"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .viewer: return "photo.fill"
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .table: return "tablecells"
        }
    }
}

/// Предпочтительный формат для импорта (настройки загрузки с камеры, отделены от фильтров галереи)
public enum ImportFormatPreference: String, CaseIterable, Identifiable, Sendable {
    case allFormats = "RAW и JPEG/HEIF"
    case rawOnly = "Только RAW"
    case companionOnly = "Только JPEG/HEIF"
    
    public var id: String { rawValue }
}

/// 5 профессиональных групп настроек приложения
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case connection = "Подключение"
    case importTab = "Импорт"
    case sessions = "Сессии и хранение"
    case clientScreen = "Клиентский экран"
    case diagnostics = "Диагностика"
    
    public var id: String { rawValue }
    
    public var title: String { rawValue }
    
    public var subtitle: String {
        switch self {
        case .connection:
            return "Кабель USB-C, Wi-Fi, FTP-сервер и мастер"
        case .importTab:
            return "Live tethering, автозагрузка с карты и форматы"
        case .sessions:
            return "Старт с пустой сессии, метаданные и кэш превью"
        case .clientScreen:
            return "Внешний монитор, HDMI, удержание Hold и знак"
        case .diagnostics:
            return "Пути к файлам, SQLite WAL, сверка и DiskGuard"
        }
    }
    
    public var iconName: String {
        switch self {
        case .connection: return "cable.connector.horizontal"
        case .importTab: return "arrow.down.circle"
        case .sessions: return "folder.badge.gearshape"
        case .clientScreen: return "tv"
        case .diagnostics: return "stethoscope"
        }
    }
    
    public var systemColor: Color {
        switch self {
        case .connection: return .blue
        case .importTab: return .green
        case .sessions: return .orange
        case .clientScreen: return .purple
        case .diagnostics: return .teal
        }
    }
}

/// Порядок сортировки кадров в галерее
public enum SortOrderOption: String, CaseIterable, Identifiable, Sendable {
    case dateDesc = "Сначала новые"
    case dateAsc = "Сначала старые"
    case nameAsc = "Имя (А-Я)"
    case nameDesc = "Имя (Я-А)"
    case ratingDesc = "По рейтингу"
    case sizeDesc = "По размеру"
    
    public var id: String { rawValue }
    public var title: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dateDesc, .dateAsc: return "calendar"
        case .nameAsc, .nameDesc: return "textformat"
        case .ratingDesc: return "star.fill"
        case .sizeDesc: return "internaldrive"
        }
    }
}

/// Фильтрация по звездному рейтингу
public enum RatingFilterOption: String, CaseIterable, Identifiable, Sendable {
    case all = "Все звёзды"
    case stars1Plus = "★ 1+"
    case stars2Plus = "★ 2+"
    case stars3Plus = "★ 3+"
    case stars4Plus = "★ 4+"
    case stars5Only = "★ 5"
    case unrated = "Без оценки"
    
    public var id: String { rawValue }
    public var title: String { rawValue }
    
    public func matches(rating: Int) -> Bool {
        switch self {
        case .all: return true
        case .stars1Plus: return rating >= 1
        case .stars2Plus: return rating >= 2
        case .stars3Plus: return rating >= 3
        case .stars4Plus: return rating >= 4
        case .stars5Only: return rating == 5
        case .unrated: return rating == 0
        }
    }
}

/// Фильтрация по флагу отбора (Pick / Reject)
public enum PickFilterOption: String, CaseIterable, Identifiable, Sendable {
    case all = "Все флаги"
    case picked = "Только отобранные"
    case unflagged = "Без флага"
    case rejected = "Отклонённые"
    case hideRejected = "Скрыть отклонённые"
    
    public var id: String { rawValue }
    public var title: String { rawValue }
    
    public func matches(status: PickStatus) -> Bool {
        switch self {
        case .all: return true
        case .picked: return status == .picked
        case .unflagged: return status == .unflagged
        case .rejected: return status == .rejected
        case .hideRejected: return status != .rejected
        }
    }
}

/// 3 основных раздела адаптивного каркаса приложения (Liquid Glass)
public enum PhotoSource: String, CaseIterable, Identifiable {
    case session = "В сессии"
    case camera = "На камере"
    public var id: String { rawValue }
}

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case photos = "Снимки"
    case camera = "Камера"
    case sessions = "Сессии"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .photos: return "photo.on.rectangle"
        case .camera: return "camera"
        case .sessions: return "square.stack.3d.up"
        }
    }
    
    public var selectedIconName: String {
        switch self {
        case .photos: return "photo.fill"
        case .camera: return "camera.fill"
        case .sessions: return "square.stack.3d.up.fill"
        }
    }
}

/// Модель состояния для SwiftUI, отвязанная от деталей транспортов и хранилища
@MainActor
public final class AppState: ObservableObject {
    // Навигация каркаса и централизованные модальные окна
    @Published public var selectedSection: AppSection = .photos
    @Published public var isSidebarCollapsed: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isShowingConnectionSheet: Bool = false
    @Published public var isShowingSessionSheet: Bool = false
    @Published public var isShowingFilterSheet: Bool = false
    
    public func toggleSidebar() {
        isSidebarCollapsed.toggle()
    }
    
    // Состояние сети и сервера
    @Published public var serverState: FTPServerState = .stopped
    public var isServerRunning: Bool {
        if case .running = serverState { return true }
        return false
    }
    @Published public var activeIPs: [NetworkAddressInfo] = []
    @Published public var connectedClients: Int = 0
    @Published public var usbConnected: Bool = false
    @Published public var usbCameraName: String?
    @Published public var usbConnectionState: USBCameraConnectionState = .disconnected
    @Published public var photoSource: PhotoSource = .session
    @Published public var selectedCameraFileIDs: Set<String> = []
    @Published public var cameraFormatFilter: CameraFileFormatFilter = .all

    // Совместимость существующих действий: открываем карту в основном разделе.
    public var isUSBBrowserPresented: Bool {
        get { selectedSection == .photos && photoSource == .camera }
        set {
            if newValue {
                exitViewer()
                photoSource = .camera
                selectedSection = .photos
            } else {
                photoSource = .session
            }
        }
    }
    @Published public var isUSBAutoDownloadNewShotsEnabled: Bool = true
    @Published public var isUSBAutoDownloadCardOnConnectEnabled: Bool = false
    
    // Настройки FTP и безопасность (Этап 5)
    @Published public var isFTPReceivingEnabled: Bool
    @Published public var isFTPAutoStartEnabled: Bool
    @Published public var resumeLastSessionOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(resumeLastSessionOnLaunch, forKey: "nikon_resume_last_session")
        }
    }
    private var isStartupReady = false
    @Published public var ftpUsername: String = "nikon"
    @Published public var ftpPassword: String = ""
    
    // Очередь и жизненный цикл (Этап 6)
    @Published public var isQueuePresented: Bool = false
    public var lifecycleManager = LifecycleManager.shared
    public var diagnosticLogger = DiagnosticLogger.shared
    
    // Мастер подключения и совместимость (Этап 7)
    @Published public var isWizardPresented: Bool = false
    @Published public var isMatrixPresented: Bool = false
    @Published public var wizardSelectedModel: NikonCameraModel = .z8
    @Published public var wizardSelectedTransport: NikonConnectionTransport = .directUSB
    
    public var currentSessionDirectory: URL {
        currentSession?.folderURL ?? StorageManager.shared.baseStorageURL
    }
    
    // Разделение прогресса: сохранённые оригиналы vs текущая попытка
    public var savedOriginalsBytes: Int64 {
        receivedFiles.reduce(0) { $0 + $1.fileSize }
    }
    
    public var currentAttemptBytes: Int64 {
        activeTransferJob?.transferredBytes ?? 0
    }
    
    public var activeTransferJob: TransferJob? {
        activeJobs.first { $0.state.isInProgress || $0.state.isVerifying }
    }
    
    public var pendingJobs: [TransferJob] {
        activeJobs.filter { $0.state.isPending }
    }
    
    public var failedJobs: [TransferJob] {
        activeJobs.filter { $0.state.isFailed }
    }
    
    public var completedJobs: [TransferJob] {
        activeJobs.filter { $0.state.isCompleted }
    }
    
    public var activeQueueCount: Int {
        activeJobs.filter { $0.state.isPending || $0.state.isInProgress || $0.state.isVerifying }.count
    }
    
    public var currentETASeconds: Double? {
        guard let job = activeTransferJob,
              let total = job.totalBytes,
              total > job.transferredBytes,
              currentTransferSpeedMBs > 0.05 else {
            return nil
        }
        let remainingMB = Double(total - job.transferredBytes) / 1_048_576.0
        return remainingMB / currentTransferSpeedMBs
    }
    
    // Доменные сущности (Этап 1: Единая модель импорта)
    @Published public var currentSession: CaptureSession?
    @Published public var availableSessions: [CaptureSession] = []
    @Published public var connectedSources: [CameraSource] = []
    @Published public var captureGroups: [CaptureGroup] = []
    @Published public var selectedGroup: CaptureGroup? {
        didSet {
            if oldValue?.id != selectedGroup?.id {
                viewerZoom = 1.0
                viewerPanOffset = .zero
                isUserInspecting = false
            }
        }
    }
    @Published public var activeJobs: [TransferJob] = []
    
    // Состояние полученных файлов и галереи (для SwiftUI представлений)
    @Published public var receivedFiles: [IngestedFile] = []
    @Published public var selectedFile: IngestedFile?
    @Published public var currentTransferSpeedMBs: Double = 0.0
    @Published public var totalBytesTransferred: Int64 = 0
    @Published public var isAutoScrollEnabled: Bool = true
    
    // НАСТРОЙКИ ИМПОРТА (НЕ влияют на фильтрацию отображения в галерее)
    @Published public var usbImportMode: USBImportMode = .onlyNew
    @Published public var importFormatPreference: ImportFormatPreference = .allFormats
    
    // РЕЖИМ ВНЕШНЕГО ВИДА И ФИЛЬТРЫ ОТОБРАЖЕНИЯ ГАЛЕРЕИ
    @Published public var viewMode: ViewMode = .icons {
        didSet {
            if oldValue == .viewer && viewMode != .viewer {
                isUserInspecting = false
                viewerZoom = 1.0
                viewerPanOffset = .zero
                pendingIncomingFrameNotification = nil
            }
        }
    }
    @Published public var showRAW: Bool = true
    @Published public var showJPG: Bool = true
    @Published public var showHEIF: Bool = true
    @Published public var onlyPaired: Bool = false
    
    /// Явный выход из режима детального просмотра кадра в галерею
    public func exitViewer() {
        viewMode = .icons
        isUserInspecting = false
        viewerZoom = 1.0
        viewerPanOffset = .zero
        pendingIncomingFrameNotification = nil
    }
    
    // ФИЛЬТРЫ И СОРТИРОВКА (Этап 9)
    @Published public var sortOrder: SortOrderOption = .dateDesc
    @Published public var ratingFilter: RatingFilterOption = .all
    @Published public var pickFilter: PickFilterOption = .all
    
    // Псевдонимы совместимости для фильтров
    public var selectedRatingFilter: RatingFilterOption {
        get { ratingFilter }
        set { ratingFilter = newValue }
    }
    public var selectedPickFilter: PickFilterOption {
        get { pickFilter }
        set { pickFilter = newValue }
    }
    
    // МНОЖЕСТВЕННЫЙ ВЫБОР И МАССОВЫЕ ДЕЙСТВИЯ (Этап 9)
    @Published public var isSelectionMode: Bool = false
    @Published public var selectedGroupIDs: Set<String> = []
    
    // ИНСПЕКЦИЯ И ПАУЗА АВТОПЕРЕКЛЮЧЕНИЯ (Этап 9)
    @Published public var isUserInspecting: Bool = false
    @Published public var pendingIncomingFrameNotification: String? = nil
    
    // Состояние зума и панорамирования в полноэкранном просмотрщике (сохраняется при смене лейаута и поворотах)
    @Published public var viewerZoom: CGFloat = 1.0
    @Published public var viewerPanOffset: CGSize = .zero
    
    // СРАВНЕНИЕ ДВУХ КАДРОВ (CompareView)
    @Published public var isComparePresented: Bool = false
    @Published public var compareCandidateGroup: CaptureGroup? = nil
    
    // ЭКСПОРТ И ВНЕШНЕЕ ХРАНИЛИЩЕ (Этап 10)
    @Published public var isExportSheetPresented: Bool = false
    @Published public var exportTargetGroups: [CaptureGroup] = []
    @Published public var currentExportJob: ExportJob? = nil
    
    // Автоматическое фоновое копирование (Live Mirror)
    @Published public var isAutoExportEnabled: Bool = false
    @Published public var autoExportDestinationURL: URL? = nil
    @Published public var autoExportBookmarkData: Data? = nil
    @Published public var autoExportFormat: ExportFormatSelection = .both
    
    // МЕТАДАННЫЕ СЕССИИ И XMP (Этап 12)
    @Published public var sessionAuthor: String = ""
    @Published public var sessionCopyright: String = ""
    @Published public var sessionComment: String = ""
    @Published public var isXMPExportEnabled: Bool = true
    @Published public var xmpNamingConvention: XMPSidecarNamingConvention = .standardBasename
    
    // РЕЖИМ КЛИЕНТСКОГО МОНИТОРА (Этап 11)
    public let clientMonitorManager = ClientMonitorManager.shared
    @Published public var isClientMonitorPresented: Bool = false
    @Published public var isClientControlSheetPresented: Bool = false
    
    public var totalFramesCount: Int {
        captureGroups.count
    }
    
    public var pairedCount: Int {
        captureGroups.filter { $0.hasBothRawAndJpeg }.count
    }
    
    public var rawCount: Int {
        captureGroups.filter { $0.rawAsset != nil }.count
    }
    
    public var jpgCount: Int {
        captureGroups.filter { $0.jpegAsset != nil && $0.jpegAsset?.format.isJPEG == true }.count
    }
    
    public var heifCount: Int {
        captureGroups.filter { $0.heifAsset != nil || ($0.jpegAsset?.format.isHEIF == true) }.count
    }
    
    /// Кадры, видимые в галерее с учётом активных фильтров форматов, звездного рейтинга, статусов отбора и сортировки
    public var filteredGroups: [CaptureGroup] {
        let filtered = captureGroups.filter { group in
            if onlyPaired && !group.hasBothRawAndJpeg {
                return false
            }
            let hasRaw = group.rawAsset != nil
            let hasJpg = group.jpegAsset != nil && group.jpegAsset?.format.isJPEG == true
            let hasHeif = group.heifAsset != nil || (group.jpegAsset?.format.isHEIF == true)
            
            let matchesFormat: Bool
            if showRAW && hasRaw {
                matchesFormat = true
            } else if showJPG && hasJpg {
                matchesFormat = true
            } else if showHEIF && hasHeif {
                matchesFormat = true
            } else if !hasRaw && !hasJpg && !hasHeif && !group.otherAssets.isEmpty {
                matchesFormat = true
            } else {
                matchesFormat = false
            }
            guard matchesFormat else { return false }
            
            // Фильтр по рейтингу (звёздам)
            guard ratingFilter.matches(rating: group.rating) else { return false }
            
            // Фильтр по флагу отбора
            guard pickFilter.matches(status: group.pickStatus) else { return false }
            
            return true
        }
        
        switch sortOrder {
        case .dateDesc:
            return filtered.sorted(by: { ($0.captureDate ?? Date.distantPast) > ($1.captureDate ?? Date.distantPast) })
        case .dateAsc:
            return filtered.sorted(by: { ($0.captureDate ?? Date.distantPast) < ($1.captureDate ?? Date.distantPast) })
        case .nameAsc:
            return filtered.sorted(by: { $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending })
        case .nameDesc:
            return filtered.sorted(by: { $0.baseName.localizedStandardCompare($1.baseName) == .orderedDescending })
        case .ratingDesc:
            return filtered.sorted(by: {
                if $0.rating != $1.rating {
                    return $0.rating > $1.rating
                }
                return ($0.captureDate ?? Date.distantPast) > ($1.captureDate ?? Date.distantPast)
            })
        case .sizeDesc:
            return filtered.sorted(by: { $0.totalSize > $1.totalSize })
        }
    }
    
    public var filteredFiles: [IngestedFile] {
        receivedFiles.filter { file in
            let matchesFormat = (showRAW && file.isRAW) || (showJPG && !file.isRAW)
            guard matchesFormat else { return false }
            guard ratingFilter.matches(rating: file.rating) else { return false }
            guard pickFilter.matches(status: file.pickStatus) else { return false }
            return true
        }
    }
    
    public func toggleRAW() {
        showRAW.toggle()
        if !showRAW && !showJPG && !showHEIF {
            showRAW = true
        }
        updateSelectedAfterFilterChange()
    }
    
    public func toggleJPG() {
        showJPG.toggle()
        if !showRAW && !showJPG && !showHEIF {
            showJPG = true
        }
        updateSelectedAfterFilterChange()
    }
    
    public func toggleHEIF() {
        showHEIF.toggle()
        if !showRAW && !showJPG && !showHEIF {
            showHEIF = true
        }
        updateSelectedAfterFilterChange()
    }
    
    public func toggleOnlyPaired() {
        onlyPaired.toggle()
        updateSelectedAfterFilterChange()
    }
    
    public func setSortOrder(_ order: SortOrderOption) {
        self.sortOrder = order
        updateSelectedAfterFilterChange()
    }
    
    public func setRatingFilter(_ filter: RatingFilterOption) {
        self.ratingFilter = filter
        updateSelectedAfterFilterChange()
    }
    
    public func setPickFilter(_ filter: PickFilterOption) {
        self.pickFilter = filter
        updateSelectedAfterFilterChange()
    }
    
    /// Проверка, активны ли какие-либо фильтры отображения
    public var hasActiveFilters: Bool {
        !showRAW || !showJPG || !showHEIF || onlyPaired || ratingFilter != .all || pickFilter != .all
    }
    
    /// Количество активных критериев фильтрации (для отображения бейджа на панели)
    public var activeFilterCount: Int {
        var count = 0
        if !showRAW || !showJPG || !showHEIF {
            count += 1
        }
        if onlyPaired {
            count += 1
        }
        if ratingFilter != .all {
            count += 1
        }
        if pickFilter != .all {
            count += 1
        }
        return count
    }
    
    /// Полный сброс всех фильтров галереи к значениям по умолчанию
    public func resetFilters() {
        showRAW = true
        showJPG = true
        showHEIF = true
        onlyPaired = false
        ratingFilter = .all
        pickFilter = .all
        updateSelectedAfterFilterChange()
    }
    
    /// Вычисленное состояние главного экрана для отображения ситуации и действий
    public var mainScreenState: MainScreenState {
        let unimportedCount = currentUSBManager.catalogFiles.filter { $0.status == .notImported }.count
        return MainScreenPresentationModel.resolve(
            totalGalleryCount: totalFramesCount,
            filteredGalleryCount: filteredGroups.count,
            hasActiveFilters: hasActiveFilters,
            usbConnectionState: usbConnectionState,
            isCatalogReady: currentUSBManager.isCatalogReady,
            catalogTotalCount: currentUSBManager.catalogFiles.count,
            catalogUnimportedCount: unimportedCount,
            isDownloading: currentUSBManager.isDownloading,
            activeTransferCount: currentUSBManager.activeTransferCount,
            pendingQueueCount: currentUSBManager.pendingQueueCount,
            transferSpeedMBs: nil,
            isFTPServerRunning: isServerRunning,
            ftpClientCount: connectedClients,
            ftpServerIP: primaryIP?.ipAddress,
            ftpServerPort: serverPort,
            isFTPReceivingEnabled: isFTPReceivingEnabled
        )
    }
    
    /// Обработка действий пользователя из пустого состояния или компактного баннера
    public func handleMainScreenAction(_ action: MainScreenActionType) {
        switch action {
        case .connectCamera:
            self.isWizardPresented = true
        case .openConnectionGuide:
            self.isWizardPresented = true
        case .retryConnection:
            currentUSBManager.start()
        case .importAllFromCard:
            Task {
                await currentUSBManager.importAllUnimported()
            }
        case .selectCardFiles:
            self.isUSBBrowserPresented = true
        case .refreshCard:
            Task {
                await currentUSBManager.refreshCatalog()
            }
        case .viewTransferQueue:
            self.isQueuePresented = true
        case .resetFilters:
            resetFilters()
        }
    }
    
    public func updateSelectedAfterFilterChange() {
        if let current = selectedGroup {
            if !filteredGroups.contains(where: { $0.id == current.id }) {
                selectedGroup = filteredGroups.first
            }
        } else {
            selectedGroup = filteredGroups.first
        }
        
        if let curFile = selectedFile {
            if !filteredFiles.contains(where: { $0.id == curFile.id }) {
                selectedFile = filteredFiles.first
            }
        } else {
            selectedFile = filteredFiles.first
        }
    }
    
    public func handleCaptureGroupUpdated(_ group: CaptureGroup) {
        let isExisting: Bool
        if let idx = captureGroups.firstIndex(where: { $0.id == group.id || $0.canAccept(asset: group.primaryAsset ?? MediaAsset(sessionID: group.sessionID, filename: group.baseName, fileURL: URL(fileURLWithPath: ""), format: .jpeg, fileSize: 0)) }) {
            captureGroups[idx] = group
            if selectedGroup?.id == group.id {
                selectedGroup = group
            }
            isExisting = true
        } else {
            captureGroups.insert(group, at: 0)
            isExisting = false
        }
        
        if !isExisting {
            clientMonitorManager.handleIncomingGroup(group)
            if isUserInspecting {
                // Пользователь рассматривает кадр: не сбиваем зум и фокус, показываем уведомление
                pendingIncomingFrameNotification = "Новый кадр: \(group.baseName)"
            } else {
                if isAutoScrollEnabled || selectedGroup == nil {
                    selectedGroup = group
                }
            }
        } else {
            clientMonitorManager.handleGroupUpdated(group)
        }
        updateSelectedAfterFilterChange()
    }
    
    public func handleIngestedFile(_ file: IngestedFile) {
        let isNew = !receivedFiles.contains(where: { $0.id == file.id })
        if isNew {
            receivedFiles.insert(file, at: 0)
        }
        let matches = (showRAW && file.isRAW) || (showJPG && !file.isRAW)
        if matches && isNew && !isUserInspecting {
            if isAutoScrollEnabled || selectedFile == nil {
                selectedFile = file
            }
        }
    }
    
    public func dismissPendingNotification() {
        pendingIncomingFrameNotification = nil
    }
    
    public func switchToPendingGroup() {
        if let first = captureGroups.first {
            selectedGroup = first
            isUserInspecting = false
            pendingIncomingFrameNotification = nil
        }
    }
    
    public func selectNextGroup() {
        let list = filteredGroups
        guard !list.isEmpty else { return }
        if let current = selectedGroup, let idx = list.firstIndex(where: { $0.id == current.id }), idx + 1 < list.count {
            selectedGroup = list[idx + 1]
        } else if selectedGroup == nil {
            selectedGroup = list.first
        }
    }
    
    public func selectPreviousGroup() {
        let list = filteredGroups
        guard !list.isEmpty else { return }
        if let current = selectedGroup, let idx = list.firstIndex(where: { $0.id == current.id }), idx > 0 {
            selectedGroup = list[idx - 1]
        } else if selectedGroup == nil {
            selectedGroup = list.first
        }
    }
    
    // MARK: - Рейтинг и отбор (Culling)
    
    public func setRating(_ rating: Int, for group: CaptureGroup) {
        let clamped = max(0, min(5, rating))
        if let idx = captureGroups.firstIndex(where: { $0.id == group.id }) {
            captureGroups[idx].setRating(clamped)
            let updated = captureGroups[idx]
            if selectedGroup?.id == group.id {
                selectedGroup = updated
            }
            clientMonitorManager.handleGroupUpdated(updated)
        }
        Task {
            await coordinator.updateRating(for: group.id, rating: clamped)
        }
    }
    
    public func setPickStatus(_ status: PickStatus, for group: CaptureGroup) {
        if let idx = captureGroups.firstIndex(where: { $0.id == group.id }) {
            captureGroups[idx].setPickStatus(status)
            let updated = captureGroups[idx]
            if selectedGroup?.id == group.id {
                selectedGroup = updated
            }
            clientMonitorManager.handleGroupUpdated(updated)
        }
        Task {
            await coordinator.updatePickStatus(for: group.id, status: status)
        }
    }
    
    public func toggleSelectGroup(id: String) {
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }
    
    public func toggleSelectGroup(_ group: CaptureGroup) {
        toggleSelectGroup(id: group.id)
    }
    
    public func selectAll() {
        selectedGroupIDs = Set(filteredGroups.map { $0.id })
    }
    
    public func clearSelection() {
        selectedGroupIDs.removeAll()
    }
    
    /// Доступно ли сравнение для выбранных кадров (строго ровно 2 кадра)
    public var canCompareSelected: Bool {
        selectedGroupIDs.count == 2
    }
    
    /// Запуск сравнения для двух выбранных кадров
    public func presentCompareForSelected() {
        guard selectedGroupIDs.count == 2 else { return }
        let ids = Array(selectedGroupIDs)
        if let g1 = filteredGroups.first(where: { $0.id == ids[0] }) ?? captureGroups.first(where: { $0.id == ids[0] }),
           let g2 = filteredGroups.first(where: { $0.id == ids[1] }) ?? captureGroups.first(where: { $0.id == ids[1] }) {
            selectedGroup = g1
            compareCandidateGroup = g2
            isComparePresented = true
        }
    }
    
    public func batchSetRating(_ rating: Int) {
        let ids = Array(selectedGroupIDs)
        guard !ids.isEmpty else { return }
        for id in ids {
            if let idx = captureGroups.firstIndex(where: { $0.id == id }) {
                captureGroups[idx].setRating(rating)
                if selectedGroup?.id == id {
                    selectedGroup = captureGroups[idx]
                }
            }
        }
        Task {
            await coordinator.batchUpdateRating(groupIDs: ids, rating: rating)
        }
    }
    
    public func batchSetPickStatus(_ status: PickStatus) {
        let ids = Array(selectedGroupIDs)
        guard !ids.isEmpty else { return }
        for id in ids {
            if let idx = captureGroups.firstIndex(where: { $0.id == id }) {
                captureGroups[idx].setPickStatus(status)
                if selectedGroup?.id == id {
                    selectedGroup = captureGroups[idx]
                }
            }
        }
        Task {
            await coordinator.batchUpdatePickStatus(groupIDs: ids, status: status)
        }
    }
    
    public func batchDeleteSelected() {
        let ids = Array(selectedGroupIDs)
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        captureGroups.removeAll(where: { idSet.contains($0.id) })
        receivedFiles.removeAll(where: { file in
            ids.contains(where: { file.filename.contains($0) })
        })
        if let sel = selectedGroup, idSet.contains(sel.id) {
            selectedGroup = filteredGroups.first
        }
        selectedGroupIDs.removeAll()
        Task {
            try? await coordinator.batchDeleteGroups(groupIDs: ids)
        }
    }
    
    // MARK: - Пакетный экспорт и автокопирование (Этап 10)
    
    public func presentExport(for groups: [CaptureGroup]) {
        self.exportTargetGroups = groups
        self.isExportSheetPresented = true
    }
    
    public func presentExportForSelected() {
        let selected = captureGroups.filter { selectedGroupIDs.contains($0.id) }
        if !selected.isEmpty {
            presentExport(for: selected)
        } else if let sel = selectedGroup {
            presentExport(for: [sel])
        }
    }
    
    public func presentExportForSession() {
        presentExport(for: captureGroups)
    }
    
    public func enableAutoExport(url: URL, bookmarkData: Data?, format: ExportFormatSelection = .both) {
        self.isAutoExportEnabled = true
        self.autoExportDestinationURL = url
        self.autoExportBookmarkData = bookmarkData
        self.autoExportFormat = format
        Task {
            await coordinator.setAutoExport(enabled: true, destinationURL: url, bookmarkData: bookmarkData, format: format)
        }
    }
    
    public func disableAutoExport() {
        self.isAutoExportEnabled = false
        self.autoExportDestinationURL = nil
        self.autoExportBookmarkData = nil
        Task {
            await coordinator.setAutoExport(enabled: false, destinationURL: nil, bookmarkData: nil, format: .both)
        }
    }
    
    public var isCameraConnected: Bool {
        connectedClients > 0 || usbConnected || !connectedSources.isEmpty
    }
    
    public var isCameraConnecting: Bool {
        usbConnectionState.isConnecting
    }
    
    public var connectionStatusTitle: String {
        if usbConnected {
            return usbCameraName ?? "Nikon Z (Кабель)"
        } else if let first = connectedSources.first {
            return first.displayName
        } else if connectedClients > 0 {
            return "Nikon Z (Wi-Fi)"
        } else {
            return "Ожидание камеры"
        }
    }
    
    public var shortConnectionStatusTitle: String {
        if usbConnected {
            return "USB"
        } else if connectedClients > 0 {
            return "Wi-Fi"
        } else {
            return "Откл."
        }
    }
    
    public var primaryIP: NetworkAddressInfo? {
        activeIPs.first(where: { $0.type == .usbCable }) ?? activeIPs.first(where: { $0.type == .wifi })
    }
    
    public let serverPort: UInt16
    public let coordinator: TransferCoordinator
    private var server: FTPServer
    private let monitor = NetworkInterfaceMonitor.shared
    private let usbManager: USBCameraManager
    
    public init(
        port: UInt16 = FTPServer.defaultPort,
        coordinator: TransferCoordinator = .shared,
        usbManager: USBCameraManager? = nil,
        resumeLastSessionOnLaunch: Bool? = nil
    ) {
        self.serverPort = port
        self.coordinator = coordinator
        self.server = FTPServer(port: port, coordinator: coordinator)
        
        if let usbManager = usbManager {
            self.usbManager = usbManager
        } else if coordinator !== TransferCoordinator.shared {
            self.usbManager = USBCameraManager(coordinator: coordinator)
        } else {
            self.usbManager = USBCameraManager.shared
        }
        
        let defaults = UserDefaults.standard
        self.resumeLastSessionOnLaunch = resumeLastSessionOnLaunch
            ?? defaults.bool(forKey: "nikon_resume_last_session")
        let receiving = defaults.object(forKey: "nikon_ftp_receiving_enabled") as? Bool ?? true
        let autostart = defaults.object(forKey: "nikon_ftp_autostart_enabled") as? Bool ?? true
        self.isFTPReceivingEnabled = receiving
        self.isFTPAutoStartEnabled = autostart
        
        let creds = FTPAuthManager.shared.getCredentials()
        self.ftpUsername = creds.username
        self.ftpPassword = creds.password
        
        self.isUSBAutoDownloadNewShotsEnabled = self.usbManager.isAutoDownloadNewShotsEnabled
        self.isUSBAutoDownloadCardOnConnectEnabled = self.usbManager.isAutoDownloadCardOnConnectEnabled
        
        setupBindings()
    }
    
    public var currentUSBManager: USBCameraManager { usbManager }
    
    public func setUSBAutoDownloadNewShots(_ enabled: Bool) {
        usbManager.setAutoDownloadNewShots(enabled)
    }
    
    public func setUSBAutoDownloadCardOnConnect(_ enabled: Bool) {
        usbManager.setAutoDownloadCardOnConnect(enabled)
    }
    
    private func setupBindings() {
        // 1. Мониторинг сетевых интерфейсов
        self.activeIPs = monitor.fetchCurrentAddresses()
        monitor.onInterfacesChanged = { [weak self] addresses in
            Task { @MainActor [weak self] in
                self?.activeIPs = addresses
            }
        }
        
        // 2. Инициализация и регистрация USB транспорта
        usbManager.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$usbConnected)
        
        usbManager.$cameraName
            .receive(on: DispatchQueue.main)
            .assign(to: &$usbCameraName)
        
        usbManager.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$usbConnectionState)
            
        usbManager.$isAutoDownloadNewShotsEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isUSBAutoDownloadNewShotsEnabled)
            
        usbManager.$isAutoDownloadCardOnConnectEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isUSBAutoDownloadCardOnConnectEnabled)
        
        // Регистрация транспортов в координаторе
        Task {
            await coordinator.registerTransport(usbManager)
            let ftpAdapter = FTPCameraTransportAdapter(server: server)
            await coordinator.registerTransport(ftpAdapter)
            
            // Не показываем предыдущую съёмку, пока выбирается стартовая сессия.
            do {
                try await coordinator.bootstrapForLaunch(resumeLastSession: resumeLastSessionOnLaunch)
            } catch {
                diagnosticLogger.log(level: .error, subsystem: "Sessions", message: error.localizedDescription)
                serverState = .failed("Не удалось подготовить сессию: \(error.localizedDescription)")
                return
            }
            await configureCoordinatorCallbacks()
            await configureServerCallbacks()
            
            // 3. Явная загрузка восстановленной активной сессии, кадров и очереди в состояние UI
            await syncStateFromCoordinator()
            isStartupReady = true
            usbManager.start()
            
            // 4. Настройка FTP сервера
            await server.setReceivingEnabled(isFTPReceivingEnabled)
            
            // 5. Автозапуск FTP если включено в настройках
            if isFTPAutoStartEnabled && isFTPReceivingEnabled {
                startServer()
            }
        }
        
        #if canImport(UIKit)
        clientMonitorManager.externalViewControllerProvider = { manager in
            let hosting = UIHostingController(rootView: ClientMonitorCleanHostingView(monitorManager: manager))
            hosting.view.backgroundColor = .black
            return hosting
        }
        #endif
    }
    
    /// Ожидание завершения начальной фоновой инициализации транспортов и сессии
    @MainActor
    public func waitUntilReady() async {
        while !isStartupReady {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    
    /// Синхронизация текущего состояния координатора (сессия, кадры, группы, очереди) в главное состояние UI
    @MainActor
    public func syncStateFromCoordinator() async {
        let active = await coordinator.activeSession
        let all = await coordinator.allSessions
        let assets = await coordinator.assets
        let groups = await coordinator.captureGroups
        let relevantJobs = await coordinator.jobs.values.filter { !$0.state.isTerminal || $0.sessionID == active.id }
        let totalBytes = assets.reduce(0, { $0 + $1.fileSize })
        
        self.currentSession = active
        self.availableSessions = all
        self.sessionAuthor = active.author ?? ""
        self.sessionCopyright = active.copyright ?? ""
        self.sessionComment = active.comment ?? ""
        self.receivedFiles = assets.map { IngestedFile(from: $0) }
        self.captureGroups = groups
        self.activeJobs = Array(relevantJobs)
        self.totalBytesTransferred = totalBytes
        
        if let selFile = self.selectedFile {
            self.selectedFile = self.receivedFiles.first(where: { $0.id == selFile.id }) ?? self.receivedFiles.first
        } else {
            self.selectedFile = self.receivedFiles.first
        }
        
        if let selGroup = self.selectedGroup {
            self.selectedGroup = groups.first(where: { $0.id == selGroup.id }) ?? groups.first
        } else {
            self.selectedGroup = groups.first
        }
    }
    
    private func configureCoordinatorCallbacks() async {
        await coordinator.setCallbacks(
            onJobUpdated: { [weak self] job in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let index = self.activeJobs.firstIndex(where: { $0.id == job.id }) {
                        self.activeJobs[index] = job
                    } else {
                        self.activeJobs.append(job)
                    }
                }
            },
            onAssetIngested: { [weak self] asset, group in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let file = IngestedFile(from: asset)
                    self.handleIngestedFile(file)
                    self.totalBytesTransferred += asset.fileSize
                }
            },
            onCaptureGroupUpdated: { [weak self] group in
                Task { @MainActor [weak self] in
                    self?.handleCaptureGroupUpdated(group)
                }
            },
            onSourcesChanged: { [weak self] sources in
                Task { @MainActor [weak self] in
                    self?.connectedSources = sources
                }
            },
            onSessionChanged: { [weak self] session in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentSession = session
                    self.sessionAuthor = session.author ?? ""
                    self.sessionCopyright = session.copyright ?? ""
                    self.sessionComment = session.comment ?? ""
                    let assets = await self.coordinator.assets
                    let groups = await self.coordinator.captureGroups
                    let all = await self.coordinator.allSessions
                    let relevantJobs = await self.coordinator.jobs.values.filter { !$0.state.isTerminal || $0.sessionID == session.id }
                    self.availableSessions = all
                    self.receivedFiles = assets.map { IngestedFile(from: $0) }
                    self.captureGroups = groups
                    self.activeJobs = Array(relevantJobs)
                    self.totalBytesTransferred = assets.reduce(0, { $0 + $1.fileSize })
                    if let selFile = self.selectedFile {
                        self.selectedFile = self.receivedFiles.first(where: { $0.id == selFile.id }) ?? self.receivedFiles.first
                    } else {
                        self.selectedFile = self.receivedFiles.first
                    }
                    if let selGroup = self.selectedGroup {
                        self.selectedGroup = groups.first(where: { $0.id == selGroup.id }) ?? groups.first
                    } else {
                        self.selectedGroup = groups.first
                    }
                }
            },
            onSpeedUpdated: { [weak self] speed in
                Task { @MainActor [weak self] in
                    self?.currentTransferSpeedMBs = speed
                }
            }
        )
    }
    
    private func configureServerCallbacks() async {
        await server.setCallbacks(
            onClientConnectionChanged: { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.connectedClients = count
                }
            },
            onStateChanged: { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.serverState = state
                }
            }
        )
    }
    
    // MARK: - Действия с сессиями
    
    public func reloadSessions() async {
        let all = await coordinator.allSessions
        let active = await coordinator.activeSession
        await MainActor.run {
            self.availableSessions = all
            self.currentSession = active
            self.sessionAuthor = active.author ?? ""
            self.sessionCopyright = active.copyright ?? ""
            self.sessionComment = active.comment ?? ""
        }
    }
    
    public func fetchSessionStats(for sessionID: UUID) async -> SessionStats {
        await coordinator.getSessionStats(id: sessionID)
    }
    
    public func startNewSession(named name: String? = nil) {
        Task {
            do {
                let session = try await coordinator.startNewSession(named: name)
                let all = await coordinator.allSessions
                let nonTerminalJobs = await coordinator.jobs.values.filter { !$0.state.isTerminal }
                await MainActor.run {
                    self.currentSession = session
                    self.availableSessions = all
                    self.sessionAuthor = session.author ?? ""
                    self.sessionCopyright = session.copyright ?? ""
                    self.sessionComment = session.comment ?? ""
                    self.receivedFiles.removeAll()
                    self.captureGroups.removeAll()
                    self.selectedGroup = nil
                    self.selectedFile = nil
                    self.totalBytesTransferred = 0
                    self.activeJobs = Array(nonTerminalJobs)
                }
            } catch {
                print("Error starting new session: \(error)")
            }
        }
    }
    
    public func switchSession(to sessionID: UUID) {
        Task {
            if let switched = await coordinator.switchActiveSession(to: sessionID) {
                let all = await coordinator.allSessions
                let assets = await coordinator.assets
                let groups = await coordinator.captureGroups
                let relevantJobs = await coordinator.jobs.values.filter { !$0.state.isTerminal || $0.sessionID == sessionID }
                await MainActor.run {
                    self.currentSession = switched
                    self.availableSessions = all
                    self.sessionAuthor = switched.author ?? ""
                    self.sessionCopyright = switched.copyright ?? ""
                    self.sessionComment = switched.comment ?? ""
                    self.receivedFiles = assets.map { IngestedFile(from: $0) }
                    self.captureGroups = groups
                    self.selectedGroup = groups.first
                    self.selectedFile = self.receivedFiles.first
                    self.totalBytesTransferred = assets.reduce(0, { $0 + $1.fileSize })
                    self.activeJobs = Array(relevantJobs)
                }
            }
        }
    }
    
    public func saveSessionMetadata(author: String?, copyright: String?, comment: String?) {
        guard let sessionID = currentSession?.id else { return }
        saveSessionMetadata(for: sessionID, author: author, copyright: copyright, comment: comment)
    }
    
    public func saveSessionMetadata(for sessionID: UUID, author: String?, copyright: String?, comment: String?) {
        if currentSession?.id == sessionID {
            self.sessionAuthor = author ?? ""
            self.sessionCopyright = copyright ?? ""
            self.sessionComment = comment ?? ""
        }
        Task {
            await coordinator.updateSessionMetadata(
                id: sessionID,
                author: author,
                copyright: copyright,
                comment: comment
            )
            let all = await coordinator.allSessions
            await MainActor.run {
                self.availableSessions = all
                if let updated = all.first(where: { $0.id == sessionID }), self.currentSession?.id == sessionID {
                    self.currentSession = updated
                }
            }
        }
    }
    
    public func switchAndExportSession(_ session: CaptureSession) {
        if currentSession?.id == session.id {
            presentExportForSession()
        } else {
            Task {
                switchSession(to: session.id)
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    self.presentExportForSession()
                }
            }
        }
    }
    
    public func fetchDatabaseStats() async -> CatalogDatabase.DatabaseStats {
        await coordinator.getDatabaseStats()
    }
    
    public func runCatalogReconciliation() async -> (missingCount: Int, recoveredCount: Int) {
        let (missing, recovered) = await coordinator.reconcileDiskCatalog()
        let assets = await coordinator.assets
        let groups = await coordinator.captureGroups
        await MainActor.run {
            self.receivedFiles = assets.map { IngestedFile(from: $0) }
            self.captureGroups = groups
        }
        return (missing, recovered)
    }
    
    public func renameSession(id: UUID, newName: String) {
        Task {
            do {
                let renamed = try await coordinator.renameSession(id: id, newName: newName)
                let all = await coordinator.allSessions
                let assets = await coordinator.assets
                let groups = await coordinator.captureGroups
                let updatedJobs = await coordinator.jobs.values.filter { $0.sessionID == id }
                await MainActor.run {
                    self.availableSessions = all
                    if self.currentSession?.id == id {
                        self.currentSession = renamed
                        let prevFileID = self.selectedFile?.id
                        let prevGroupID = self.selectedGroup?.id
                        
                        self.receivedFiles = assets.map { IngestedFile(from: $0) }
                        self.captureGroups = groups
                        
                        if let fid = prevFileID {
                            self.selectedFile = self.receivedFiles.first(where: { $0.id == fid }) ?? self.receivedFiles.first
                        } else {
                            self.selectedFile = self.receivedFiles.first
                        }
                        
                        if let gid = prevGroupID {
                            self.selectedGroup = groups.first(where: { $0.id == gid }) ?? groups.first
                        } else {
                            self.selectedGroup = groups.first
                        }
                        
                        self.activeJobs = Array(updatedJobs)
                    }
                }
            } catch {
                print("Error renaming session: \(error)")
            }
        }
    }
    
    public func closeSession(id: UUID) {
        Task {
            await coordinator.closeSession(id: id)
            let all = await coordinator.allSessions
            await MainActor.run {
                self.availableSessions = all
                if self.currentSession?.id == id {
                    self.currentSession?.isClosed = true
                }
            }
        }
    }
    
    public func deleteSession(id: UUID, completion: @escaping (String?) -> Void) {
        Task {
            do {
                try await coordinator.deleteSession(id: id)
                let all = await coordinator.allSessions
                let active = await coordinator.activeSession
                let assets = await coordinator.assets
                let groups = await coordinator.captureGroups
                await MainActor.run {
                    self.availableSessions = all
                    self.currentSession = active
                    self.receivedFiles = assets.map { IngestedFile(from: $0) }
                    self.captureGroups = groups
                    self.selectedGroup = groups.first
                    self.selectedFile = self.receivedFiles.first
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error.localizedDescription)
                }
            }
        }
    }
    
    public func startServer() {
        guard isStartupReady else { return }
        Task {
            do {
                try await server.start()
            } catch {
                await MainActor.run {
                    self.serverState = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    public func stopServer() {
        Task {
            await server.stop()
        }
    }
    
    public func restartServer() {
        Task {
            do {
                try await server.restart()
            } catch {
                await MainActor.run {
                    self.serverState = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    public func toggleFTPReceiving(_ enabled: Bool) {
        isFTPReceivingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "nikon_ftp_receiving_enabled")
        Task {
            await server.setReceivingEnabled(enabled)
            if !enabled {
                await server.stop()
            } else {
                startServer()
            }
        }
    }
    
    public func toggleFTPAutoStart(_ enabled: Bool) {
        isFTPAutoStartEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "nikon_ftp_autostart_enabled")
    }
    
    public func updateFTPCredentials(username: String, password: String) {
        FTPAuthManager.shared.updateUsername(username)
        FTPAuthManager.shared.updatePassword(password)
        let creds = FTPAuthManager.shared.getCredentials()
        self.ftpUsername = creds.username
        self.ftpPassword = creds.password
    }
    
    public func regenerateFTPPassword() {
        let newPass = FTPAuthManager.shared.regeneratePassword()
        self.ftpPassword = newPass
    }
    
    public func handleScenePhaseChange(_ phase: ScenePhase) {
        lifecycleManager.handleScenePhaseChange(
            phase,
            hasActiveJobs: activeTransferJob != nil,
            coordinator: coordinator
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.activeIPs = self.monitor.fetchCurrentAddresses()
                await self.reloadSessions()
            }
        }
    }
    
    public func cancelJob(id: UUID) {
        Task {
            await coordinator.cancelTransfer(jobID: id)
            await usbManager.cancelTransfer(jobID: id)
            diagnosticLogger.log(level: .info, subsystem: "Queue", message: "Задание \(id) отменено пользователем")
        }
    }
    
    public func retryJob(id: UUID) {
        Task {
            guard let job = activeJobs.first(where: { $0.id == id }) else { return }
            diagnosticLogger.log(level: .info, subsystem: "Queue", message: "Повтор задания \(job.filename)")
            if job.source.transportType == .usb {
                do {
                    try await usbManager.retryTransfer(jobID: id)
                } catch {
                    diagnosticLogger.log(level: .error, subsystem: "USB", message: "Не удалось повторить перенос по USB: \(error)")
                }
            } else {
                diagnosticLogger.log(level: .info, subsystem: "FTP", message: "Ожидание повторной отправки кадра \(job.filename) камерой")
            }
        }
    }
    
    public func clearGallery() {
        Task {
            do {
                try await coordinator.clearActiveSession()
                await MainActor.run {
                    self.receivedFiles.removeAll()
                    self.captureGroups.removeAll()
                    self.selectedFile = nil
                    self.totalBytesTransferred = 0
                    self.currentTransferSpeedMBs = 0.0
                }
            } catch {
                print("Failed to clear gallery: \(error)")
            }
        }
    }
    
    // MARK: - Управление клиентским монитором (Этап 11)
    
    public func toggleClientMonitorHold() {
        clientMonitorManager.toggleHold(for: selectedGroup)
    }
    
    public func presentClientMonitor() {
        if clientMonitorManager.displayedGroup == nil {
            clientMonitorManager.displayedGroup = selectedGroup ?? filteredGroups.first
        }
        isClientMonitorPresented = true
    }
    
    public func presentClientControlSheet() {
        isClientControlSheetPresented = true
    }
    
    public func pushSelectedToClientMonitor() {
        if let sel = selectedGroup {
            clientMonitorManager.forcePresentGroup(sel)
        }
    }
}

// MARK: - Extension TransferCoordinator for Callbacks Configuration
extension TransferCoordinator {
    public func setCallbacks(
        onJobUpdated: (@Sendable (TransferJob) -> Void)? = nil,
        onAssetIngested: (@Sendable (MediaAsset, CaptureGroup) -> Void)? = nil,
        onCaptureGroupUpdated: (@Sendable (CaptureGroup) -> Void)? = nil,
        onSourcesChanged: (@Sendable ([CameraSource]) -> Void)? = nil,
        onSessionChanged: (@Sendable (CaptureSession) -> Void)? = nil,
        onSpeedUpdated: (@Sendable (Double) -> Void)? = nil
    ) {
        if let cb = onJobUpdated { self.onJobUpdated = cb }
        if let cb = onAssetIngested { self.onAssetIngested = cb }
        if let cb = onCaptureGroupUpdated { self.onCaptureGroupUpdated = cb }
        if let cb = onSourcesChanged { self.onSourcesChanged = cb }
        if let cb = onSessionChanged { self.onSessionChanged = cb }
        if let cb = onSpeedUpdated { self.onSpeedUpdated = cb }
    }
}
