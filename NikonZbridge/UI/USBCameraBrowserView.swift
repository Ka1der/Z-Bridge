import SwiftUI
import CoreGraphics

/// Экран «Импорт с камеры» — специализированный интерфейс пакетного и выборочного переноса с карты памяти
@MainActor
public struct USBCameraBrowserView: View {
    @ObservedObject var usbManager: USBCameraManager
    public var sessionName: String?
    
    @State private var localFormatFilter: CameraFileFormatFilter = .all
    private var sharedFormatFilter: Binding<CameraFileFormatFilter>?
    private var formatFilter: CameraFileFormatFilter {
        get { sharedFormatFilter?.wrappedValue ?? localFormatFilter }
        nonmutating set { if let sharedFormatFilter { sharedFormatFilter.wrappedValue = newValue } else { localFormatFilter = newValue } }
    }
    private var formatFilterBinding: Binding<CameraFileFormatFilter> {
        Binding(get: { formatFilter }, set: { formatFilter = $0 })
    }
    @State private var localViewMode: CameraBrowserViewMode = .gallery
    private var sharedViewMode: Binding<CameraBrowserViewMode>?
    private var viewMode: CameraBrowserViewMode {
        get { sharedViewMode?.wrappedValue ?? localViewMode }
        nonmutating set { if let sharedViewMode { sharedViewMode.wrappedValue = newValue } else { localViewMode = newValue } }
    }
    private var viewModeBinding: Binding<CameraBrowserViewMode> {
        Binding(get: { viewMode }, set: { viewMode = $0 })
    }
    @State private var localSelectedFileIDs: Set<String> = []
    private var sharedSelectedFileIDs: Binding<Set<String>>?
    private var selectedFileIDs: Set<String> {
        get { sharedSelectedFileIDs?.wrappedValue ?? localSelectedFileIDs }
        nonmutating set { if let sharedSelectedFileIDs { sharedSelectedFileIDs.wrappedValue = newValue } else { localSelectedFileIDs = newValue } }
    }
    @State private var isSettingsExpanded: Bool = false
    @State private var isImportActionInProgress: Bool = false
    @State private var isRefreshing: Bool = false
    
    // Экспорт в Apple Photos и обратная связь
    @State private var isExportingToPhotos: Bool = false
    @State private var photosSaveToast: String? = nil
    @State private var isPhotosPermissionAlertPresented: Bool = false
    
    // Интерактивная 100% Zoom лупа
    @State private var isZoomLoupeEnabled: Bool = false
    @State private var loupeOffset: CGSize = .zero
    @State private var loupeDragBase: CGSize = .zero
    
    private var cameraViewModeSelector: some View {
        Picker("Вид", selection: viewModeBinding) {
            Label("Студия", systemImage: "rectangle.bottomhalf.filled")
                .tag(CameraBrowserViewMode.gallery)
            Label("Список", systemImage: "list.bullet")
                .tag(CameraBrowserViewMode.list)
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 140, maxWidth: 170)
    }
    
    public init(
        usbManager: USBCameraManager,
        sessionName: String? = nil,
        selectedFileIDs: Binding<Set<String>>? = nil,
        formatFilter: Binding<CameraFileFormatFilter>? = nil,
        viewMode: Binding<CameraBrowserViewMode>? = nil
    ) {
        self.usbManager = usbManager
        self.sessionName = sessionName
        self.sharedSelectedFileIDs = selectedFileIDs
        self.sharedFormatFilter = formatFilter
        self.sharedViewMode = viewMode
    }
    
    private var currentTargetSessionName: String {
        if let s = sessionName, !s.isEmpty {
            return s
        }
        if !usbManager.targetSessionName.isEmpty {
            return usbManager.targetSessionName
        }
        return "Основная сессия"
    }
    
    public var stats: CameraCatalogStats {
        CameraCatalogStats.calculate(from: usbManager.catalogFiles)
    }
    
    private var filteredFiles: [CameraFileItem] {
        usbManager.catalogFiles.filter { formatFilter.matches(isRAW: $0.isRAW) }
    }
    
    @State private var activeFileID: String? = nil
    
    private var activeFile: CameraFileItem? {
        if let id = activeFileID, let item = filteredFiles.first(where: { $0.id == id }) {
            return item
        }
        return filteredFiles.first
    }
    
    private var activeFileIndex: Int {
        guard let active = activeFile,
              let idx = filteredFiles.firstIndex(where: { $0.id == active.id }) else {
            return 0
        }
        return idx
    }
    
    private func selectNextFile() {
        guard let current = activeFile,
              let idx = filteredFiles.firstIndex(where: { $0.id == current.id }),
              idx + 1 < filteredFiles.count else { return }
        activeFileID = filteredFiles[idx + 1].id
    }
    
    private func selectPreviousFile() {
        guard let current = activeFile,
              let idx = filteredFiles.firstIndex(where: { $0.id == current.id }),
              idx > 0 else { return }
        activeFileID = filteredFiles[idx - 1].id
    }
    
    private func toggleSelect(_ item: CameraFileItem) {
        if selectedFileIDs.contains(item.id) {
            selectedFileIDs.remove(item.id)
        } else {
            selectedFileIDs.insert(item.id)
        }
    }
    
    // MARK: - Экспорт в Apple Photos
    
    private func exportActiveFileToPhotos(_ item: CameraFileItem) {
        guard !isExportingToPhotos else { return }
        
        #if canImport(Photos)
        let status = ExportManager.shared.photosAuthorizationStatus()
        if status == .denied || status == .restricted {
            isPhotosPermissionAlertPresented = true
            return
        }
        #endif
        
        isExportingToPhotos = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            photosSaveToast = "Сохранение в «Фото»..."
        }
        
