import SwiftUI

/// Режим отображения: подробный список фотографий
public struct PhotoListView: View {
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
    
    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(groups) { group in
                    PhotoListRow(
                        group: group,
                        isSelected: isSelectionMode ? selectedGroupIDs.contains(group.id) : (selectedGroup?.id == group.id),
                        isSelectionMode: isSelectionMode
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectionMode {
                            onToggleSelect?(group)
                        } else {
                            onSelect(group)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// Строка кадра в режиме списка
public struct PhotoListRow: View {
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
        HStack(spacing: 12) {
            // Чекбокс выбора
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            
            // Превью
            ZStack(alignment: .bottomTrailing) {
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
                            .scaleEffect(0.6)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 58, height: 58)
                .clipped()
                
                Text(group.formatBadge)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(group.hasBothRawAndJpeg ? Color.green : (group.rawAsset != nil ? Color.orange : Color.blue))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Метаданные
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.baseName)
                        .font(.subheadline.bold().monospaced())
                        .foregroundStyle(.primary)
                    
                    if group.pickStatus == .picked {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if group.pickStatus == .rejected {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    }
                    
                    if group.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...group.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                
                HStack(spacing: 8) {
                    if let primary = group.primaryAsset {
                        Label(primary.formattedTime, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(group.availableOriginalsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Размер и переход
            VStack(alignment: .trailing, spacing: 4) {
                Text(group.formattedTotalSize)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minHeight: 64)
        .background(Color(uiColor: isSelected ? .secondarySystemFill : .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.baseName), \(group.formatBadge), размер \(group.formattedTotalSize), рейтинг \(group.rating) звезд")
        .accessibilityHint(isSelectionMode ? (isSelected ? "Выбран. Нажмите для отмены" : "Не выбран. Нажмите для выбора") : "Нажмите для просмотра кадра")
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 180)
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 180)
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
