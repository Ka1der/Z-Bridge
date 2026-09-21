import SwiftUI

/// Профессиональный просмотрщик кадра по макету Liquid Glass
public struct PhotoDetailView: View {
    let group: CaptureGroup
    var appState: AppState?
    public var showsTopHUD: Bool = false
    var onRatingChanged: ((Int) -> Void)?
    var onPickStatusChanged: ((PickStatus) -> Void)?
    var onInspectionChanged: ((Bool) -> Void)?
    var onOpenCompare: (() -> Void)?
    
    @State private var activeAsset: MediaAsset?
    @State private var previewState: PreviewState = .idle
    @State private var exifData: [String: Any]?
    @State private var isShowingEXIFSheet = false
    @State private var isShowingPreviewNotice = false
    
    // Состояние панорамирования и зума
    @State private var currentZoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var basePanOffset: CGSize = .zero
    
    public init(
        group: CaptureGroup,
        appState: AppState? = nil,
        showsTopHUD: Bool = false,
        onRatingChanged: ((Int) -> Void)? = nil,
        onPickStatusChanged: ((PickStatus) -> Void)? = nil,
        onInspectionChanged: ((Bool) -> Void)? = nil,
        onOpenCompare: (() -> Void)? = nil
    ) {
        self.group = group
        self.appState = appState
        self.showsTopHUD = showsTopHUD
        self.onRatingChanged = onRatingChanged
        self.onPickStatusChanged = onPickStatusChanged
        self.onInspectionChanged = onInspectionChanged
        self.onOpenCompare = onOpenCompare
    }
    
