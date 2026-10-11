import SwiftUI

/// Интерактивная круглая лупа 100% проверки резкости кадра (в точности как на референсе iPhone).
/// Отображает увеличенный фрагмент изображения в круглой оправе с надписью «100% Zoom».
public struct ZoomLoupeOverlayView<Content: View>: View {
    public let diameter: CGFloat
    public let isVisible: Bool
    public let labelText: String
    @ViewBuilder public let content: () -> Content
    
    public init(
        diameter: CGFloat = 140,
        isVisible: Bool = true,
        labelText: String = "100% Zoom",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.diameter = diameter
        self.isVisible = isVisible
        self.labelText = labelText
        self.content = content
    }
    
    public var body: some View {
        if isVisible {
            VStack(spacing: 8) {
                // Круглая увеличительная линза
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                    
                    content()
                        .scaleEffect(2.8)
                        .clipShape(Circle())
                    
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.9), Color.white.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .frame(width: diameter, height: diameter)
                .shadow(color: Color.black.opacity(0.50), radius: 16, x: 0, y: 6)
                
                // Подпись под лупой
                Text(labelText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.3), radius: 4)
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}
