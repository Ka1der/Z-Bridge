import SwiftUI

/// Модификатор и вспомогательные структуры для создания стеклянных полупрозрачных поверхностей.
/// 
/// Автоматически учитывает:
/// - Доступность современного системного Glass API на платформах iOS 26+ (`glassEffect`);
/// - Безопасный системный фолбэк на `.ultraThinMaterial` для iOS 17..25;
/// - Настройку системы «Уменьшение прозрачности» (`accessibilityReduceTransparency`) с переключением на сплошной графитовый/светлый фон;
/// - Повышенную контрастность (`colorSchemeContrast == .increased`) с утолщенным и более заметным контуром;
/// - Мягкую аккуратную тень без паразитных неоновых засветов вокруг фотоматериала.
public struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    
    public let shape: S
    public let tint: Color?
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat
    
    public init(
        shape: S,
        tint: Color? = nil,
        shadowRadius: CGFloat = 8,
        shadowY: CGFloat = 2
    ) {
        self.shape = shape
        self.tint = tint
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }
    
    @ViewBuilder
    public func body(content: Content) -> some View {
        let isHighContrast = (contrast == .increased)
        let strokeColor = isHighContrast ? AppTheme.Colors.borderStrong : AppTheme.Colors.borderSubtle
        let strokeWidth: CGFloat = isHighContrast ? AppTheme.Dimensions.borderWidthHighContrast : AppTheme.Dimensions.borderWidth
        let shadowColor = AppTheme.Colors.shadow
        
        if reduceTransparency {
            // Безопасный сплошной фон при отключенной прозрачности в iOS
            content
                .background(
                    Group {
                        if let tint {
                            shape.fill(AppTheme.Colors.surfacePrimary)
                                .overlay(shape.fill(tint.opacity(0.12)))
                        } else {
                            shape.fill(AppTheme.Colors.surfacePrimary)
                        }
                    }
                )
                .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            // Актуальный системный API Glass при наличии в SDK / рантайме
            let glassStyle = tint != nil ? Glass.regular.tint(tint!) : Glass.regular
            content
                .glassEffect(glassStyle, in: shape)
                .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        } else {
            // Элегантный фолбэк для iOS 17+ на основе ultraThinMaterial
            content
                .background(
                    Group {
                        if let tint {
                            shape.fill(tint.opacity(0.12))
                                .background(.ultraThinMaterial, in: shape)
                        } else {
                            Color.clear
                                .background(.ultraThinMaterial, in: shape)
                        }
                    }
                )
                .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        }
    }
}

// MARK: - View Extensions

public extension View {
    /// Применяет стеклянное оформление с произвольной фигурой
    func glassSurface<S: Shape>(
        shape: S,
        tint: Color? = nil,
        shadowRadius: CGFloat = 8,
        shadowY: CGFloat = 2
    ) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, tint: tint, shadowRadius: shadowRadius, shadowY: shadowY))
    }
    
    /// Применяет стеклянное оформление со скруглённым прямоугольником
    func glassSurface(
        cornerRadius: CGFloat = AppTheme.Radius.md,
        tint: Color? = nil,
        shadowRadius: CGFloat = 8,
        shadowY: CGFloat = 2
    ) -> some View {
        glassSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }
    
    /// Применяет стеклянное оформление в форме капсулы (для кнопок и статусных индикаторов)
    func glassPill(
        tint: Color? = nil,
        shadowRadius: CGFloat = 6,
        shadowY: CGFloat = 1
    ) -> some View {
        glassSurface(
            shape: Capsule(),
            tint: tint,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }
}

// MARK: - GlassCard Container

/// Переиспользуемый контейнер карточки со стеклянным фоном
public struct GlassCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let tint: Color?
    public let content: Content
    
    public init(
        cornerRadius: CGFloat = AppTheme.Radius.md,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }
    
    public var body: some View {
        content
            .glassSurface(cornerRadius: cornerRadius, tint: tint)
    }
}
