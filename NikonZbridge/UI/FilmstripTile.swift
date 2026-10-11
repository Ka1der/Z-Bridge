import SwiftUI

/// Компактная миниатюра кадра для нижней ленты просмотрщика и экрана сравнения
public struct FilmstripTile: View {
    public let group: CaptureGroup
    public let isSelected: Bool
    @State private var previewState: PreviewState = .idle
    
    public init(group: CaptureGroup, isSelected: Bool) {
        self.group = group
        self.isSelected = isSelected
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
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if case .success(let img) = previewState {
                #if canImport(UIKit)
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
                #elseif canImport(AppKit)
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
                #endif
            } else {
                Rectangle()
                    .fill(AppTheme.Colors.surfaceSecondary)
                    .frame(width: 64, height: 64)
                    .overlay(ProgressView().scaleEffect(0.6))
            }
            
            // Верхний левый угол: флаг отбора
            if group.pickStatus == .picked {
                VStack {
                    HStack {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.green)
                            .clipShape(Circle())
                            .padding(2)
                        Spacer()
                    }
                    Spacer()
                }
            } else if group.pickStatus == .rejected {
                VStack {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.red)
                            .clipShape(Circle())
                            .padding(2)
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            // Нижний левый угол: звёздочки
            if group.rating > 0 {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(AppTheme.Colors.ratingActive)
                            Text("\(group.rating)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.ratingActive)
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(2)
                        Spacer()
                    }
                }
            }
            
            Text(group.formatBadge)
                .font(.system(size: 7, weight: .bold))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(group.hasBothRawAndJpeg ? Color.green : (group.rawAsset != nil ? Color.orange : Color.blue))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(2)
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.borderSubtle, lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.baseName), \(group.formatBadge), рейтинг \(group.rating) звезд")
        .accessibilityHint(isSelected ? "Выбранный кадр" : "Нажмите для выбора кадра")
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