    /// Инициализатор совместимости с одиночным IngestedFile
    public init(file: IngestedFile, appState: AppState? = nil, showsTopHUD: Bool = false) {
        if let asset = file.mediaAsset {
            self.group = CaptureGroup(asset: asset)
        } else {
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration,
                rating: file.rating,
                pickStatus: file.pickStatus
            )
            self.group = CaptureGroup(asset: asset)
        }
        self.appState = appState
        self.showsTopHUD = showsTopHUD
    }
    
    private var currentAsset: MediaAsset? {
        activeAsset ?? group.primaryAsset
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Верхняя плашка (если включена)
            if showsTopHUD {
                floatingHUD
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.xs)
            }
            
            // Основная область фотографии: aspectRatio(.fit) — никогда не обрезается!
            GeometryReader { geo in
                ZStack {
                    switch previewState {
                    case .success(let preview):
                        imageContentView(preview: preview, geoSize: geo.size)
                        
                    case .loading, .idle:
                        VStack(spacing: 10) {
                            ProgressView()
                                .tint(AppTheme.Colors.accent)
                            Text("Декодирование превью...")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        
                    case .failure(let error):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(AppTheme.Colors.statusOrange)
                            
                            VStack(spacing: 4) {
                                Text("Не удалось отобразить превью")
                                    .font(AppTheme.Typography.headline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                
                                Text(error.localizedDescription)
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            
                            Button {
                                loadCurrentPreview()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Повторить")
                                }
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AppTheme.Colors.accent)
                                .clipShape(Capsule())
                            }
                            .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Нижняя панель действий кадра (вынесена под фото, не накладывается на изображение)
            actionsCard
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xs)
        }
        .background(AppTheme.Colors.photoBackground.ignoresSafeArea())
        .sheet(isPresented: $isShowingEXIFSheet) {
            exifDetailSheet
        }
        .alert("Качество превью", isPresented: $isShowingPreviewNotice) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Для мгновенного отклика при беспроводной и проводной съемке отображается встроенное JPEG-превью камеры. Полное разрешение RAW-сенсора доступно для экспорта и детальной обработки.")
        }
        .task(id: "\(group.id)_\(currentAsset?.id.uuidString ?? "")") {
            loadCurrentPreview()
        }
        .onDisappear {
            updateInspectionState(isInspecting: false)
        }
    }
    
    // MARK: - Image Content View with Pan and Zoom
    
    @ViewBuilder
    private func imageContentView(preview: PlatformImage, geoSize: CGSize) -> some View {
        let maxPanX = max(0, (geoSize.width * currentZoom - geoSize.width) / 2)
        let maxPanY = max(0, (geoSize.height * currentZoom - geoSize.height) / 2)
        
        #if canImport(UIKit)
        Image(uiImage: preview)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(max(1.0, currentZoom))
            .offset(panOffset)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { val in
                        currentZoom = max(1.0, min(8.0, baseZoom * val))
                        updateInspectionState(isInspecting: currentZoom > 1.05)
                    }
                    .onEnded { val in
                        baseZoom = max(1.0, min(currentZoom, 8.0))
                        if baseZoom <= 1.05 {
                            withAnimation(.spring(response: 0.25)) {
                                currentZoom = 1.0
                                baseZoom = 1.0
                                panOffset = .zero
                                basePanOffset = .zero
                            }
                            updateInspectionState(isInspecting: false)
                        } else {
                            currentZoom = baseZoom
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { val in
                        guard currentZoom > 1.05 else { return }
                        let proposedX = basePanOffset.width + val.translation.width
                        let proposedY = basePanOffset.height + val.translation.height
                        panOffset = CGSize(
                            width: min(maxPanX, max(-maxPanX, proposedX)),
                            height: min(maxPanY, max(-maxPanY, proposedY))
                        )
                        updateInspectionState(isInspecting: true)
                    }
                    .onEnded { _ in
                        basePanOffset = panOffset
                    }
            )
            .onTapGesture(count: 2) { location in
                withAnimation(.spring(response: 0.25)) {
                    if currentZoom > 1.05 {
                        currentZoom = 1.0
                        baseZoom = 1.0
                        panOffset = .zero
                        basePanOffset = .zero
                        updateInspectionState(isInspecting: false)
                    } else {
                        let targetZoom: CGFloat = 2.5
                        currentZoom = targetZoom
                        baseZoom = targetZoom
                        
                        // Смещение в точку двойного касания
                        let offsetX = (geoSize.width / 2.0 - location.x) * (targetZoom - 1.0)
                        let offsetY = (geoSize.height / 2.0 - location.y) * (targetZoom - 1.0)
                        let newMaxX = max(0, (geoSize.width * targetZoom - geoSize.width) / 2)
                        let newMaxY = max(0, (geoSize.height * targetZoom - geoSize.height) / 2)
                        let clamped = CGSize(
                            width: min(newMaxX, max(-newMaxX, offsetX)),
                            height: min(newMaxY, max(-newMaxY, offsetY))
                        )
                        panOffset = clamped
                        basePanOffset = clamped
                        updateInspectionState(isInspecting: true)
                    }
                }
            }
        #elseif canImport(AppKit)
        Image(nsImage: preview)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(max(1.0, currentZoom))
            .offset(panOffset)
        #endif
    }
    
    private func updateInspectionState(isInspecting: Bool) {
        onInspectionChanged?(isInspecting)
        appState?.isUserInspecting = isInspecting
    }
    
    private func toggle100PercentZoom() {
        withAnimation(.spring(response: 0.25)) {
            if currentZoom > 1.05 {
                currentZoom = 1.0
                baseZoom = 1.0
                panOffset = .zero
                basePanOffset = .zero
                updateInspectionState(isInspecting: false)
            } else {
                currentZoom = 3.0
                baseZoom = 3.0
                panOffset = .zero
                basePanOffset = .zero
                updateInspectionState(isInspecting: true)
            }
        }
    }
    
    private func loadCurrentPreview() {
        guard let asset = currentAsset else { return }
        previewState = .loading
        currentZoom = 1.0
        baseZoom = 1.0
        panOffset = .zero
        basePanOffset = .zero
        updateInspectionState(isInspecting: false)
        
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: asset.fileURL, maxPixelSize: 2560)
            if Task.isCancelled { return }
            
            switch result {
            case .success(let image):
                previewState = .success(image)
            case .failure(let error):
                if error != .cancelled {
                    previewState = .failure(error)
                }
            }
            
            exifData = RAWPreviewExtractor.extractEXIFMetadata(from: asset.fileURL)
        }
    }
    
    // MARK: - Actions Card (Под фотографией по макету)
    
    private var actionsCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(spacing: AppTheme.Spacing.xs) {
                // Верхняя строка: имя кадра, формат, качество, быстрый EXIF
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(group.baseName)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Text(group.formatBadge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    previewQualityBadge
                    
                    Spacer()
                    
                    // Кнопка EXIF
                    Button {
                        isShowingEXIFSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            if let params = formattedQuickEXIF {
                                Text(params)
                                    .font(AppTheme.Typography.code)
                            }
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Сведения EXIF")
                    
                    // Меню дополнительных действий (Overflow)
                    secondaryActionsMenu
                }
                
                Divider()
                
                // Нижняя строка: звезды 1..5, флаги отбора, сравнение, экспорт/шаринг
                HStack(spacing: AppTheme.Spacing.md) {
                    // Рейтинг 1..5
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                let newRating = (group.rating == star) ? 0 : star
                                onRatingChanged?(newRating)
                                appState?.setRating(newRating, for: group)
                            } label: {
                                Image(systemName: star <= group.rating ? "star.fill" : "star")
                                    .font(.system(size: 17))
                                    .foregroundStyle(star <= group.rating ? Color.yellow : AppTheme.Colors.textTertiary)
                                    .frame(width: 32, height: AppTheme.Dimensions.minTouchTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Рейтинг \(star) звёзд")
                        }
                    }
                    
                    Spacer()
                    
                    // Флаг Pick
                    Button {
                        let newStatus: PickStatus = (group.pickStatus == .picked) ? .unflagged : .picked
                        onPickStatusChanged?(newStatus)
                        appState?.setPickStatus(newStatus, for: group)
                    } label: {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(group.pickStatus == .picked ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                            .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            .background(
                                group.pickStatus == .picked ? AppTheme.Colors.statusGreen.opacity(0.18) : Color.clear
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.pickStatus == .picked ? "Снять флаг" : "Отобрать (Pick)")
                    
                    // Флаг Reject
                    Button {
                        let newStatus: PickStatus = (group.pickStatus == .rejected) ? .unflagged : .rejected
                        onPickStatusChanged?(newStatus)
                        appState?.setPickStatus(newStatus, for: group)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(group.pickStatus == .rejected ? AppTheme.Colors.statusRed : AppTheme.Colors.textSecondary)
                            .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            .background(
                                group.pickStatus == .rejected ? AppTheme.Colors.statusRed.opacity(0.18) : Color.clear
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.pickStatus == .rejected ? "Снять отметку отклонения" : "Отклонить (Reject)")
                    
                    // Поделиться / Экспорт
                    if let asset = currentAsset {
                        ShareLink(item: asset.fileURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.Colors.accent)
                                .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                        }
                        .accessibilityLabel("Поделиться кадром")
                    } else {
                        Button {
                            appState?.presentExport(for: [group])
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.Colors.accent)
                                .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Экспорт кадра")
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    private var badgeColor: Color {
        if group.hasBothRawAndJpeg {
            return AppTheme.Colors.statusGreen
        } else if group.rawAsset != nil {
            return AppTheme.Colors.statusOrange
        } else if group.heifAsset != nil {
            return Color.purple
        } else {
            return AppTheme.Colors.accent
        }
    }
    
    // MARK: - Floating Top HUD (опциональный)
    
    private var floatingHUD: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.baseName)
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(Color.white)
                    
                    Text(group.formatBadge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                if let asset = currentAsset {
                    Text("\(asset.filename) • \(asset.formattedSize)")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassSurface(shape: RoundedRectangle(cornerRadius: 10))
            
            Spacer()
            
            previewQualityBadge
            
            secondaryActionsMenu
        }
    }
    
    // MARK: - Secondary Actions Menu (Overflow)
    
    private var secondaryActionsMenu: some View {
        Menu {
            // 1. Полноразмерный зум 100% / По размеру
            Button {
                toggle100PercentZoom()
            } label: {
                Label(
                    currentZoom > 1.05 ? "Масштаб: по размеру экрана" : "Масштаб: 100% (1:1)",
                    systemImage: currentZoom > 1.05 ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass"
                )
            }
            
            // 2. Сравнение с другим кадром
            Button {
                onOpenCompare?()
                appState?.compareCandidateGroup = group
                appState?.isComparePresented = true
            } label: {
                Label("Сравнить кадры...", systemImage: "square.split.2x1")
            }
            
            // 3. Экспорт текущего кадра
            Button {
                appState?.presentExport(for: [group])
            } label: {
                Label("Экспорт кадра...", systemImage: "square.and.arrow.up")
            }
            
            // 4. Фиксация на мониторе клиента (Hold)
            if let monitor = appState?.clientMonitorManager {
                Button {
                    monitor.toggleHold(for: group)
                } label: {
                    if monitor.config.isHoldEnabled && monitor.heldGroup?.id == group.id {
                        Label("Отпустить с монитора клиента", systemImage: "pin.slash")
                    } else {
                        Label("Зафиксировать на мониторе (Hold)", systemImage: "pin")
                    }
                }
            }
            
            // 5. Переключение активного формата / оригинала (RAW vs Companion)
            if group.allAssets.count > 1 {
                Divider()
                Menu("Выбрать оригинал") {
                    ForEach(group.allAssets) { asset in
                        Button {
                            activeAsset = asset
                        } label: {
                            if asset.id == currentAsset?.id {
                                Label("\(asset.format.displayName) — \(asset.formattedSize) ✓", systemImage: "checkmark")
                            } else {
                                Text("\(asset.format.displayName) — \(asset.formattedSize)")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
        }
        .accessibilityLabel("Дополнительные действия кадра")
    }
    
    // MARK: - Preview Quality Badge
    
    @ViewBuilder
    private var previewQualityBadge: some View {
        if let asset = currentAsset {
            if asset.isRAW {
                Button {
                    isShowingPreviewNotice = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 11))
                        Text("RAW-превью")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.Colors.statusOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.Colors.statusOrange.opacity(0.18))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                    Text("100%")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(AppTheme.Colors.statusGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.Colors.statusGreen.opacity(0.18))
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Formatted Quick EXIF String
    
    private var formattedQuickEXIF: String? {
        guard let exif = exifData else { return nil }
        var parts: [String] = []
        if let iso = exif["PhotographicSensitivity"] as? Int {
            parts.append("ISO \(iso)")
        } else if let isoArr = exif["PhotographicSensitivity"] as? [Int], let first = isoArr.first {
            parts.append("ISO \(first)")
        }
        if let fNum = exif["FNumber"] as? Double {
            parts.append(String(format: "f/%.1f", fNum))
        }
        if let expTime = exif["ExposureTime"] as? Double {
            if expTime < 1.0 && expTime > 0.0 {
                let denom = Int(round(1.0 / expTime))
                parts.append("1/\(denom)s")
            } else {
                parts.append(String(format: "%.1fs", expTime))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }
    
    // MARK: - EXIF Detail Sheet
    
    private var exifDetailSheet: some View {
        NavigationStack {
            List {
                Section("Сведения о кадре") {
                    LabeledContent("Имя группы", value: group.baseName)
                    LabeledContent("Форматы", value: group.formatBadge)
                    LabeledContent("Размер данных", value: group.formattedTotalSize)
                    if let primary = group.primaryAsset {
                        LabeledContent("Дата съемки", value: primary.formattedDateTime)
                        LabeledContent("Имя основного файла", value: primary.filename)
                    }
                }
                
                if let exif = exifData {
                    Section("Параметры съемки (EXIF)") {
                        if let camera = exif["Model"] as? String {
                            LabeledContent("Камера", value: camera)
                        }
                        if let lens = exif["LensModel"] as? String {
                            LabeledContent("Объектив", value: lens)
                        }
                        if let fLen = exif["FocalLength"] as? Double {
                            LabeledContent("Фокусное расстояние", value: String(format: "%.1f мм", fLen))
                        }
                        if let fNum = exif["FNumber"] as? Double {
                            LabeledContent("Диафрагма", value: String(format: "f/%.1f", fNum))
                        }
                        if let expTime = exif["ExposureTime"] as? Double {
                            let valStr = expTime < 1.0 && expTime > 0.0 ? "1/\(Int(round(1.0 / expTime))) с" : String(format: "%.1f с", expTime)
                            LabeledContent("Выдержка", value: valStr)
                        }
                        if let iso = exif["PhotographicSensitivity"] as? Int {
                            LabeledContent("ISO", value: "\(iso)")
                        } else if let isoArr = exif["PhotographicSensitivity"] as? [Int], let first = isoArr.first {
                            LabeledContent("ISO", value: "\(first)")
                        }
                        if let wb = exif["WhiteBalance"] as? Int {
                            LabeledContent("Баланс белого", value: wb == 0 ? "Авто" : "Ручной")
                        }
                    }
                }
                
                Section("Файлы группы (\(group.allAssets.count))") {
                    ForEach(group.allAssets) { asset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.filename)
                                    .font(AppTheme.Typography.captionBold)
                                Text("\(asset.format.displayName) • \(asset.formattedSize)")
                                    .font(AppTheme.Typography.caption2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            if asset.id == currentAsset?.id {
                                Text("Активен")
                                    .font(AppTheme.Typography.caption2Bold)
                                    .foregroundStyle(AppTheme.Colors.statusGreen)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Метаданные кадра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        isShowingEXIFSheet = false
                    }
                }
            }
        }
    }
}
