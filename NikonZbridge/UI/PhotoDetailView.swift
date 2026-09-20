import SwiftUI

public struct PhotoDetailView: View {
    let group: CaptureGroup
    var appState: AppState?
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
        onRatingChanged: ((Int) -> Void)? = nil,
        onPickStatusChanged: ((PickStatus) -> Void)? = nil,
        onInspectionChanged: ((Bool) -> Void)? = nil,
        onOpenCompare: (() -> Void)? = nil
    ) {
        self.group = group
        self.appState = appState
        self.onRatingChanged = onRatingChanged
        self.onPickStatusChanged = onPickStatusChanged
        self.onInspectionChanged = onInspectionChanged
        self.onOpenCompare = onOpenCompare
    }
    
    /// Инициализатор совместимости с одиночным IngestedFile
    public init(file: IngestedFile, appState: AppState? = nil) {
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
    }
    
    private var currentAsset: MediaAsset? {
        activeAsset ?? group.primaryAsset
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            // Основная область фотографии с поддержкой панорамирования и зума
            GeometryReader { geo in
                ZStack {
                    switch previewState {
                    case .success(let preview):
                        imageContentView(preview: preview, geoSize: geo.size)
                        
                    case .loading, .idle:
                        VStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Декодирование превью...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    case .failure(let error):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            
                            VStack(spacing: 4) {
                                Text("Не удалось отобразить превью")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            
            // Верхняя парящая плашка с информацией о кадре, форматах и оригиналах
            floatingHUD
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            // Нижняя панель отбора (Рейтинг, Флаги, Сравнение, Масштаб 1:1)
            VStack {
                Spacer()
                cullingBar
                    .padding(.bottom, 12)
            }
        }
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
    
    private var floatingHUD: some View {
        HStack(spacing: 8) {
            // Имя кадра и бейдж формата
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.baseName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(group.formatBadge)
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(group.hasBothRawAndJpeg ? Color.green.opacity(0.4) : (group.rawAsset != nil ? Color.orange.opacity(0.4) : Color.blue.opacity(0.4)))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                if let asset = currentAsset {
                    Text("\(asset.filename) • \(asset.formattedSize)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Spacer()
            
            // Бейдж типа превью (Оригинал vs Встроенное превью RAW)
            previewQualityBadge
            
            // Инспектор метаданных (EXIF, камера, объектив, контрольная сумма)
            Button {
                isShowingEXIFSheet = true
            } label: {
                HStack(spacing: 5) {
                    if let params = formattedQuickEXIF {
                        Text(params)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .accessibilityLabel("Сведения и метаданные кадра")
            
            // Меню дополнительных действий (Secondary / Overflow Menu)
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
            
            // 5. Поделиться оригиналом
            if let asset = currentAsset {
                ShareLink(item: asset.fileURL) {
                    Label("Поделиться файлом (\(asset.format.displayName))...", systemImage: "square.and.arrow.up")
                }
            }
            
            // 6. Переключение активного формата / оригинала (RAW vs Companion)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(7)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel("Дополнительные действия кадра")
    }
    
    // MARK: - Preview Quality Badge (Обозначение ограниченного превью vs полное разрешение)
    
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
                        Text("Превью • RAW")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                    Text("Оригинал 100%")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.18))
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Culling Bar (Bottom: Stars 1..5, Pick, Reject, Unflag)
    
    private var cullingBar: some View {
        HStack(spacing: 12) {
            // Звезды 1..5
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        let newRating = (group.rating == star) ? 0 : star
                        onRatingChanged?(newRating)
                        appState?.setRating(newRating, for: group)
                    } label: {
                        Image(systemName: star <= group.rating ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundStyle(star <= group.rating ? Color.yellow : Color.white.opacity(0.35))
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("Рейтинг \(star) звёзд")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            
            // Разделитель
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 22)
            
            // Флаги отбора: Pick (зеленый флаг), Reject (красный крестик), Unflag
            HStack(spacing: 6) {
                // Pick
                Button {
                    let newStatus: PickStatus = (group.pickStatus == .picked) ? .unflagged : .picked
                    onPickStatusChanged?(newStatus)
                    appState?.setPickStatus(newStatus, for: group)
                } label: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(group.pickStatus == .picked ? Color.green : Color.white.opacity(0.4))
                        .padding(7)
                        .background(group.pickStatus == .picked ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Отобрать (Pick)")
                
                // Reject
                Button {
                    let newStatus: PickStatus = (group.pickStatus == .rejected) ? .unflagged : .rejected
                    onPickStatusChanged?(newStatus)
                    appState?.setPickStatus(newStatus, for: group)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(group.pickStatus == .rejected ? Color.red : Color.white.opacity(0.4))
                        .padding(7)
                        .background(group.pickStatus == .rejected ? Color.red.opacity(0.25) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Отклонить (Reject)")
                
                // Unflag
                if group.pickStatus != .unflagged {
                    Button {
                        onPickStatusChanged?(.unflagged)
                        appState?.setPickStatus(.unflagged, for: group)
                    } label: {
                        Image(systemName: "flag.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(7)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Снять флаг")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.3), radius: 6, y: 2)
    }
    
    private var formattedQuickEXIF: String? {
        guard let exif = exifData, let exifSub = exif["{Exif}"] as? [String: Any] else {
            return currentAsset?.metadata.quickExposureSummary
        }
        var parts: [String] = []
        if let exp = exifSub["ExposureTime"] as? Double {
            parts.append(exp < 1.0 ? "1/\(Int(round(1.0 / exp)))" : "\(exp)s")
        }
        if let fNum = exifSub["FNumber"] as? Double {
            parts.append(String(format: "f/%.1f", fNum))
        }
        if let iso = (exifSub["ISOSpeedRatings"] as? [Int])?.first {
            parts.append("ISO \(iso)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }
    
    private var exifDetailSheet: some View {
        NavigationStack {
            List {
                Section("Параметры съемки (EXIF)") {
                    if let exifSub = exifData?["{Exif}"] as? [String: Any] {
                        if let exp = exifSub["ExposureTime"] as? Double {
                            row(title: "Выдержка", value: exp < 1.0 ? "1/\(Int(round(1.0 / exp))) s" : "\(exp) s")
                        }
                        if let fNum = exifSub["FNumber"] as? Double {
                            row(title: "Диафрагма", value: String(format: "f/%.1f", fNum))
                        }
                        if let iso = (exifSub["ISOSpeedRatings"] as? [Int])?.first {
                            row(title: "ISO", value: "\(iso)")
                        }
                        if let focal = exifSub["FocalLength"] as? Double {
                            row(title: "Фокусное расстояние", value: "\(Int(focal)) мм")
                        }
                        if let lens = (exifSub["LensModel"] as? String) ?? (exifData?["{TIFF}"] as? [String: Any])?["LensModel"] as? String {
                            row(title: "Объектив", value: lens)
                        }
                    } else if let summary = currentAsset?.metadata.quickExposureSummary {
                        row(title: "Экспозиция", value: summary)
                    } else {
                        Text("Метаданные экспозиции недоступны")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Камера и файл") {
                    if let tiff = exifData?["{TIFF}"] as? [String: Any], let model = tiff["Model"] as? String {
                        row(title: "Камера", value: model)
                    }
                    if let session = appState?.currentSession {
                        row(title: "Сессия", value: session.name)
                    }
                    if let asset = currentAsset {
                        row(title: "Файл", value: asset.filename)
                        row(title: "Формат", value: asset.format.displayName)
                        row(title: "Размер", value: asset.formattedSize)
                        row(title: "Дата и время", value: asset.formattedTime)
                        if let sum = asset.sha256Checksum {
                            row(title: "Контрольная сумма SHA-256", value: sum)
                        }
                    }
                }
                
                Section("Доступные оригиналы на диске (\(group.allAssets.count))") {
                    ForEach(group.allAssets) { asset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(asset.filename)
                                        .font(.subheadline.bold())
                                    if asset.id == currentAsset?.id {
                                        Text("Текущий")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.3))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(asset.format.displayName) • \(asset.formattedSize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: asset.fileURL) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Сведения о кадре")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") {
                        isShowingEXIFSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func row(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
                .multilineTextAlignment(.trailing)
        }
    }
}