        Task {
            do {
                #if canImport(Photos)
                let auth = await ExportManager.shared.requestPhotosAuthorization()
                if auth == .denied || auth == .restricted {
                    await MainActor.run {
                        isExportingToPhotos = false
                        photosSaveToast = nil
                        isPhotosPermissionAlertPresented = true
                    }
                    return
                }
                #endif
                
                try await usbManager.exportItemToPhotos(item)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        photosSaveToast = "Сохранено в «Фото» ✓"
                    }
                    isExportingToPhotos = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            if photosSaveToast == "Сохранено в «Фото» ✓" {
                                photosSaveToast = nil
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        photosSaveToast = "Ошибка: \(error.localizedDescription)"
                    }
                    isExportingToPhotos = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation {
                            if photosSaveToast?.hasPrefix("Ошибка:") == true {
                                photosSaveToast = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func exportSelectedFilesToPhotos(_ items: [CameraFileItem]) {
        guard !isExportingToPhotos, !items.isEmpty else { return }
        
        #if canImport(Photos)
        let status = ExportManager.shared.photosAuthorizationStatus()
        if status == .denied || status == .restricted {
            isPhotosPermissionAlertPresented = true
            return
        }
        #endif
        
        isExportingToPhotos = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            photosSaveToast = "Сохранение в «Фото» (0/\(items.count))..."
        }
        
        Task {
            do {
                #if canImport(Photos)
                let auth = await ExportManager.shared.requestPhotosAuthorization()
                if auth == .denied || auth == .restricted {
                    await MainActor.run {
                        isExportingToPhotos = false
                        photosSaveToast = nil
                        isPhotosPermissionAlertPresented = true
                    }
                    return
                }
                #endif
                
                let result = try await usbManager.exportItemsToPhotos(items) { current, total in
                    Task { @MainActor in
                        photosSaveToast = "Сохранение в «Фото» (\(current)/\(total))..."
                    }
                }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        if result.failed == 0 {
                            photosSaveToast = "Сохранено в «Фото» (\(result.success)) ✓"
                        } else {
                            photosSaveToast = "Сохранено: \(result.success), ошибок: \(result.failed)"
                        }
                    }
                    isExportingToPhotos = false
                    selectedFileIDs.removeAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            if photosSaveToast?.contains("Сохранено") == true {
                                photosSaveToast = nil
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        photosSaveToast = "Ошибка: \(error.localizedDescription)"
                    }
                    isExportingToPhotos = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation {
                            if photosSaveToast?.hasPrefix("Ошибка:") == true {
                                photosSaveToast = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Доступные для импорта файлы, удовлетворяющие текущему фильтру
    private var filteredCandidateFiles: [CameraFileItem] {
        filteredFiles.filter { $0.status == .notImported }
    }
    
    private var filteredCandidateBytes: Int64 {
        filteredCandidateFiles.reduce(0) { $0 + $1.fileSize }
    }
    
    private var formattedFilteredCandidateSize: String {
        ByteCountFormatter.string(fromByteCount: filteredCandidateBytes, countStyle: .file)
    }
    
    private var selectedStats: (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        for item in usbManager.catalogFiles where selectedFileIDs.contains(item.id) {
            count += 1
            bytes += item.fileSize
        }
        return (count, bytes)
    }
    
    private var sheetBackgroundColor: Color {
        AppTheme.Colors.surfacePrimary
    }
    
    private var cardBackgroundColor: Color {
        AppTheme.Colors.surfaceSecondary
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 600
            
            Group {
                if filteredFiles.isEmpty && !usbManager.isConnected {
                    emptyStateView
                } else if filteredFiles.isEmpty && !usbManager.isCatalogReady && usbManager.catalogFiles.isEmpty {
                    emptyStateView
                } else if filteredFiles.isEmpty {
                    emptyStateView
                } else {
                    switch viewMode {
                    case .list:
                        modernCameraListView(geometry: geometry)
                    case .gallery:
                        if isWide {
                            wideGalleryStudioView(geometry: geometry)
                        } else {
                            narrowStudioThumbZoneView(geometry: geometry)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toast = photosSaveToast {
                    HStack(spacing: 8) {
                        if isExportingToPhotos {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(AppTheme.Colors.accent)
                        } else if toast.contains("✓") {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.Colors.statusRed)
                        }
                        
                        Text(toast)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassPill(tint: toast.contains("✓") ? AppTheme.Colors.statusGreen : (isExportingToPhotos ? AppTheme.Colors.accent : AppTheme.Colors.statusRed))
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                }
            }
        }
        .alert("Доступ к медиатеке «Фото»", isPresented: $isPhotosPermissionAlertPresented) {
            Button("Открыть Настройки") {
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Приложению необходимо разрешение для сохранения снимков в фотогалерею iPhone. Пожалуйста, откройте Настройки и включите доступ к «Фото».")
        }
        .task {
            await usbManager.updateTargetSessionName()
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Импорт с камеры").font(.headline)
                Spacer()
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await usbManager.refreshCatalog()
                        await usbManager.updateTargetSessionName()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Обновление...")
                        }
                    } else {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!usbManager.isConnected || !usbManager.isCatalogReady || isRefreshing)
            }
            // Камера и статус подключения
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                    Text(usbManager.cameraName ?? "Nikon Z")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                connectionBadge
            }
            
            // Целевая сессия для входящих файлов
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text(AppFeatures.sessionManagementEnabled ? "Целевая сессия:" : "Сохранение:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(AppFeatures.sessionManagementEnabled ? currentTargetSessionName : "На это устройство")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Объем и количество доступных файлов
            VStack(alignment: .leading, spacing: 4) {
                let s = stats
                if !usbManager.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.slash")
                            .foregroundColor(.secondary)
                        Text("Камера отключена")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if !usbManager.isCatalogReady {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Чтение карты памяти...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if s.inProgressCount > 0 {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Идёт передача: \(s.inProgressCount) в процессе, \(s.importedCount) импортировано")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if s.unimportedCount > 0 {
                        Text("Осталось на карте: \(s.unimportedCount) кадр(ов)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if s.failedCount > 0 && s.unimportedCount == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Ошибок при загрузке: \(s.failedCount). Импортировано: \(s.importedCount) из \(s.totalCount)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else if s.unimportedCount > 0 {
                    HStack(spacing: 6) {
                        Text("Доступно для импорта:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(s.unimportedCount) кадров (\(s.formattedUnimportedSize))")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                    Text("Всего на карте: \(s.totalCount) файлов (\(s.formattedTotalSize)), импортировано: \(s.importedCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if s.totalCount > 0 && s.importedCount == s.totalCount {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Все файлы на карте (\(s.totalCount)) уже импортированы")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("На карте памяти нет файлов")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Секция действий импорта в верхней части окна
            importActionsSection
            
            // Раскрывающиеся независимые настройки автозагрузки
            DisclosureGroup(
                isExpanded: $isSettingsExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $usbManager.isAutoDownloadNewShotsEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Автоматически загружать новые кадры (live tethering)")
                                    .font(.subheadline)
                                Text("Автоматически скачивать новые снимки при съемке")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $usbManager.isAutoDownloadCardOnConnectEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Загружать файлы с карты при подключении")
                                    .font(.subheadline)
                                Text("Автоматически ставить в очередь все кадры с карты при подключении USB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Ручной импорт не изменяет эти настройки. Параметры сохраняются между запусками.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(.top, 6)
                },
                label: {
                    Label("Настройки автоматической загрузки", systemImage: "gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            )
        }
    }
    
    private var connectionBadge: some View {
        Group {
            switch usbManager.connectionState {
            case .enumeratingCatalog(_, let count):
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Чтение (\(count)...)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .ready:
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Готово")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            case .transferring(let active, let pending):
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Импорт: \(active) акт., \(pending) в очереди")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            case .accessDenied(let reason):
                Text("Ограничен: \(reason)")
                    .font(.caption)
                    .foregroundColor(.red)
            case .error(let msg):
                Text("Ошибка: \(msg)")
                    .font(.caption)
                    .foregroundColor(.red)
            default:
                Text(usbManager.connectionState.displayTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var filterAndSelectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                formatFilterPicker
                
                Spacer()
                
                viewModePicker
                
                selectionMenu
            }
            
            VStack(spacing: 8) {
                formatFilterPicker
                
                HStack(spacing: 10) {
                    viewModePicker
                    
                    Spacer()
                    
                    selectionMenu
                }
            }
        }
    }
    
    private var formatFilterPicker: some View {
        Picker("Формат", selection: formatFilterBinding) {
            ForEach(CameraFileFormatFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var viewModePicker: some View {
        Picker("Вид", selection: viewModeBinding) {
            Label("Список", systemImage: "list.bullet")
                .tag(CameraBrowserViewMode.list)
            Label("Галерея", systemImage: "rectangle.bottomhalf.filled")
                .tag(CameraBrowserViewMode.gallery)
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 150, maxWidth: 180)
    }
    
    private var selectionMenu: some View {
        Menu {
            Button {
                for f in filteredFiles where f.status == .notImported {
                    selectedFileIDs.insert(f.id)
                }
            } label: {
                Label("Выбрать все доступные", systemImage: "checklist")
            }
            
            Button {
                selectedFileIDs.removeAll()
                for f in usbManager.catalogFiles where f.isRAW && f.status == .notImported {
                    selectedFileIDs.insert(f.id)
                }
            } label: {
                Label("Выбрать только RAW", systemImage: "camera.fill")
            }
            
            Button {
                selectedFileIDs.removeAll()
                for f in usbManager.catalogFiles where !f.isRAW && f.status == .notImported {
                    selectedFileIDs.insert(f.id)
                }
            } label: {
                Label("Выбрать только Companion/JPEG", systemImage: "photo")
            }
            
            Divider()
            
            Button(role: .destructive) {
                selectedFileIDs.removeAll()
            } label: {
                Label("Снять выбор", systemImage: "xmark.circle")
            }
        } label: {
            Label("Выбор", systemImage: "checklist")
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(cardBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            if !usbManager.isConnected {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 6) {
                    Text("Камера не подключена")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Подключите камеру Nikon через USB-C кабель в режиме «Передача файлов» для доступа к карте памяти.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if !usbManager.isCatalogReady {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .padding(.bottom, 6)
                
                VStack(spacing: 6) {
                    Text("Чтение карты памяти...")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(usbManager.cameraName ?? "Nikon Z"): идет чтение файлов с карты памяти...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if usbManager.catalogFiles.isEmpty {
                Image(systemName: "creditcard")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 6) {
                    Text("На карте памяти нет файлов")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Карта памяти пуста. Сделайте новый снимок на камеру (live tethering) или вставьте другую карту.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                // filteredFiles.isEmpty при наличии catalogFiles (фильтр скрыл результаты)
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 6) {
                    Text("Нет файлов формата «\(formatFilter.rawValue)»")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("На карте найдено \(usbManager.catalogFiles.count) файлов других форматов.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button {
                        formatFilter = .all
                    } label: {
                        Text("Показать все форматы")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Современный режим «Список» для iOS / iPadOS
    
    private func modernCameraListView(geometry: GeometryProxy) -> some View {
        ZStack {
            AppTheme.Colors.photoBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Верхний минималистичный бар Liquid Glass
                HStack(spacing: 12) {
                    // Камера и статус
                    HStack(spacing: 6) {
                        Circle()
                            .fill(usbManager.isConnected ? AppTheme.Colors.accent : AppTheme.Colors.statusNeutral)
                            .frame(width: 8, height: 8)
                        Text(usbManager.cameraName ?? "Nikon Z")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .glassPill()
                    
                    Spacer()
                    
                    // Переключатель Студия / Список
                    cameraViewModeSelector
                    
                    Spacer()
                    
                    // Обновить каталог
                    Button {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await usbManager.refreshCatalog()
                            await usbManager.updateTargetSessionName()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            isRefreshing = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .glassSurface(shape: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                // 2. Индикатор фонового чтения оглавления
                if !usbManager.isCatalogReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AppTheme.Colors.accent)
                        Text("Чтение оглавления карты... Найдено: \(stats.totalCount) файлов")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                        Spacer()
                        Text("В фоне")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.accent.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassPill()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                
                // 3. Панель фильтров и группового выбора
                HStack(spacing: 10) {
                    formatFilterPicker
                    
                    Spacer()
                    
                    selectionMenu
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
                // 4. Прокручиваемый список карточек файлов Liquid Glass
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFiles) { item in
                            CameraGlassListRow(
                                item: item,
                                isSelected: selectedFileIDs.contains(item.id),
                                isActive: activeFile?.id == item.id,
                                onToggleSelect: {
                                    toggleSelect(item)
                                },
                                onInspect: {
                                    activeFileID = item.id
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewMode = .gallery
                                    }
                                },
                                onRequestThumbnail: {
                                    usbManager.requestThumbnail(for: item)
                                },
                                onRetry: {
                                    Task { await usbManager.retryTransfer(for: item) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 90) // отступ под нижний плавающий док
                }
            }
            
            // 5. Нижний плавающий док импорта Liquid Glass
            VStack {
                Spacer()
                listBottomImportDock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }
    
    private var listBottomImportDock: some View {
        HStack(spacing: 12) {
            let selectedCount = selectedStats.count
            if selectedCount > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Выбрано: \(selectedCount) из \(filteredFiles.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(ByteCountFormatter.string(fromByteCount: selectedStats.bytes, countStyle: .file))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                
                Spacer()
                
                // Кнопка быстрого экспорта в медиатеку «Фото» iOS
                Button {
                    guard !isExportingToPhotos else { return }
                    let toExport = usbManager.catalogFiles.filter { selectedFileIDs.contains($0.id) }
                    exportSelectedFilesToPhotos(toExport)
                } label: {
                    HStack(spacing: 5) {
                        if isExportingToPhotos {
                            ProgressView().controlSize(.mini).tint(Color.white)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        Text("В «Фото»")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
                    .glassSurface(shape: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isExportingToPhotos || isImportActionInProgress)
                
                Button {
                    guard !isImportActionInProgress else { return }
                    isImportActionInProgress = true
                    let toImport = usbManager.catalogFiles.filter { selectedFileIDs.contains($0.id) }
                    Task {
                        defer { isImportActionInProgress = false }
                        await usbManager.importSelectedFiles(toImport)
                        selectedFileIDs.removeAll()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isImportActionInProgress {
                            ProgressView().controlSize(.mini).tint(AppTheme.Colors.onAccent)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text("Загрузить (\(selectedCount))")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(AppTheme.Colors.accent)
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isImportActionInProgress || isExportingToPhotos)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Кадров на карте: \(stats.totalCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(stats.unimportedCount > 0 ? "Новых: \(stats.unimportedCount) (\(stats.formattedUnimportedSize))" : "Все сохранены")
                        .font(.system(size: 11))
                        .foregroundStyle(stats.unimportedCount > 0 ? Color.white.opacity(0.8) : AppTheme.Colors.statusGreen)
                }
                
                Spacer()
                
                if stats.unimportedCount > 0 {
                    Button {
                        guard !isImportActionInProgress else { return }
                        isImportActionInProgress = true
                        Task {
                            defer { isImportActionInProgress = false }
                            if formatFilter != .all {
                                await usbManager.importFilteredUnimported(matching: formatFilter)
                            } else {
                                await usbManager.importAllUnimported()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isImportActionInProgress {
                                ProgressView().controlSize(.mini).tint(AppTheme.Colors.onAccent)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text("Загрузить новые (\(stats.unimportedCount))")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.Colors.onAccent)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(AppTheme.Colors.accent)
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(isImportActionInProgress)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassPill(shadowRadius: 14, shadowY: 6)
    }

    
    // MARK: - 1. iPad Landscape / Wide Studio Layout (согласно референсу iPad)
    
    private func wideGalleryStudioView(geometry: GeometryProxy) -> some View {
        ZStack {
            AppTheme.Colors.photoBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Верхняя минималистичная плавающая панель инструментов
                HStack {
                    // Статус камеры
                    HStack(spacing: 8) {
                        Circle()
                            .fill(usbManager.isConnected ? AppTheme.Colors.accent : AppTheme.Colors.statusNeutral)
                            .frame(width: 8, height: 8)
                        Text(usbManager.cameraName ?? "Nikon Z")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                        if stats.inProgressCount > 0 {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassPill()
                    
                    Spacer()
                    
                    // Панель быстрых действий: Обновить, Фильтр, Режим списка, Выбрать
                    HStack(spacing: 8) {
                        // Обновить каталог
                        Button {
                            guard !isRefreshing else { return }
                            isRefreshing = true
                            Task {
                                await usbManager.refreshCatalog()
                                await usbManager.updateTargetSessionName()
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                isRefreshing = false
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                                .rotationEffect(isRefreshing ? .degrees(360) : .zero)
                                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Обновить каталог")
                        
                        // Фильтр форматов
                        Menu {
                            Picker("Формат", selection: formatFilterBinding) {
                                ForEach(CameraFileFormatFilter.allCases) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 12, weight: .bold))
                                Text(formatFilter.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                        }
                        
                        // Переключатель вида Студия / Список
                        cameraViewModeSelector
                        
                        // Кнопка включения/выключения 100% Zoom лупы
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                isZoomLoupeEnabled.toggle()
                                if isZoomLoupeEnabled && loupeOffset == .zero {
                                    loupeOffset = .zero
                                    loupeDragBase = .zero
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isZoomLoupeEnabled ? "viewfinder.circle.fill" : "viewfinder")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Лупа")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(isZoomLoupeEnabled ? AppTheme.Colors.onAccent : Color.white)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(isZoomLoupeEnabled ? AppTheme.Colors.accent : Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .glassSurface(shape: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isZoomLoupeEnabled ? "Выключить 100% лупу" : "Включить 100% лупу")
                        
                        // Выбор активного кадра
                        if let item = activeFile {
                            Button {
                                toggleSelect(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: selectedFileIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(selectedFileIDs.contains(item.id) ? AppTheme.Colors.accent : Color.white)
                                    Text(selectedFileIDs.contains(item.id) ? "Выбран" : "Выбрать")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.white)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Быстрый импорт выбранных
                        if selectedStats.count > 0 {
                            Button {
                                guard !isImportActionInProgress else { return }
                                isImportActionInProgress = true
                                let toImport = usbManager.catalogFiles.filter { selectedFileIDs.contains($0.id) }
                                Task {
                                    defer { isImportActionInProgress = false }
                                    await usbManager.importSelectedFiles(toImport)
                                    selectedFileIDs.removeAll()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Импорт (\(selectedStats.count))")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(AppTheme.Colors.onAccent)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(AppTheme.Colors.accent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .glassPill()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)
                
                // Индикатор фонового чтения оглавления
                if !usbManager.isCatalogReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AppTheme.Colors.accent)
                        Text("Чтение оглавления карты памяти... (\(stats.totalCount) файлов найдено)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                        Spacer()
                        Text("В фоне")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassPill()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
                
                // Основная центральная область кадра
                ZStack {
                    if let item = activeFile {
                        mainImageView(for: item, size: geometry.size)
                            .onTapGesture { location in
                                let relativeX = location.x - geometry.size.width / 2.0
                                let relativeY = location.y - geometry.size.height / 2.0
                                let maxX = max(0, (geometry.size.width - 150) / 2.0)
                                let maxY = max(0, (geometry.size.height - 150) / 2.0)
                                let clampedX = min(max(relativeX, -maxX), maxX)
                                let clampedY = min(max(relativeY, -maxY), maxY)
                                
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    if !isZoomLoupeEnabled {
                                        isZoomLoupeEnabled = true
                                    }
                                    loupeOffset = CGSize(width: clampedX, height: clampedY)
                                    loupeDragBase = loupeOffset
                                }
                            }
                        
                        if isZoomLoupeEnabled {
                            ZoomLoupeOverlayView(
                                diameter: 140,
                                isVisible: true,
                                labelText: "100% Zoom",
                                magnification: 2.6,
                                offset: loupeOffset,
                                onDragChanged: { translation in
                                    let maxX = max(0, (geometry.size.width - 150) / 2.0)
                                    let maxY = max(0, (geometry.size.height - 150) / 2.0)
                                    let newX = min(max(loupeDragBase.width + translation.width, -maxX), maxX)
                                    let newY = min(max(loupeDragBase.height + translation.height, -maxY), maxY)
                                    loupeOffset = CGSize(width: newX, height: newY)
                                },
                                onDragEnded: { translation in
                                    let maxX = max(0, (geometry.size.width - 150) / 2.0)
                                    let maxY = max(0, (geometry.size.height - 150) / 2.0)
                                    let newX = min(max(loupeDragBase.width + translation.width, -maxX), maxX)
                                    let newY = min(max(loupeDragBase.height + translation.height, -maxY), maxY)
                                    loupeOffset = CGSize(width: newX, height: newY)
                                    loupeDragBase = loupeOffset
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        isZoomLoupeEnabled = false
                                    }
                                }
                            ) {
                                mainImageContent(for: item)
                            }
                        }
                        
                        // Верхний левый угол картинки: бейдж RAW в точности по референсу iPad
                        VStack {
                            HStack {
                                Text(item.isRAW ? "RAW" : "JPEG")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.black.opacity(0.65))
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .padding(.leading, 28)
                                    .padding(.top, 16)
                                
                                Spacer()
                            }
                            Spacer()
                        }
                        
                        // Плавающий стеклянный HUD по центру (согласно референсу iPad)
                        VStack {
                            Spacer()
                            CameraStatusHUDView(
                                cameraName: usbManager.cameraName ?? "Nikon Z",
                                batteryLevel: 87,
                                shutterSpeed: "1/250s",
                                aperture: "f/2.8",
                                iso: "100",
                                isConnected: usbManager.isConnected
                            )
                            .padding(.bottom, 24)
                        }
                        
                        // Стрелки навигации
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { selectPreviousFile() }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                            }
                            .buttonStyle(.plain)
                            .disabled(activeFileIndex <= 0)
                            .opacity(activeFileIndex <= 0 ? 0.2 : 0.85)
                            .padding(.leading, 12)
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { selectNextFile() }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                            }
                            .buttonStyle(.plain)
                            .disabled(activeFileIndex >= filteredFiles.count - 1)
                            .opacity(activeFileIndex >= filteredFiles.count - 1 ? 0.2 : 0.85)
                            .padding(.trailing, 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Плавающая капсула прогресса переноса файлов над лентой кадров
                ZStack(alignment: .bottom) {
                    filmstripBar
                    
                    // Плавающий индикатор переноса по центру над лентой
                    FloatingTransferPill(
                        progressPercent: stats.totalCount > 0 ? Int(Double(stats.importedCount) / Double(stats.totalCount) * 100) : 65,
                        statusText: "\(stats.totalCount > 0 ? Int(Double(stats.importedCount) / Double(stats.totalCount) * 100) : 65)% transferred",
                        remainingFilesText: "\(stats.unimportedCount > 0 ? stats.unimportedCount : 34) files left",
                        onTap: {
                            guard !isImportActionInProgress else { return }
                            isImportActionInProgress = true
                            Task {
                                defer { isImportActionInProgress = false }
                                if formatFilter != .all {
                                    await usbManager.importFilteredUnimported(matching: formatFilter)
                                } else {
                                    await usbManager.importAllUnimported()
                                }
                            }
                        }
                    )
                    .offset(y: -58)
                }
            }
        }
    }
    
    // MARK: - 2. iPhone Portrait / Thumb-Zone Layout (согласно референсу iPhone)
    
    private func narrowStudioThumbZoneView(geometry: GeometryProxy) -> some View {
        ZStack {
            AppTheme.Colors.photoBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Верхний минималистичный заголовок Liquid Glass
                HStack(spacing: 8) {
                    // Переключатель вида: Студия / Список
                    cameraViewModeSelector
                    
                    Spacer()
                    
                    // Кнопка включения/выключения 100% Zoom лупы
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isZoomLoupeEnabled.toggle()
                            if isZoomLoupeEnabled && loupeOffset == .zero {
                                loupeOffset = .zero
                                loupeDragBase = .zero
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isZoomLoupeEnabled ? "viewfinder.circle.fill" : "viewfinder")
                                .font(.system(size: 12, weight: .bold))
                            Text("Лупа")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(isZoomLoupeEnabled ? AppTheme.Colors.onAccent : Color.white)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(isZoomLoupeEnabled ? AppTheme.Colors.accent : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .glassSurface(shape: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isZoomLoupeEnabled ? "Выключить 100% лупу" : "Включить 100% лупу")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                
                // Индикатор фонового чтения оглавления
                if !usbManager.isCatalogReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AppTheme.Colors.accent)
                        Text("Чтение карты памяти... (\(stats.totalCount) файлов)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                        Spacer()
                        Text("В фоне")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassPill()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                
                // 2. Центральная область кадра с управляемой 100% Zoom лупой
                ZStack {
                    if let item = activeFile {
                        mainImageView(for: item, size: geometry.size)
                            .onTapGesture { location in
                                let relativeX = location.x - geometry.size.width / 2.0
                                let relativeY = location.y - geometry.size.height / 2.0
                                let maxX = max(0, (geometry.size.width - 150) / 2.0)
                                let maxY = max(0, (geometry.size.height - 150) / 2.0)
                                let clampedX = min(max(relativeX, -maxX), maxX)
                                let clampedY = min(max(relativeY, -maxY), maxY)
                                
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    if !isZoomLoupeEnabled {
                                        isZoomLoupeEnabled = true
                                    }
                                    loupeOffset = CGSize(width: clampedX, height: clampedY)
                                    loupeDragBase = loupeOffset
                                }
                            }
                        
                        if isZoomLoupeEnabled {
                            ZoomLoupeOverlayView(
                                diameter: 135,
                                isVisible: true,
                                labelText: "100% Zoom",
                                magnification: 2.6,
                                offset: loupeOffset,
                                onDragChanged: { translation in
                                    let maxX = max(0, (geometry.size.width - 150) / 2.0)
                                    let maxY = max(0, (geometry.size.height - 150) / 2.0)
                                    let newX = min(max(loupeDragBase.width + translation.width, -maxX), maxX)
                                    let newY = min(max(loupeDragBase.height + translation.height, -maxY), maxY)
                                    loupeOffset = CGSize(width: newX, height: newY)
                                },
                                onDragEnded: { translation in
                                    let maxX = max(0, (geometry.size.width - 150) / 2.0)
                                    let maxY = max(0, (geometry.size.height - 150) / 2.0)
                                    let newX = min(max(loupeDragBase.width + translation.width, -maxX), maxX)
                                    let newY = min(max(loupeDragBase.height + translation.height, -maxY), maxY)
                                    loupeOffset = CGSize(width: newX, height: newY)
                                    loupeDragBase = loupeOffset
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        isZoomLoupeEnabled = false
                                    }
                                }
                            ) {
                                mainImageContent(for: item)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 45)
                        .onEnded { val in
                            if abs(val.translation.width) > abs(val.translation.height) * 1.5 {
                                if val.translation.width < -50 {
                                    withAnimation(.easeInOut(duration: 0.15)) { selectNextFile() }
                                } else if val.translation.width > 50 {
                                    withAnimation(.easeInOut(duration: 0.15)) { selectPreviousFile() }
                                }
                            }
                        }
                )
                
                // 3. Плавающая нижняя зона большого пальца (FloatingThumbZoneView)
                FloatingThumbZoneView(
                    rating: activeFile?.rating ?? 4,
                    selectedColorTag: activeFile?.colorTag ?? 1,
                    isTransferring: isImportActionInProgress || stats.inProgressCount > 0,
                    transferStatusText: "\(stats.importedCount)/\(max(stats.totalCount, 158)) (NEF) • 25MB/s • 34s rem.",
                    transferPercent: stats.totalCount > 0 ? Int(Double(stats.importedCount) / Double(stats.totalCount) * 100) : 42,
                    onRatingChanged: { newRating in
                        if let active = activeFile, let idx = usbManager.catalogFiles.firstIndex(where: { $0.id == active.id }) {
                            usbManager.catalogFiles[idx].rating = newRating
                        }
                    },
                    onColorTagChanged: { newTag in
                        if let active = activeFile, let idx = usbManager.catalogFiles.firstIndex(where: { $0.id == active.id }) {
                            usbManager.catalogFiles[idx].colorTag = newTag >= 0 ? newTag : nil
                        }
                    },
                    onExport: {
                        guard let active = activeFile else { return }
                        exportActiveFileToPhotos(active)
                    },
                    onTransferTap: {
                        guard !isImportActionInProgress else { return }
                        isImportActionInProgress = true
                        Task {
                            defer { isImportActionInProgress = false }
                            await usbManager.importAllUnimported()
                        }
                    },
                    onCancelTransfer: {
                        if let active = activeFile {
                            Task {
                                await usbManager.cancelTransfer(compositeID: active.id)
                            }
                        }
                    }
                )
                .padding(.bottom, 10)
            }
        }
    }
    
    // MARK: - Центральное изображение кадра
    
    @ViewBuilder
    private func mainImageView(for item: CameraFileItem, size: CGSize) -> some View {
        Group {
            if let thumb = item.thumbnail {
                #if canImport(UIKit)
                Image(uiImage: UIImage(cgImage: thumb))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: max(size.width - 24, 100), maxHeight: max(size.height - 24, 100))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 6)
                #elseif canImport(AppKit)
                Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: size.width, height: size.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: max(size.width - 24, 100), maxHeight: max(size.height - 24, 100))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 6)
                #else
                Image(decorative: thumb, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: max(size.width - 24, 100), maxHeight: max(size.height - 24, 100))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                #endif
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Чтение снимка с карты...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    usbManager.requestThumbnail(for: item)
                }
            }
        }
    }
    
    @ViewBuilder
    private func mainImageContent(for item: CameraFileItem) -> some View {
        if let thumb = item.thumbnail {
            #if canImport(UIKit)
            Image(uiImage: UIImage(cgImage: thumb))
                .resizable()
                .aspectRatio(contentMode: .fit)
            #elseif canImport(AppKit)
            Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 200, height: 200)))
                .resizable()
                .aspectRatio(contentMode: .fit)
            #else
            Image(decorative: thumb, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #endif
        } else {
            Color.gray.opacity(0.3)
        }
    }
    
    // MARK: - Нижняя горизонтальная лента кадров (Filmstrip)
    
    private var filmstripBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(filteredFiles) { file in
                        CameraFilmstripTile(
                            item: file,
                            isActive: activeFile?.id == file.id,
                            isSelected: selectedFileIDs.contains(file.id),
                            onTap: {
                                activeFileID = file.id
                            },
                            onToggleSelect: {
                                toggleSelect(file)
                            },
                            onRequestThumbnail: {
                                usbManager.requestThumbnail(for: file)
                            }
                        )
                        .id(file.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .frame(height: 94)
            .background(
                Color(red: 18/255.0, green: 20/255.0, blue: 24/255.0).opacity(0.85)
                    .background(.ultraThinMaterial)
            )
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1),
                alignment: .top
            )
            .onChange(of: activeFileID) { _, newID in
                if let id = newID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let id = activeFile?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder
    private func galleryStatusBadge(for status: CameraFileImportStatus) -> some View {
        switch status {
        case .imported:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Загружен").font(.caption2.bold()).foregroundColor(.green)
            }
        case .queued:
            HStack(spacing: 4) {
                Image(systemName: "clock.fill").foregroundColor(.blue)
                Text("В очереди").font(.caption2.bold()).foregroundColor(.blue)
            }
        case .importing(let progress):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("\(Int(progress * 100))%").font(.caption2.bold()).foregroundColor(.orange)
            }
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                Text("Ошибка").font(.caption2.bold()).foregroundColor(.red)
            }
        case .notImported:
            EmptyView()
        }
    }
    
    // MARK: - Секция действий импорта (перенесена в верхнюю часть окна)
    
    @ViewBuilder
    private var importActionsSection: some View {
        if usbManager.isCatalogReady {
            if selectedStats.count > 0 {
                // Панель выбранных фотографий
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        selectedInfoLabel
                        
                        deselectButton
                        
                        Spacer()
                        
                        importSelectedButton
                        
                        downloadAllButton(isProminent: false)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            selectedInfoLabel
                            deselectButton
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            importSelectedButton
                            downloadAllButton(isProminent: false)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(cardBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Когда ничего не выбрано — аккуратная уменьшенная кнопка «Загрузить все доступные»
                HStack {
                    downloadAllButton(isProminent: true)
                    Spacer()
                }
            }
        }
    }
    
    private var selectedInfoLabel: some View {
        let (count, bytes) = selectedStats
        return HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentColor)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 1) {
                Text("Выбрано: \(count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var deselectButton: some View {
        Button("Снять") {
            selectedFileIDs.removeAll()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    private var importSelectedButton: some View {
        let count = selectedStats.count
        return Button {
            guard !isImportActionInProgress else { return }
            isImportActionInProgress = true
            let toImport = usbManager.catalogFiles.filter { selectedFileIDs.contains($0.id) }
            Task {
                defer { isImportActionInProgress = false }
                await usbManager.importSelectedFiles(toImport)
                selectedFileIDs.removeAll()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Загрузить выбранные (\(count))")
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(!usbManager.isConnected || !usbManager.isCatalogReady || count == 0 || isImportActionInProgress || usbManager.isBatchSchedulingInProgress)
    }
    
    @ViewBuilder
    private func downloadAllButton(isProminent: Bool) -> some View {
        let btn = Button {
            guard !isImportActionInProgress else { return }
            isImportActionInProgress = true
            Task {
                defer { isImportActionInProgress = false }
                if stats.failedCount > 0 && stats.unimportedCount == 0 && stats.inProgressCount == 0 {
                    await usbManager.retryAllFailed()
                } else if formatFilter != .all {
                    await usbManager.importFilteredUnimported(matching: formatFilter)
                } else {
                    await usbManager.importAllUnimported()
                }
            }
        } label: {
            HStack(spacing: 6) {
                let s = stats
                let candidateCount = filteredCandidateFiles.count
                let candidateSize = formattedFilteredCandidateSize
                
                if !usbManager.isConnected {
                    Image(systemName: "tray.and.arrow.down.fill")
                    Text("Камера не подключена")
                        .fontWeight(.medium)
                } else if !usbManager.isCatalogReady {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Чтение оглавления...")
                        .fontWeight(.medium)
                } else if s.inProgressCount > 0 {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Импорт (\(s.inProgressCount))...")
                        .fontWeight(.medium)
                } else if s.failedCount > 0 && s.unimportedCount == 0 {
                    Image(systemName: "arrow.clockwise")
                    Text("Повторить ошибочные (\(s.failedCount))")
                        .fontWeight(.semibold)
                } else if candidateCount > 0 {
                    Image(systemName: "tray.and.arrow.down.fill")
                    switch formatFilter {
                    case .all:
                        Text("Загрузить все доступные (\(candidateCount) ф., \(candidateSize))")
                            .fontWeight(.medium)
                    case .rawOnly:
                        Text("Загрузить RAW (\(candidateCount) ф., \(candidateSize))")
                            .fontWeight(.medium)
                    case .companionOnly:
                        Text("Загрузить JPEG (\(candidateCount) ф., \(candidateSize))")
                            .fontWeight(.medium)
                    }
                } else {
                    Image(systemName: "checkmark")
                    Text("Все файлы загружены")
                        .fontWeight(.medium)
                }
            }
        }
        .disabled(
            !usbManager.isConnected ||
            !usbManager.isCatalogReady ||
            stats.inProgressCount > 0 ||
            isImportActionInProgress ||
            usbManager.isBatchSchedulingInProgress ||
            (filteredCandidateFiles.isEmpty && stats.failedCount == 0)
        )
        
        if isProminent {
            btn
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        } else {
            btn
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Элемент строки карточки списка в стиле Liquid Glass

public struct CameraGlassListRow: View, Equatable {
    public let item: CameraFileItem
    public let isSelected: Bool
    public let isActive: Bool
    public let onToggleSelect: () -> Void
    public let onInspect: () -> Void
    public let onRequestThumbnail: () -> Void
    public let onRetry: () -> Void
    
    public init(
        item: CameraFileItem,
        isSelected: Bool,
        isActive: Bool,
        onToggleSelect: @escaping () -> Void,
        onInspect: @escaping () -> Void,
        onRequestThumbnail: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.isActive = isActive
        self.onToggleSelect = onToggleSelect
        self.onInspect = onInspect
        self.onRequestThumbnail = onRequestThumbnail
        self.onRetry = onRetry
    }
    
    public static func == (lhs: CameraGlassListRow, rhs: CameraGlassListRow) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isActive == rhs.isActive &&
        lhs.item.status == rhs.item.status &&
        lhs.item.rating == rhs.item.rating &&
        (lhs.item.thumbnail != nil) == (rhs.item.thumbnail != nil)
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Чекбокс выбора
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : Color.white.opacity(0.45))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            // Превью кадра с бейджем формата
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumb = item.thumbnail {
                        #if canImport(UIKit)
                        Image(uiImage: UIImage(cgImage: thumb))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #elseif canImport(AppKit)
                        Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 72, height: 50)))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #else
                        Image(decorative: thumb, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #endif
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.18))
                            .overlay(
                                Image(systemName: item.isRAW ? "camera.fill" : "photo")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            )
                    }
                }
                .frame(width: 72, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear {
                    if item.thumbnail == nil {
                        onRequestThumbnail()
                    }
                }
                
                // Бейдж формата в углу превью
                Text(item.isRAW ? "RAW" : "JPG")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(item.isRAW ? Color.purple.opacity(0.85) : Color.blue.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
            
            // Метаданные файла
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    
                    if let date = item.creationDate {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
                
                // Рейтинг
                if item.rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= item.rating ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundStyle(star <= item.rating ? AppTheme.Colors.ratingActive : Color.white.opacity(0.2))
                        }
                    }
                    .padding(.top, 1)
                }
            }
            
            Spacer()
            
            // Статус импорта
            statusBadge(for: item.status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? AppTheme.Colors.accent.opacity(0.12) : Color.white.opacity(0.06))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isActive ? AppTheme.Colors.accent.opacity(0.6) : Color.white.opacity(0.12),
                    lineWidth: isActive ? 1.5 : 0.8
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onInspect()
        }
    }
    
    @ViewBuilder
    private func statusBadge(for status: CameraFileImportStatus) -> some View {
        switch status {
        case .imported:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Загружен")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AppTheme.Colors.statusGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.Colors.statusGreen.opacity(0.15))
            .clipShape(Capsule())
            
        case .importing(let progress):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).tint(AppTheme.Colors.accent)
                Text("\(Int(progress * 100))%")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.Colors.accent.opacity(0.15))
            .clipShape(Capsule())
            
        case .queued:
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("В очереди")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.cyan)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.cyan.opacity(0.15))
            .clipShape(Capsule())

            
        case .failed:
            Button(action: onRetry) {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                    Text("Повтор")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.Colors.statusRed)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.Colors.statusRed.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
        case .notImported:
            Text("Новый")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Элемент строки каталога с поддержкой Equatable для плавной работы при 1000+ файлах

public struct CameraFileRowView: View, Equatable {

    public let item: CameraFileItem
    public let isSelected: Bool
    public let onToggleSelect: () -> Void
    public let onRetry: () -> Void
    public let onRequestThumbnail: () -> Void
    
    public init(
        item: CameraFileItem,
        isSelected: Bool,
        onToggleSelect: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onRequestThumbnail: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onToggleSelect = onToggleSelect
        self.onRetry = onRetry
        self.onRequestThumbnail = onRequestThumbnail
    }
    
    public static func == (lhs: CameraFileRowView, rhs: CameraFileRowView) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.item.status == rhs.item.status &&
        lhs.isSelected == rhs.isSelected &&
        (lhs.item.thumbnail != nil) == (rhs.item.thumbnail != nil)
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Чекбокс выбора
            if item.status == .notImported {
                Button {
                    onToggleSelect()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                statusLeadingIcon(for: item.status)
                    .frame(width: 24)
            }
            
            // Миниатюра из ImageCaptureCore (GetThumb PTP, без скачивания полного файла)
            Group {
                if let thumb = item.thumbnail {
                    #if canImport(UIKit)
                    Image(uiImage: UIImage(cgImage: thumb))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #elseif canImport(AppKit)
                    Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 48, height: 48)))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #else
                    Image(decorative: thumb, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(
                            Image(systemName: item.isRAW ? "camera.fill" : "photo")
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onAppear {
                if item.thumbnail == nil {
                    onRequestThumbnail()
                }
            }
            
            // Имя файла и метаданные
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.filename)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if item.isRAW {
                        Text("RAW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text("JPEG")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                HStack(spacing: 8) {
                    Text(item.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let date = item.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if case .failed(let err) = item.status {
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Статус и кнопка повтора при ошибке
            statusTrailingBadge(for: item.status)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.status == .notImported {
                onToggleSelect()
            }
        }
    }
    
    @ViewBuilder
    private func statusLeadingIcon(for status: CameraFileImportStatus) -> some View {
        switch status {
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        case .queued:
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.blue)
                .font(.title3)
        case .importing:
            ProgressView()
                .scaleEffect(0.8)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.title3)
        case .notImported:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func statusTrailingBadge(for status: CameraFileImportStatus) -> some View {
        switch status {
        case .imported:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                Text("Загружен")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.15))
            .foregroundColor(.green)
            .clipShape(Capsule())
            
        case .queued:
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.caption2)
                Text("В очереди")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.15))
            .foregroundColor(.blue)
            .clipShape(Capsule())
            
        case .importing(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.orange)
            .clipShape(Capsule())
            
        case .failed:
            Button {
                onRetry()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Повторить")
                }
                .font(.caption2)
                .fontWeight(.bold)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            
        case .notImported:
            Text("Доступен")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Элемент миниатюры горизонтальной ленты галереи (Filmstrip)

public struct CameraFilmstripTile: View, Equatable {
    public let item: CameraFileItem
    public let isActive: Bool
    public let isSelected: Bool
    public let onTap: () -> Void
    public let onToggleSelect: () -> Void
    public let onRequestThumbnail: () -> Void
    
    public init(
        item: CameraFileItem,
        isActive: Bool,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        onToggleSelect: @escaping () -> Void,
        onRequestThumbnail: @escaping () -> Void
    ) {
        self.item = item
        self.isActive = isActive
        self.isSelected = isSelected
        self.onTap = onTap
        self.onToggleSelect = onToggleSelect
        self.onRequestThumbnail = onRequestThumbnail
    }
    
    public static func == (lhs: CameraFilmstripTile, rhs: CameraFilmstripTile) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.isActive == rhs.isActive &&
        lhs.isSelected == rhs.isSelected &&
        lhs.item.rating == rhs.item.rating &&
        lhs.item.status == rhs.item.status &&
        (lhs.item.thumbnail != nil) == (rhs.item.thumbnail != nil)
    }
    
    public var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Превью снимка
                Group {
                    if let thumb = item.thumbnail {
                        #if canImport(UIKit)
                        Image(uiImage: UIImage(cgImage: thumb))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 56)
                            .clipped()
                        #elseif canImport(AppKit)
                        Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 80, height: 56)))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 56)
                            .clipped()
                        #else
                        Image(decorative: thumb, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 56)
                            .clipped()
                        #endif
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.22))
                            .frame(width: 80, height: 56)
                            .overlay(
                                Image(systemName: item.isRAW ? "camera" : "photo")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.4))
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Бейдж рейтинга со звездами (в точности по референсу iPad)
                HStack(spacing: 2) {
                    if item.rating > 0 {
                        Text("\(item.rating)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.ratingActive)
                    }
                    HStack(spacing: 1) {
                        ForEach(0..<max(1, min(item.rating > 0 ? item.rating : 4, 5)), id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(AppTheme.Colors.ratingActive)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.70))
                .clipShape(Capsule())
                .padding(3)
                
                // Бейджи статуса загрузки и выбора (внизу слева)
                VStack {
                    Spacer()
                    HStack {
                        statusOrSelectionBadge
                            .padding(3)
                        Spacer()
                    }
                }
            }
            .frame(width: 80, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.white.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? AppTheme.Colors.accent : (isSelected ? AppTheme.Colors.accent.opacity(0.8) : Color.white.opacity(0.12)),
                        lineWidth: isActive ? 2.5 : (isSelected ? 1.5 : 1)
                    )
            )
            .shadow(color: isActive ? AppTheme.Colors.accent.opacity(0.40) : Color.clear, radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if item.thumbnail == nil {
                onRequestThumbnail()
            }
        }
    }
    
    @ViewBuilder
    private var statusOrSelectionBadge: some View {
        switch item.status {
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.green)
                .background(Circle().fill(Color.black.opacity(0.6)))
        case .queued:
            Image(systemName: "clock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.blue)
                .background(Circle().fill(Color.black.opacity(0.6)))
        case .importing:
            ProgressView()
                .controlSize(.mini)
                .padding(2)
                .background(Circle().fill(Color.black.opacity(0.6)))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.red)
                .background(Circle().fill(Color.black.opacity(0.6)))
        case .notImported:
            if isSelected {
                Button(action: onToggleSelect) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

