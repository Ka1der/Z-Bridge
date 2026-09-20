import SwiftUI
import CoreGraphics

/// Режим фильтрации по формату файлов на карте памяти
public enum CameraFileFormatFilter: String, CaseIterable, Identifiable {
    case all = "Все"
    case rawOnly = "Только RAW"
    case companionOnly = "Только Companion/JPEG"
    
    public var id: String { rawValue }
}

/// Статистика оглавления карты памяти
public struct CameraCatalogStats: Equatable, Sendable {
    public let totalCount: Int
    public let totalBytes: Int64
    public let unimportedCount: Int
    public let unimportedBytes: Int64
    public let importedCount: Int
    public let importedBytes: Int64
    public let inProgressCount: Int
    public let failedCount: Int
    
    public init(
        totalCount: Int = 0,
        totalBytes: Int64 = 0,
        unimportedCount: Int = 0,
        unimportedBytes: Int64 = 0,
        importedCount: Int = 0,
        importedBytes: Int64 = 0,
        inProgressCount: Int = 0,
        failedCount: Int = 0
    ) {
        self.totalCount = totalCount
        self.totalBytes = totalBytes
        self.unimportedCount = unimportedCount
        self.unimportedBytes = unimportedBytes
        self.importedCount = importedCount
        self.importedBytes = importedBytes
        self.inProgressCount = inProgressCount
        self.failedCount = failedCount
    }
    
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public var formattedUnimportedSize: String {
        ByteCountFormatter.string(fromByteCount: unimportedBytes, countStyle: .file)
    }
}

/// Экран «Импорт с камеры» — специализированный интерфейс пакетного и выборочного переноса с карты памяти
@MainActor
public struct USBCameraBrowserView: View {
    @ObservedObject var usbManager: USBCameraManager
    public var sessionName: String?
    @Environment(\.dismiss) private var dismiss
    
    @State private var formatFilter: CameraFileFormatFilter = .all
    @State private var selectedFileIDs: Set<String> = []
    @State private var isSettingsExpanded: Bool = false
    
    public init(
        usbManager: USBCameraManager,
        sessionName: String? = nil
    ) {
        self.usbManager = usbManager
        self.sessionName = sessionName
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
        var total = 0
        var totalBytes: Int64 = 0
        var unimported = 0
        var unimportedBytes: Int64 = 0
        var imported = 0
        var importedBytes: Int64 = 0
        var inProgress = 0
        var failed = 0
        
        for item in usbManager.catalogFiles {
            total += 1
            totalBytes += item.fileSize
            switch item.status {
            case .notImported:
                unimported += 1
                unimportedBytes += item.fileSize
            case .imported:
                imported += 1
                importedBytes += item.fileSize
            case .queued, .importing:
                inProgress += 1
            case .failed:
                failed += 1
            }
        }
        return CameraCatalogStats(
            totalCount: total,
            totalBytes: totalBytes,
            unimportedCount: unimported,
            unimportedBytes: unimportedBytes,
            importedCount: imported,
            importedBytes: importedBytes,
            inProgressCount: inProgress,
            failedCount: failed
        )
    }
    
    private var filteredFiles: [CameraFileItem] {
        usbManager.catalogFiles.filter { item in
            switch formatFilter {
            case .all:
                return true
            case .rawOnly:
                return item.isRAW
            case .companionOnly:
                return !item.isRAW
            }
        }
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
        NavigationStack {
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
                
                // Список файлов карты памяти с виртуализацией
                if filteredFiles.isEmpty {
                    emptyStateView
                } else {
                    fileListView
                }
                
                // Закрепленная нижняя панель при наличии выделенных файлов
                if selectedStats.count > 0 {
                    pinnedSelectionBar
                }
            }
            .navigationTitle("Импорт с камеры")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                if usbManager.isDownloading {
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Импорт в фоне...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await usbManager.refreshCatalog()
                        }
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .disabled(!usbManager.isConnected || !usbManager.isCatalogReady)
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
                Text("Целевая сессия:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(currentTargetSessionName)
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
                Task {
                    if stats.failedCount > 0 && stats.unimportedCount == 0 && stats.inProgressCount == 0 {
                        await usbManager.retryAllFailed()
                    } else {
                        await usbManager.importAllUnimported()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    let s = stats
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
                    } else if s.unimportedCount > 0 {
                        Image(systemName: "tray.and.arrow.down.fill")
                        Text("Загрузить \(s.unimportedCount) файлов (\(s.formattedUnimportedSize))")
                            .fontWeight(.bold)
                    } else {
                        Image(systemName: "checkmark")
                        Text("Все файлы загружены")
                            .fontWeight(.medium)
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
                (stats.unimportedCount == 0 && stats.failedCount == 0)
            )
            
            // Раскрывающиеся независимые настройки автозагрузки
            DisclosureGroup(
                isExpanded: $isSettingsExpanded,
                content: {
                    VStack(spacing: 10) {
                        Toggle(isOn: $usbManager.isAutoDownloadNewShotsEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Автозагрузка новых кадров (live tethering)")
                                    .font(.subheadline)
                                Text("Автоматически скачивать новые снимки при съемке")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $usbManager.isAutoDownloadCardOnConnectEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Автозагрузка карты памяти при подключении")
                                    .font(.subheadline)
                                Text("Автоматически ставить в очередь все кадры с карты при подключении USB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
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
                    Text("Карта готова")
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
        HStack {
            Picker("Формат", selection: $formatFilter) {
                ForEach(CameraFileFormatFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            
            Spacer()
            
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
                    let toImport = usbManager.catalogFiles.filter { selectedFileIDs.contains($0.id) }
                    Task {
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
                .disabled(!usbManager.isConnected || !usbManager.isCatalogReady || count == 0)
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
