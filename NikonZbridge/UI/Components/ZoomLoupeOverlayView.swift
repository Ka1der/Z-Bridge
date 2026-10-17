import SwiftUI

/// Интерактивная круглая лупа 100% проверки резкости кадра (в стиле Liquid Glass).
/// Отображает увеличенный оптический фрагмент изображения в круглой оправе с надписью «100% Zoom».
/// Поддерживает свободное перемещение перетаскиванием (drag), фокусировку тапом и быстрое отключение.
public struct ZoomLoupeOverlayView<Content: View>: View {
    public let diameter: CGFloat
    public let isVisible: Bool
    public let labelText: String
    public let magnification: CGFloat
    public let offset: CGSize
    public let onDragChanged: ((CGSize) -> Void)?
    public let onDragEnded: ((CGSize) -> Void)?
    public let onClose: (() -> Void)?
    @ViewBuilder public let content: () -> Content
    
    public init(
        diameter: CGFloat = 140,
        isVisible: Bool = true,
        labelText: String = "100% Zoom",
        magnification: CGFloat = 2.6,
        offset: CGSize = .zero,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.diameter = diameter
        self.isVisible = isVisible
        self.labelText = labelText
        self.magnification = magnification
        self.offset = offset
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onClose = onClose
        self.content = content
    }
    
    public var body: some View {
        if isVisible {
            VStack(spacing: 8) {
                // Круглая увеличительная оптическая линза
                ZStack {
                    // Подложка глубины
                    Circle()
                        .fill(Color.black.opacity(0.85))
                    
                    // Увеличенный фрагмент, синхронизированный с положением лупы
                    content()
                        .scaleEffect(magnification)
                        .offset(
                            x: -offset.width * (magnification - 1.0),
                            y: -offset.height * (magnification - 1.0)
                        )
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                    
                    // Тонкое перекрестие видоискателя для точной оценки микрорезкости
                    Path { path in
                        let center = diameter / 2.0
                        let tick: CGFloat = 7
                        path.move(to: CGPoint(x: center - tick, y: center))
                        path.addLine(to: CGPoint(x: center + tick, y: center))
                        path.move(to: CGPoint(x: center, y: center - tick))
                        path.addLine(to: CGPoint(x: center, y: center + tick))
                    }
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    
                    // Внешнее кольцо оправы Liquid Glass с акцентным свечением
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.cyan.opacity(0.8),
                                    Color.white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
                .frame(width: diameter, height: diameter)
                .shadow(color: Color.black.opacity(0.60), radius: 20, x: 0, y: 8)
                
                // Интерактивная плашка статуса с кнопкой закрытия
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    
                    Text(labelText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                    
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
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.65))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
            }
            .contentShape(Circle())
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
