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
    public let onToggleZoom: (() -> Void)?
    public let onClose: (() -> Void)?
    @ViewBuilder public let content: () -> Content
    
    public init(
        diameter: CGFloat = 150,
        isVisible: Bool = true,
        labelText: String = "100% Zoom",
        magnification: CGFloat = 3.0,
        offset: CGSize = .zero,
        displaySize: CGSize = CGSize(width: 800, height: 600),
        cgImage: CGImage? = nil,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil,
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
        self.onToggleZoom = onToggleZoom
        self.onClose = onClose
        self.content = content
    }
    
    public var body: some View {
        if isVisible {
            VStack(spacing: 8) {
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
                    
                    // Тонкое перекрестие видоискателя для точной оценки резкости
                    Path { path in
                        let center = diameter / 2.0
                        let tick: CGFloat = 8
                        let gap: CGFloat = 3
                        path.move(to: CGPoint(x: center - tick, y: center))
                        path.addLine(to: CGPoint(x: center - gap, y: center))
                        path.move(to: CGPoint(x: center + gap, y: center))
                        path.addLine(to: CGPoint(x: center + tick, y: center))
                        path.move(to: CGPoint(x: center, y: center - tick))
                        path.addLine(to: CGPoint(x: center, y: center - gap))
                        path.move(to: CGPoint(x: center, y: center + gap))
                        path.addLine(to: CGPoint(x: center, y: center + tick))
                    }
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.2)
                    
                    // Центральная микро-точка фокусировки
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 3, height: 3)
                        .shadow(color: Color.cyan, radius: 2)
                    
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
                
                // Интерактивная плашка статуса с переключением масштаба и кнопкой закрытия
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    
                    if let onToggleZoom {
                        Button(action: onToggleZoom) {
                            HStack(spacing: 4) {
                                Text(labelText)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.cyan)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Переключить масштаб увеличения")
                    } else {
                        Text(labelText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)
                        .accessibilityLabel("Выключить лупу")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.75))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
            }
            .contentShape(Rectangle())
            .offset(offset)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { val in
                        onDragChanged?(val.translation)
                    }
                    .onEnded { val in
                        onDragEnded?(val.translation)
                    }
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

extension ZoomLoupeOverlayView where Content == EmptyView {
    public init(
        diameter: CGFloat = 150,
        isVisible: Bool = true,
        labelText: String = "100% Zoom",
        magnification: CGFloat = 3.0,
        offset: CGSize = .zero,
        displaySize: CGSize = CGSize(width: 800, height: 600),
        cgImage: CGImage? = nil,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil,
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
            onToggleZoom: onToggleZoom,
            onClose: onClose,
            content: { EmptyView() }
        )
    }
}
