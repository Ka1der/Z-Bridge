import SwiftUI

/// Режим отображения: адаптивная сетка карточек фотографий (Liquid Glass)
public struct IconsGridView: View {
    public let groups: [CaptureGroup]
    public let selectedGroup: CaptureGroup?
    public var isSelectionMode: Bool = false
    public var selectedGroupIDs: Set<String> = []
    public var onToggleSelect: ((CaptureGroup) -> Void)? = nil
    public let onSelect: (CaptureGroup) -> Void
    
    public init(
        groups: [CaptureGroup],
        selectedGroup: CaptureGroup? = nil,
        isSelectionMode: Bool = false,
        selectedGroupIDs: Set<String> = [],
        onToggleSelect: ((CaptureGroup) -> Void)? = nil,
        onSelect: @escaping (CaptureGroup) -> Void
    ) {
        self.groups = groups
        self.selectedGroup = selectedGroup
        self.isSelectionMode = isSelectionMode
        self.selectedGroupIDs = selectedGroupIDs
        self.onToggleSelect = onToggleSelect
        self.onSelect = onSelect
    }
    
    public init(
        files: [IngestedFile],
        selectedFile: IngestedFile? = nil,
        onSelect: @escaping (IngestedFile) -> Void
    ) {
        self.groups = files.map { file in
            if let asset = file.mediaAsset {
                return CaptureGroup(asset: asset)
            }
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            return CaptureGroup(asset: asset)
        }
        self.selectedGroup = groups.first
        self.isSelectionMode = false
        self.selectedGroupIDs = []
        self.onToggleSelect = nil
        self.onSelect = { group in
            if let first = group.primaryAsset {
                onSelect(IngestedFile(from: first))
            }
        }
    }
    
    /// Расчет числа колонок сетки в зависимости от доступной ширины
    public static func calculateColumnCount(for width: CGFloat) -> Int {
        if width < 520 {
            return 2 // iPhone в портрете, узкий Split View
        } else if width < 850 {
            return 3 // iPhone в ландшафте, 1/2 Split View
        } else if width < 1200 {
            return 4 // iPad в портрете / 2/3 Split View
        } else {
            return 5 // iPad Pro полноэкранный
        }
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let columnCount = Self.calculateColumnCount(for: proxy.size.width)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                count: columnCount
            )
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                    ForEach(groups) { group in
                        IconGridCard(
                            group: group,
                            isSelected: isSelectionMode ? selectedGroupIDs.contains(group.id) : (selectedGroup?.id == group.id),
                            isSelectionMode: isSelectionMode
                        )
                        .onTapGesture {
                            if isSelectionMode {
                                onToggleSelect?(group)
                            } else {
                                onSelect(group)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl + 40) // Запас под нижний dock / панель
            }
        }
    }
}

/// Карточка кадра в сетке фотографий по макету Liquid Glass
public struct IconGridCard: View {
    public let group: CaptureGroup
    public let isSelected: Bool
    public var isSelectionMode: Bool = false
    @State private var previewState: PreviewState = .idle
    
    public init(group: CaptureGroup, isSelected: Bool, isSelectionMode: Bool = false) {
        self.group = group
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
    }
    
    public init(file: IngestedFile, isSelected: Bool) {
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
                transferDuration: file.transferDuration
            )
            self.group = CaptureGroup(asset: asset)
        }
        self.isSelected = isSelected
        self.isSelectionMode = false
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Область миниатюры фотографии с пропорцией ~1:1
            ZStack {
                AppTheme.Colors.surfacePrimary
                
                switch previewState {
                case .success(let img):
                    #if canImport(UIKit)
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #elseif canImport(AppKit)
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #endif
                case .loading, .idle:
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.Colors.accent)
                case .failure:
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Text("Ошибка")
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                        Button {
                            loadThumbnail()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .frame(minWidth: AppTheme.Dimensions.minTouchTarget, minHeight: AppTheme.Dimensions.minTouchTarget)
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 180)
            .aspectRatio(1.0, contentMode: .fill)
            .clipped()
            
            // 2. Верхние индикаторы (множественный выбор, рейтинг, флаг)
            VStack {
                HStack {
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isSelected ? AppTheme.Colors.accent : Color.white.opacity(0.85))
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .padding(AppTheme.Spacing.xs)
                    } else if group.pickStatus == .picked {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(5)
                            .background(AppTheme.Colors.statusGreen)
                            .clipShape(Circle())
                            .padding(AppTheme.Spacing.xs)
                    } else if group.pickStatus == .rejected {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(5)
                            .background(AppTheme.Colors.statusRed)
                            .clipShape(Circle())
                            .padding(AppTheme.Spacing.xs)
                    }
                    
                    Spacer()
                    
                    if group.rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.yellow)
                            Text("\(group.rating)")
                                .font(AppTheme.Typography.caption2Bold)
                                .foregroundStyle(Color.yellow)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(AppTheme.Spacing.xs)
                    }
                }
                Spacer()
            }
            
            // 3. Компактная нижняя плашка кадра по макету:
            // Имя кадра слева («DSC_0021»), формат справа («RAW+JPG»)
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(group.baseName)
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                
                Spacer()
                
                Text(formatBadgeTitle)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .padding(.horizontal, AppTheme.Spacing.xs + 2)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.6), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.Colors.accent : AppTheme.Colors.borderSubtle,
                    lineWidth: isSelected ? 2.0 : AppTheme.Dimensions.borderWidth
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.baseName), формат \(formatBadgeTitle), рейтинг \(group.rating) звезд")
        .accessibilityHint(isSelectionMode ? (isSelected ? "Выбран. Нажмите для снятия" : "Не выбран. Нажмите для выбора") : "Нажмите для открытия просмотра кадра")
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 350)
                }
            }
        }
    }
    
    private var formatBadgeTitle: String {
        if group.hasBothRawAndJpeg {
            return "RAW+JPG"
        } else if group.rawAsset != nil {
            return "RAW"
        } else if group.heifAsset != nil {
            return "HEIF"
        } else {
            return "JPG"
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 350)
            if Task.isCancelled { return }
            switch result {
            case .success(let img):
                previewState = .success(img)
            case .failure(let err):
                if err != .cancelled {
                    previewState = .failure(err)
                }
            }
        }
    }
}
