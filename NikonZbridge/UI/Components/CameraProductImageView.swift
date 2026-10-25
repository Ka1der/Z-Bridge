import SwiftUI

/// Компонент для отображения фотографии корпуса камеры Nikon Z.
/// Загружает локальное изображение из Asset Catalog приложения (offline-first),
/// а при необходимости подтягивает официальное студийное фото продукта из интернета через AsyncImage.
public struct CameraProductImageView: View {
    public let model: NikonCameraModel?
    public let imageURL: URL?
    
    public init(model: NikonCameraModel?, imageURL: URL? = nil) {
        self.model = model
        self.imageURL = imageURL ?? model?.officialImageURL
    }
    
    public var body: some View {
        contentView
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var contentView: some View {
        #if canImport(UIKit)
        if let model = model, let uiImage = UIImage(named: model.assetImageName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let url = imageURL {
            remoteAsyncImage(url: url)
        } else {
            placeholderIcon
        }
        #elseif canImport(AppKit)
        if let model = model, let nsImage = NSImage(named: model.assetImageName) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let url = imageURL {
            remoteAsyncImage(url: url)
        } else {
            placeholderIcon
        }
        #else
        if let url = imageURL {
            remoteAsyncImage(url: url)
        } else {
            placeholderIcon
        }
        #endif
    }
    
    @ViewBuilder
    private func remoteAsyncImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .controlSize(.mini)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .failure:
                placeholderIcon
            @unknown default:
                placeholderIcon
            }
        }
    }
    
    private var placeholderIcon: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.accent)
    }
}
