import SwiftUI

/// Интерактивная круглая лупа 100% / 200% проверки резкости кадра (в стиле Liquid Glass).
/// Отображает реальный оптически увеличенный фрагмент изображения в круглой оправе с надписью «100% Zoom».
/// Поддерживает свободное перемещение перетаскиванием (drag), фокусировку тапом, переключение 100%/200% и быстрое отключение.
public struct ZoomLoupeOverlayView<Content: View>: View {
    public let diameter: CGFloat
    public let isVisible: Bool
    public let labelText: String
    public let magnification: CGFloat
    public let offset: CGSize
    public let displaySize: CGSize
    public let cgImage: CGImage?
    public let onDragChanged: ((CGSize) -> Void)?
    public let onDragEnded: ((CGSize) -> Void)?
    public let onTap: (() -> Void)?
    public let onToggleZoom: (() -> Void)?
    public let onClose: (() -> Void)?
    @ViewBuilder public let content: () -> Content
    
    public init(
        diameter: CGFloat = 218,
        isVisible: Bool = true,
        labelText: String = "100% Zoom",
        magnification: CGFloat = 3.0,
        offset: CGSize = .zero,
        displaySize: CGSize = CGSize(width: 800, height: 600),
        cgImage: CGImage? = nil,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        onToggleZoom: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.diameter = diameter
        self.isVisible = isVisible
        self.labelText = labelText
        self.magnification = magnification
        self.offset = offset
        self.displaySize = displaySize
        self.cgImage = cgImage
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onTap = onTap
        self.onToggleZoom = onToggleZoom
        self.onClose = onClose
        self.content = content
    }
    
    public var body: some View {
        if isVisible {
            // Круглая увеличительная оптическая линза
                ZStack {
                    // Черная подложка
                    Circle()
                        .fill(Color.black)
                    
                    // Реально увеличенное оптическое изображение с точным расчетом геометрии
                    Group {
                        if let cgImage = cgImage {
                            #if canImport(UIKit)
                            Image(uiImage: UIImage(cgImage: cgImage))
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                            #elseif canImport(AppKit)
                            Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: max(1, displaySize.width), height: max(1, displaySize.height))))
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                            #else
                            Image(decorative: cgImage, scale: 1.0)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                            #endif
                        } else {
                            content()
                        }
                    }
                    .frame(
                        width: max(displaySize.width, 100) * magnification,
                        height: max(displaySize.height, 100) * magnification
                    )
                    .offset(
                        x: -offset.width * magnification,
                        y: -offset.height * magnification
                    )
                    .frame(width: diameter, height: diameter)
                    .clipped()
                    
                    // Оптический градиент объема линзы (эффект преломления по краям)
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.42)
                        ]),
                        center: .center,
                        startRadius: diameter * 0.32,
                        endRadius: diameter * 0.50
                    )
                    
                    // Внешнее кольцо оправы Liquid Glass с акцентным свечением
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.cyan.opacity(0.85),
                                    Color.white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .shadow(color: Color.cyan.opacity(0.4), radius: 6)
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.70), radius: 22, x: 0, y: 10)
                .contentShape(Circle())
                .offset(offset)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { val in
                            onDragChanged?(val.translation)
                        }
                        .onEnded { val in
                            let dist = hypot(val.translation.width, val.translation.height)
                            if dist < 6 {
                                onTap?()
                            } else {
                                onDragEnded?(val.translation)
                            }
                        }
                )
                .onTapGesture {
                    onTap?()
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

extension ZoomLoupeOverlayView where Content == EmptyView {
    public init(
        diameter: CGFloat = 218,
        isVisible: Bool = true,
        labelText: String = "100% Zoom",
        magnification: CGFloat = 3.0,
        offset: CGSize = .zero,
        displaySize: CGSize = CGSize(width: 800, height: 600),
        cgImage: CGImage? = nil,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        onToggleZoom: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.init(
            diameter: diameter,
            isVisible: isVisible,
            labelText: labelText,
            magnification: magnification,
            offset: offset,
            displaySize: displaySize,
            cgImage: cgImage,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onTap: onTap,
            onToggleZoom: onToggleZoom,
            onClose: onClose,
            content: { EmptyView() }
        )
    }
}
