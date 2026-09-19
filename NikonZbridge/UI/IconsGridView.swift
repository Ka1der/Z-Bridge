import SwiftUI

/// Режим отображения: сетка карточек фотографий (по умолчанию)
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
    
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 10)
    ]
    
    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
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
            .padding(12)
        }
    }
}

/// Карточка кадра в сетке фотографий
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
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color(uiColor: .secondarySystemFill)
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
                            .scaleEffect(0.7)
                    case .failure:
                        VStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 16))
                                .foregroundStyle(.orange)
                            Text("Ошибка")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button {
                                loadThumbnail()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
                .frame(height: 110)
                .clipped()
                
                // Верхний левый угол: индикатор выбора или флаг отбора
                VStack {
                    HStack {
                        if isSelectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.85))
                                .background(Circle().fill(Color.black.opacity(0.4)))
                                .padding(4)
                        } else if group.pickStatus == .picked {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.green)
                                .clipShape(Circle())
                                .padding(4)
                        } else if group.pickStatus == .rejected {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .padding(4)
                        }
                        
                        Spacer()
                    }
                    Spacer()
                }
                
                // Бейдж формата кадра
                Text(group.formatBadge)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(badgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(group.baseName)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if group.rating > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text("\(group.rating)")
                                .font(.caption2.bold())
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                
                HStack {
                    Text(group.formattedTotalSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let primary = group.primaryAsset {
                        Text(primary.formattedTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(Color(uiColor: isSelected ? .secondarySystemFill : .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: isSelected ? 2 : 0.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.baseName), формат \(group.formatBadge), рейтинг \(group.rating) звезд")
        .accessibilityHint(isSelectionMode ? (isSelected ? "Выбран. Нажмите, чтобы снять выбор" : "Не выбран. Нажмите для выбора") : "Нажмите для просмотра кадра")
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 300)
                }
            }
        }
    }
    
    private var badgeColor: Color {
        if group.hasBothRawAndJpeg {
            return Color.green
        } else if group.rawAsset != nil {
            return Color.orange
        } else if group.heifAsset != nil {
            return Color.purple
        } else {
            return Color.blue
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 300)
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
