import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ExportSheetView: View {
    @ObservedObject var appState: AppState
    let groups: [CaptureGroup]
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDestinationType: DestinationType = .folder
    @State private var targetFolderURL: URL?
    @State private var targetFolderBookmark: Data?
    @State private var targetVolumeFreeBytes: Int64?
    
    @State private var formatSelection: ExportFormatSelection = .both
    @State private var conflictStrategy: NameConflictStrategy = .rename
    @State private var isShowingFolderPicker: Bool = false
    
    // XMP и метаданные сессии (Этап 12)
    @State private var includeXMPSidecars: Bool = true
    @State private var sidecarNamingConvention: XMPSidecarNamingConvention = .standardBasename
    @State private var includeSessionManifest: Bool = true
    @State private var sessionAuthor: String = ""
    @State private var sessionCopyright: String = ""
    @State private var sessionComment: String = ""
    @State private var isShowingGuide: Bool = false
    
    @State private var currentJob: ExportJob?
    @State private var isExporting: Bool = false
    @State private var isCompleted: Bool = false
    @State private var isShowingShareSheet: Bool = false
    @State private var shareSheetItems: [URL] = []
    
    enum DestinationType: String, CaseIterable, Identifiable {
        case folder = "Папка / SSD"
        case photos = "Медиатека «Фото»"
        case share = "Поделиться"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .folder: return "externaldrive.fill"
            case .photos: return "photo.on.rectangle.angled"
            case .share: return "square.and.arrow.up"
            }
        }
    }
    
    public init(appState: AppState, groups: [CaptureGroup]) {
        self.appState = appState
        self.groups = groups
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let job = currentJob {
                    progressView(job: job)
                } else {
                    configurationView
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Экспорт снимков")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isExporting ? "Отмена" : "Закрыть") {
                        if isExporting {
                            Task { await ExportManager.shared.cancel() }
                        }
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .fileImporter(
                isPresented: $isShowingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelected(result)
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(activityItems: shareSheetItems)
            }
            #endif
            .sheet(isPresented: $isShowingGuide) {
                XMPCompatibilityGuideView()
            }
        }
        .presentationDetents([.large])
        .onAppear {
            setupInitialFolder()
        }
    }
    
    // MARK: - Настройка папки по умолчанию
    
    private func setupInitialFolder() {
        if let autoURL = appState.autoExportDestinationURL {
            self.targetFolderURL = autoURL
            self.targetFolderBookmark = appState.autoExportBookmarkData
            updateAvailableSpace(for: autoURL)
        }
        self.sessionAuthor = appState.sessionAuthor
        self.sessionCopyright = appState.sessionCopyright
        self.sessionComment = appState.sessionComment
        self.includeXMPSidecars = appState.isXMPExportEnabled
        self.sidecarNamingConvention = appState.xmpNamingConvention
    }
    
    private func updateAvailableSpace(for url: URL) {
        let guard_ = DiskSpaceGuard()
        let free = guard_.availableFreeBytes(at: url)
        self.targetVolumeFreeBytes = free
    }
    
    // MARK: - 1. Экран конфигурации параметров экспорта
    
    private var configurationView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Сводка выбранных файлов
                summaryHeaderCard
                
                // Выбор места назначения
                destinationSection
                
                // Выбор формата файлов (RAW, Companion, Both)
                formatSelectionSection
                
                // Разрешение конфликтов имён
                if selectedDestinationType == .folder {
                    conflictStrategySection
                    
                    // Переключатель автокопирования (Live Mirror)
                    autoExportToggleSection
                }
                
                // XMP и метаданные сессии
                xmpAndMetadataSection
                
                Spacer(minLength: 24)
                
                // Кнопка запуска экспорта
                startExportButton
                    .padding(.bottom, 24)
            }
            .padding(16)
        }
    }
    
    // MARK: - Сводка
    
    private var summaryHeaderCard: some View {
        let assetsToExport = filteredAssetsToExport(format: formatSelection)
        let totalBytes = assetsToExport.reduce(0) { $0 + $1.fileSize }
        
        return HStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(groups.count) кадров (\(assetsToExport.count) файлов)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Общий объём: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Выбор места назначения
    
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("МЕСТО НАЗНАЧЕНИЯ")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                ForEach(DestinationType.allCases) { type in
                    Button {
                        selectedDestinationType = type
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 20))
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .background(selectedDestinationType == type ? Color.blue : Color.white.opacity(0.06))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            
            // Если выбрана папка / SSD
            if selectedDestinationType == .folder {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        isShowingFolderPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 16))
                            if let folder = targetFolderURL {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.lastPathComponent)
                                        .font(.system(size: 14, weight: .bold))
                                        .lineLimit(1)
                                    Text(folder.path)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else {
                                Text("Выбрать папку или внешний SSD...")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    if let free = targetVolumeFreeBytes {
                        HStack(spacing: 6) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 11))
                            Text("Доступно на носителе: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    }
                }
            }
        }
    }
    
    // MARK: - Выбор формата оригиналов
    
    private var formatSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ФОРМАТ ОРИГИНАЛОВ ДЛЯ ЭКСПОРТА")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Picker("Формат", selection: $formatSelection) {
                ForEach(ExportFormatSelection.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    // MARK: - Политика конфликтов имён
    
    private var conflictStrategySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПРИ СОВПАДЕНИИ ИМЁН ФАЙЛОВ")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Picker("Конфликты", selection: $conflictStrategy) {
                ForEach(NameConflictStrategy.allCases) { strat in
                    Text(strat.rawValue).tag(strat)
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Автокопирование (Live Mirror)
    
    private var autoExportToggleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { appState.isAutoExportEnabled },
                set: { enabled in
                    if enabled, let folder = targetFolderURL {
                        appState.enableAutoExport(url: folder, bookmarkData: targetFolderBookmark, format: formatSelection)
                    } else {
                        appState.disableAutoExport()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Автокопирование входящих снимков")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Копировать новые кадры на выбранный SSD в фоновом режиме")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(targetFolderURL == nil)
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    // MARK: - XMP и метаданные сессии
    
    private var xmpAndMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("XMP И МЕТАДАННЫЕ СЕССИИ")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    isShowingGuide = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("Справка")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
            
            Toggle(isOn: $includeXMPSidecars) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Экспортировать XMP Sidecar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Сохранять оценки (0–5★) и флаги Pick/Reject в сопутствующие файлы")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            if includeXMPSidecars {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Соглашение об именовании XMP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Именование XMP", selection: $sidecarNamingConvention) {
                        ForEach(XMPSidecarNamingConvention.allCases) { convention in
                            Text(convention.displayName).tag(convention)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 4)
            }
            
            if selectedDestinationType == .folder {
                Toggle(isOn: $includeSessionManifest) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Манифест и отчет сессии")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Генерировать session_manifest.json и session_report.md")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Метаданные автора и копирайта
            DisclosureGroup("Авторские метаданные (XMP)") {
                VStack(spacing: 8) {
                    TextField("Автор / Фотограф", text: $sessionAuthor)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                    
                    TextField("Копирайт (напр. © 2026 Studio)", text: $sessionCopyright)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                    
                    TextField("Комментарий к сессии", text: $sessionComment)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    // MARK: - Кнопка запуска
    
    private var startExportButton: some View {
        let assets = filteredAssetsToExport(format: formatSelection)
        let canStart = !assets.isEmpty && (selectedDestinationType != .folder || targetFolderURL != nil)
        
        return Button {
            startExport(assets: assets)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                Text("Экспортировать (\(assets.count) файлов)")
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canStart ? Color.blue : Color.gray.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canStart)
    }
    
    // MARK: - 2. Экран хода выполнения и результатов
    
    private func progressView(job: ExportJob) -> some View {
        VStack(spacing: 16) {
            // Верхний статус-бар
            VStack(spacing: 8) {
                HStack {
                    Text(jobStatusTitle(job: job))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(job.progressPercentage * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                
                ProgressView(value: job.progressPercentage)
                    .tint(.blue)
                
                HStack {
                    Text("Успешно: \(job.successItemsCount) из \(job.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(ByteCountFormatter.string(fromByteCount: job.exportedBytes, countStyle: .file)) из \(ByteCountFormatter.string(fromByteCount: job.totalBytes, countStyle: .file))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                
                // Сводка метаданных сессии и XMP sidecar
                if let result = job.result {
                    HStack(spacing: 8) {
                        if !result.exportedXMPURLs.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                    .font(.caption2)
                                Text("\(result.exportedXMPURLs.count) XMP")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        
                        if result.manifestURL != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.clipboard.fill")
                                    .font(.caption2)
                                Text("Манифест JSON")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        
                        if result.reportURL != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.richtext.fill")
                                    .font(.caption2)
                                Text("Отчёт MD")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Список каждого файла в очереди с его индивидуальным результатом
            List {
                ForEach(job.items) { item in
                    exportItemRow(item: item)
                        .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .listStyle(.plain)
            
            // Нижняя панель действий
            HStack(spacing: 12) {
                if isExporting {
                    Button(role: .destructive) {
                        Task { await ExportManager.shared.cancel() }
                    } label: {
                        Text("Остановить")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    if job.failedItemsCount > 0 {
                        Button {
                            retryFailedItems(in: job)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Повторить неудачные (\(job.failedItemsCount))")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange.opacity(0.25))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Готово")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Строка элемента в очереди
    
    private func exportItemRow(item: ExportItem) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: item.status)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let reason = item.errorMessage {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(item.asset.isRAW ? "RAW" : "JPG")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(item.asset.isRAW ? Color.orange : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func statusIcon(for status: ExportItemStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        case .exporting:
            ProgressView()
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
    
    private func jobStatusTitle(job: ExportJob) -> String {
        switch job.state {
        case .pending: return "Подготовка к экспорту..."
        case .inProgress: return "Экспорт файлов..."
        case .completed: return "Экспорт успешно завершён"
        case .failed(let reason): return reason
        case .cancelled: return "Экспорт отменён"
        }
    }
    
    // MARK: - Действия
    
    private func filteredAssetsToExport(format: ExportFormatSelection) -> [MediaAsset] {
        var assets: [MediaAsset] = []
        for group in groups {
            for asset in group.allAssets {
                if format.shouldExport(asset: asset) {
                    assets.append(asset)
                }
            }
        }
        return assets
    }
    
    private func handleFolderSelected(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else { return }
            
            // Начинаем доступ к security scoped ресурсу
            let isAccessing = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }
            
            let bookmark = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            self.targetFolderURL = selectedURL
            self.targetFolderBookmark = bookmark
            updateAvailableSpace(for: selectedURL)
        } catch {
            print("Ошибка получения доступа к папке: \(error)")
        }
    }
    
    private func startExport(assets: [MediaAsset]) {
        let destination: ExportDestination
        switch selectedDestinationType {
        case .folder:
            guard let folder = targetFolderURL else { return }
            destination = .directory(url: folder, bookmarkData: targetFolderBookmark)
        case .photos:
            destination = .photoLibrary()
        case .share:
            destination = .shareSheet
        }
        
        // Сохраняем введенные метаданные сессии
        appState.saveSessionMetadata(
            author: sessionAuthor.isEmpty ? nil : sessionAuthor,
            copyright: sessionCopyright.isEmpty ? nil : sessionCopyright,
            comment: sessionComment.isEmpty ? nil : sessionComment
        )
        appState.isXMPExportEnabled = includeXMPSidecars
        appState.xmpNamingConvention = sidecarNamingConvention
        
        let sessionMeta = SessionMetadata(
            sessionName: appState.currentSession?.name ?? "Сессия",
            author: sessionAuthor.isEmpty ? nil : sessionAuthor,
            copyright: sessionCopyright.isEmpty ? nil : sessionCopyright,
            comment: sessionComment.isEmpty ? nil : sessionComment
        )
        
        let items = assets.map { ExportItem(asset: $0) }
        let job = ExportJob(
            items: items,
            destination: destination,
            formatSelection: formatSelection,
            conflictStrategy: conflictStrategy,
            includeXMPSidecars: includeXMPSidecars,
            sidecarNamingConvention: sidecarNamingConvention,
            includeSessionManifest: (selectedDestinationType == .folder) && includeSessionManifest,
            sessionMetadata: sessionMeta
        )
        
        self.currentJob = job
        self.isExporting = true
        
        Task {
            let completedJob = await ExportManager.shared.executeJob(job) { updatedJob in
                DispatchQueue.main.async {
                    self.currentJob = updatedJob
                }
            }
            
            await MainActor.run {
                self.currentJob = completedJob
                self.isExporting = false
                self.isCompleted = true
                
                if selectedDestinationType == .share, case .completed(let urls) = completedJob.state {
                    self.shareSheetItems = urls
                    self.isShowingShareSheet = true
                }
            }
        }
    }
    
    private func retryFailedItems(in job: ExportJob) {
        self.isExporting = true
        Task {
            let updatedJob = await ExportManager.shared.retryFailed(in: job) { progressJob in
                DispatchQueue.main.async {
                    self.currentJob = progressJob
                }
            }
            await MainActor.run {
                self.currentJob = updatedJob
                self.isExporting = false
            }
        }
    }
}

// MARK: - Платформенный презентер Share Sheet для iOS

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
