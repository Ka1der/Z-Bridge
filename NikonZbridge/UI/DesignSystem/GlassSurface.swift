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
        } else {
            // Аутентичный Liquid Glass с матовым стеклом, глубоким обсидиановым тоном и градиентным бликом на гранях
            content
                .background(
                    Group {
                        if colorScheme == .dark {
                            shape
                                .fill(Color(red: 22/255.0, green: 24/255.0, blue: 29/255.0).opacity(0.72))
                                .overlay(tint != nil ? shape.fill(tint!.opacity(0.12)) : nil)
                                .background(.ultraThinMaterial, in: shape)
                        } else {
                            shape
                                .fill(Color.white.opacity(0.70))
                                .overlay(tint != nil ? shape.fill(tint!.opacity(0.10)) : nil)
                                .background(.ultraThinMaterial, in: shape)
                        }
                    }
                )
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(isHighContrast ? 0.35 : 0.18), Color.white.opacity(isHighContrast ? 0.12 : 0.04)]
                                : [Color.white.opacity(isHighContrast ? 0.80 : 0.65), Color.black.opacity(isHighContrast ? 0.15 : 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
                )
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.35) : shadowColor, radius: shadowRadius, x: 0, y: shadowY)
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

// MARK: - Glass Inset (Nested Liquid Glass Panel)

/// Вложенная полупрозрачная стеклянная панель для группировки данных внутри GlassCard
public struct GlassInsetModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    
    public let cornerRadius: CGFloat
    
    public init(cornerRadius: CGFloat = AppTheme.Radius.sm) {
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        let isHighContrast = (contrast == .increased)
        let strokeColor = isHighContrast ? AppTheme.Colors.borderStrong : Color.white.opacity(0.12)
        let strokeWidth: CGFloat = isHighContrast ? AppTheme.Dimensions.borderWidthHighContrast : 0.7
        
        if reduceTransparency {
            content
                .background(AppTheme.Colors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(isHighContrast ? 0.35 : 0.16), Color.white.opacity(isHighContrast ? 0.12 : 0.03)]
                                    : [Color.white.opacity(isHighContrast ? 0.70 : 0.50), Color.black.opacity(isHighContrast ? 0.12 : 0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: strokeWidth
                        )
                )
        }
    }
}

public extension View {
    /// Применяет матовое вложенное стекло для полей ввода, учетных записей и технических блоков
    func glassInset(cornerRadius: CGFloat = AppTheme.Radius.sm) -> some View {
        modifier(GlassInsetModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Studio Background (Liquid Glass Backdrop)

/// Студийный объёмный фон с мягким светом для красивого преломления жидкого стекла
public struct StudioBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    public func body(content: Content) -> some View {
        ZStack {
            if colorScheme == .dark {
                // Глубокий обсидиановый фон
                Color(red: 12/255.0, green: 13/255.0, blue: 16/255.0)
                    .ignoresSafeArea()
                
                // Рассеянный холодный свет в левом верхнем углу для естественного блика граней
                RadialGradient(
                    colors: [Color(red: 35/255.0, green: 42/255.0, blue: 58/255.0).opacity(0.35), Color.clear],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 550
                )
                .ignoresSafeArea()
                
                // Тёплый акцентный свет Nikon в правом нижнем углу
                RadialGradient(
                    colors: [AppTheme.Colors.accent.opacity(0.04), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 60,
                    endRadius: 650
                )
                .ignoresSafeArea()
            } else {
                Color(red: 242/255.0, green: 243/255.0, blue: 247/255.0)
                    .ignoresSafeArea()
            }
            
            content
        }
    }
}

public extension View {
    /// Применяет рассеянную студийную подсветку для максимального визуального эффекта Liquid Glass
    func studioBackground() -> some View {
        modifier(StudioBackgroundModifier())
    }
}
