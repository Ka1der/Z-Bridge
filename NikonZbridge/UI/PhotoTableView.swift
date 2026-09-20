import SwiftUI

/// Режим отображения: компактная таблица параметров и метаданных кадров
public struct PhotoTableView: View {
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
        VStack(spacing: 0) {
            // Шапка таблицы
            tableHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                #if canImport(UIKit)
                .background(Color(uiColor: .tertiarySystemFill))
                #else
                .background(Color.secondary.opacity(0.15))
                #endif
            
            Divider()
            
            // Строки таблицы
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        PhotoTableRow(
                            index: groups.count - index,
                            group: group,
                            isSelected: isSelectionMode ? selectedGroupIDs.contains(group.id) : (selectedGroup?.id == group.id),
                            isEven: index % 2 == 0,
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
            }
        }
    }
    
    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("№")
                .frame(width: 26, alignment: .leading)
            Text("Кадр")
                .frame(minWidth: 90, alignment: .leading)
            Spacer()
            Text("Отбор")
                .frame(width: 48, alignment: .center)
            Text("Формат")
                .frame(width: 68, alignment: .center)
            Text("Оригиналы")
                .frame(width: 70, alignment: .trailing)
            Text("Объём")
                .frame(width: 65, alignment: .trailing)
            Text("Время")
                .frame(width: 55, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
}

/// Строка кадра в режиме таблицы
public struct PhotoTableRow: View {
    public let index: Int
    public let group: CaptureGroup
    public let isSelected: Bool
    public let isEven: Bool
    public var isSelectionMode: Bool = false
    @State private var previewState: PreviewState = .idle
    
    public init(index: Int, group: CaptureGroup, isSelected: Bool, isEven: Bool, isSelectionMode: Bool = false) {
        self.index = index
        self.group = group
        self.isSelected = isSelected
        self.isEven = isEven
        self.isSelectionMode = isSelectionMode
    }
    
    public init(index: Int, file: IngestedFile, isSelected: Bool, isEven: Bool) {
        self.index = index
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
        self.isEven = isEven
        self.isSelectionMode = false
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        #if canImport(UIKit)
        return isEven ? Color(uiColor: .systemBackground) : Color(uiColor: .secondarySystemBackground)
        #else
        return isEven ? Color.clear : Color.secondary.opacity(0.05)
        #endif
    }
    
    private var badgeColor: Color {
        if group.hasBothRawAndJpeg {
            return Color.green
        } else if group.rawAsset != nil {
            return Color.orange
        } else {
            return Color.blue
        }
    }
    
    @ViewBuilder
    private var indexColumn: some View {
        if isSelectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 26)
        } else {
            Text("\(index)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var thumbnailAndNameColumn: some View {
        HStack(spacing: 6) {
            ZStack {
                #if canImport(UIKit)
                Color(uiColor: .secondarySystemFill)
                #else
                Color.secondary.opacity(0.2)
                #endif
                if case .success(let img) = previewState {
                    #if canImport(UIKit)
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #elseif canImport(AppKit)
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #endif
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(group.baseName)
                .font(.caption.bold().monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(minWidth: 90, alignment: .leading)
    }
    
    @ViewBuilder
    private var cullingColumn: some View {
        HStack(spacing: 3) {
            if group.pickStatus == .picked {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
            } else if group.pickStatus == .rejected {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            }
            
            if group.rating > 0 {
                Text("★\(group.rating)")
                    .font(.caption2.bold())
                    .foregroundStyle(.yellow)
            }
        }
        .frame(width: 48, alignment: .center)
    }
    
    @ViewBuilder
    private var detailsColumn: some View {
        Text(group.formatBadge)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .frame(width: 68, alignment: .center)
        
        Text("\(group.allAssets.count) файл(а)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .trailing)
        
        Text(group.formattedTotalSize)
            .font(.caption2.monospaced())
            .foregroundStyle(.primary)
            .frame(width: 65, alignment: .trailing)
        
        if let primary = group.primaryAsset {
            Text(primary.formattedTime)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .trailing)
        } else {
            Text("—")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .trailing)
        }
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            indexColumn
            thumbnailAndNameColumn
            Spacer()
            cullingColumn
            detailsColumn
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(rowBackgroundColor)
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.baseName), \(group.formatBadge), \(group.formattedTotalSize)")
        .accessibilityHint(isSelectionMode ? (isSelected ? "Выбран. Нажмите для отмены" : "Не выбран. Нажмите для выбора") : "Нажмите для просмотра кадра")
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 80)
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 80)
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
