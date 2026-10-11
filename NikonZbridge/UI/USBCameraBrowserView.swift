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
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color.secondary.opacity(0.08)
        #endif
    }
    
    private var cardBackgroundColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemBackground)
        #else
        return Color.secondary.opacity(0.12)
        #endif
    }
    
    public var body: some View {
        Group {
            VStack(spacing: 0) {
                // Верхняя информационная карточка управления импортом
                headerSection
                    .padding()
                    .background(sheetBackgroundColor)
                
                Divider()
                
                // Фильтр форматов и панель быстрого выбора
                filterAndSelectionBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(sheetBackgroundColor.opacity(0.7))
                
                Divider()
                
                // Список или Галерея файлов карты памяти с виртуализацией
                if filteredFiles.isEmpty {
                    emptyStateView
                } else {
                    switch viewMode {
                    case .list:
                        fileListView
                    case .gallery:
                        galleryFilmstripView
                    }
                }
                
                // Закрепленная нижняя панель при наличии выделенных файлов
                if selectedStats.count > 0 {
                    pinnedSelectionBar
                }
            }
            .task {
                await usbManager.updateTargetSessionName()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Импорт с камеры").font(.headline)
                Spacer()
                Button {
                    Task { await usbManager.refreshCatalog() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .disabled(!usbManager.isConnected || !usbManager.isCatalogReady)
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
                        Text("Вычитывание оглавления карты памяти...")
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
            
            // Основная кнопка импорта
            Button {
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
                HStack(spacing: 8) {
                    let s = stats
                    let candidateCount = filteredCandidateFiles.count
                    let candidateSize = formattedFilteredCandidateSize
                    
                    if !usbManager.isConnected {
                        Image(systemName: "tray.and.arrow.down.fill")
                        Text("Камера не подключена")
                            .fontWeight(.medium)
                    } else if !usbManager.isCatalogReady {
                        ProgressView()
                            .controlSize(.small)
                        Text("Чтение оглавления карты...")
                            .fontWeight(.medium)
                    } else if s.inProgressCount > 0 {
                        ProgressView()
                            .controlSize(.small)
                        Text("Идёт импорт (\(s.inProgressCount) активных)...")
                            .fontWeight(.medium)
                    } else if s.failedCount > 0 && s.unimportedCount == 0 {
                        Image(systemName: "arrow.clockwise")
                        Text("Повторить ошибочные (\(s.failedCount))")
                            .fontWeight(.bold)
                    } else if candidateCount > 0 {
                        Image(systemName: "tray.and.arrow.down.fill")
                        switch formatFilter {
                        case .all:
                            Text("Загрузить все доступные (\(candidateCount) файлов, \(candidateSize))")
                                .fontWeight(.bold)
                        case .rawOnly:
                            Text("Загрузить RAW (\(candidateCount) файлов, \(candidateSize))")
                                .fontWeight(.bold)
                        case .companionOnly:
                            Text("Загрузить JPEG (\(candidateCount) файлов, \(candidateSize))")
                                .fontWeight(.bold)
                        }
                    } else {
                        Image(systemName: "checkmark")
                        switch formatFilter {
                        case .all:
                            Text("Все файлы загружены")
                                .fontWeight(.medium)
                        case .rawOnly:
                            Text("Все RAW файлы уже загружены")
                                .fontWeight(.medium)
                        case .companionOnly:
                            Text("Все JPEG файлы уже загружены")
                                .fontWeight(.medium)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                !usbManager.isConnected ||
                !usbManager.isCatalogReady ||
                stats.inProgressCount > 0 ||
                isImportActionInProgress ||
                usbManager.isBatchSchedulingInProgress ||
                (filteredCandidateFiles.isEmpty && stats.failedCount == 0)
            )
            
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
                    Text("Чтение оглавления карты памяти...")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(usbManager.cameraName ?? "Nikon Z"): идет вычитывание списка файлов с карты памяти...")
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
    
    private var fileListView: some View {
        List {
            ForEach(filteredFiles) { item in
                CameraFileRowView(
                    item: item,
                    isSelected: selectedFileIDs.contains(item.id),
                    onToggleSelect: {
                        if selectedFileIDs.contains(item.id) {
                            selectedFileIDs.remove(item.id)
                        } else {
                            selectedFileIDs.insert(item.id)
                        }
                    },
                    onRetry: {
                        Task {
                            await usbManager.retryTransfer(for: item)
                        }
                    },
                    onRequestThumbnail: {
                        usbManager.requestThumbnail(for: item)
                    }
                )
                .equatable()
            }
        }
        .listStyle(.plain)
    }
    
    private var galleryFilmstripView: some View {
        VStack(spacing: 0) {
            // Центральная большая область просмотра выбранного кадра
            mainViewerArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Нижняя горизонтальная лента миниатюр
            filmstripBar
        }
    }
    
    @ViewBuilder
    private var mainViewerArea: some View {
        if let item = activeFile {
            GeometryReader { geo in
                ZStack {
                    // Темный матовый фон (как в Finder / Apple Photos Gallery)
                    Color(white: 0.10)
                        .ignoresSafeArea()
                    
                    // Крупное изображение
                    Group {
                        if let thumb = item.thumbnail {
                            #if canImport(UIKit)
                            Image(uiImage: UIImage(cgImage: thumb))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: max(geo.size.width - 24, 100), maxHeight: max(geo.size.height - 24, 100))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 3)
                            #elseif canImport(AppKit)
                            Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: geo.size.width, height: geo.size.height)))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: max(geo.size.width - 24, 100), maxHeight: max(geo.size.height - 24, 100))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 3)
                            #else
                            Image(decorative: thumb, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: max(geo.size.width - 24, 100), maxHeight: max(geo.size.height - 24, 100))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    
                    // Стрелки навигации Влево / Вправо
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectPreviousFile()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .disabled(activeFileIndex <= 0)
                        .opacity(activeFileIndex <= 0 ? 0.25 : 1.0)
                        .padding(.leading, 12)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectNextFile()
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .disabled(activeFileIndex >= filteredFiles.count - 1)
                        .opacity(activeFileIndex >= filteredFiles.count - 1 ? 0.25 : 1.0)
                        .padding(.trailing, 12)
                    }
                    
                    // Верхняя панель с кнопкой выбора и метаданными кадра
                    VStack {
                        HStack(spacing: 8) {
                            if item.status == .notImported {
                                Button {
                                    toggleSelect(item)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: selectedFileIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(selectedFileIDs.contains(item.id) ? .accentColor : .white)
                                        Text(selectedFileIDs.contains(item.id) ? "Выбран для импорта" : "Выбрать кадр")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                                }
                                .buttonStyle(.plain)
                            } else {
                                galleryStatusBadge(for: item.status)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                            }
                            
                            Spacer()
                            
                            // Счетчик кадров (например, 1 из 915)
                            Text("\(activeFileIndex + 1) из \(filteredFiles.count)")
                                .font(.caption2.bold())
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                            
                            // Имя файла, формат и размер
                            HStack(spacing: 6) {
                                Text(item.filename)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                
                                Text(item.isRAW ? "RAW" : "JPEG")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background((item.isRAW ? Color.purple : Color.blue).opacity(0.85))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                
                                Text(item.formattedSize)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                withAnimation(.easeInOut(duration: 0.15)) { selectNextFile() }
                            } else if value.translation.width > 40 {
                                withAnimation(.easeInOut(duration: 0.15)) { selectPreviousFile() }
                            }
                        }
                )
            }
        }
    }
    
    private var filmstripBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 82)
            .background(Color(white: 0.13))
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
    
    private var pinnedSelectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                let (count, bytes) = selectedStats
                VStack(alignment: .leading, spacing: 2) {
                    Text("Выбрано: \(count)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Снять") {
                    selectedFileIDs.removeAll()
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
                
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
                        Text("Загрузить выбранные (\(count))")
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .font(.subheadline)
                .disabled(!usbManager.isConnected || !usbManager.isCatalogReady || count == 0 || isImportActionInProgress || usbManager.isBatchSchedulingInProgress)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(sheetBackgroundColor)
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
        lhs.item.status == rhs.item.status &&
        (lhs.item.thumbnail != nil) == (rhs.item.thumbnail != nil)
    }
    
    public var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Превью снимка с сохранением естественных пропорций (fit)
                Group {
                    if let thumb = item.thumbnail {
                        #if canImport(UIKit)
                        Image(uiImage: UIImage(cgImage: thumb))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        #elseif canImport(AppKit)
                        Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 80, height: 56)))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        #else
                        Image(decorative: thumb, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        #endif
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.22))
                            .aspectRatio(3/2, contentMode: .fit)
                            .overlay(
                                Image(systemName: item.isRAW ? "camera" : "photo")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.4))
                            )
                    }
                }
                .frame(maxHeight: 54)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(3)
                
                // Бейджи статуса загрузки и выбора
                statusOrSelectionBadge
                    .padding(3)
            }
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color(white: 0.28) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isActive ? Color.white.opacity(0.9) : (isSelected ? Color.accentColor : Color.clear),
                        lineWidth: isActive ? 2 : (isSelected ? 1.5 : 0)
                    )
            )
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

