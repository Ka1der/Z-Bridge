import SwiftUI

/// Переиспользуемая дизайн-система приложения NikonZbridge в концепции «Liquid Glass».
/// Содержит семантические токены цветов, типографики, интервалов,
/// скруглений, геометрии и базовых стилей кнопок.
public enum AppTheme {
    
    // MARK: - 1. Цвета (Semantic Colors)
    
    public enum Colors {
        /// Спокойный графитовый фон в тёмной теме (#121316) и нейтральный светло-серый в светлой теме (#F2F3F7)
        public static let background = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x12 / 255.0, green: 0x13 / 255.0, blue: 0x16 / 255.0, alpha: 1.0)
                : UIColor(red: 0xF2 / 255.0, green: 0xF3 / 255.0, blue: 0xF7 / 255.0, alpha: 1.0)
        })
        
        /// Основная поверхность карточек (#1A1B20 в тёмной / #FFFFFF в светлой)
        public static let surfacePrimary = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x1A / 255.0, green: 0x1B / 255.0, blue: 0x20 / 255.0, alpha: 1.0)
                : UIColor.systemBackground
        })
        
        /// Вторичная поверхность (#22242B в тёмной / #E8E9EE в светлой)
        public static let surfaceSecondary = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x22 / 255.0, green: 0x24 / 255.0, blue: 0x2B / 255.0, alpha: 1.0)
                : UIColor.secondarySystemBackground
        })
        
        /// Приподнятая поверхность HUD / плавающих плашек (#282A32 в тёмной / #FFFFFF в светлой)
        public static let surfaceElevated = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x28 / 255.0, green: 0x2A / 255.0, blue: 0x32 / 255.0, alpha: 1.0)
                : UIColor.tertiarySystemBackground
        })
        
        /// Единый синий акцент (#0A84FF в тёмной теме, #007AFF в светлой)
        public static let accent = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
                : UIColor(red: 0x00 / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
        })
        
        /// Акцентный цвет при нажатии
        public static let accentPressed = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x00 / 255.0, green: 0x66 / 255.0, blue: 0xCC / 255.0, alpha: 1.0)
                : UIColor(red: 0x00 / 255.0, green: 0x55 / 255.0, blue: 0xB3 / 255.0, alpha: 1.0)
        })
        
        /// Полупрозрачный синий оттенок для подложек активных элементов
        public static let accentMuted = accent.opacity(0.18)
        
        /// Синий цвет для активного рейтинга звезд (согласно референсу Liquid Glass)
        public static let ratingActive = accent
        
        /// Неактивные звезды рейтинга
        public static let ratingInactive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.22)
                : UIColor(white: 0.0, alpha: 0.18)
        })
        
        /// Тонкий контур стеклянных панелей (12% белый в тёмной теме, 8% чёрный в светлой)
        public static let borderSubtle = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 0.0, alpha: 0.08)
        })
        
        /// Усиленный контур для активных/выделенных элементов и режима высокой контрастности
        public static let borderStrong = Color(uiColor: UIColor { traits in
            if traits.accessibilityContrast == .high {
                return traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.40)
                    : UIColor(white: 0.0, alpha: 0.35)
            }
            return traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.24)
                : UIColor(white: 0.0, alpha: 0.16)
        })
        
        /// Мягкая тень панелей
        public static let shadow = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.0, alpha: 0.28)
                : UIColor(white: 0.0, alpha: 0.08)
        })
        
        // Текстовые цвета
        public static let textPrimary = Color(uiColor: .label)
        public static let textSecondary = Color(uiColor: .secondaryLabel)
        public static let textTertiary = Color(uiColor: .tertiaryLabel)
        
        // Статусные индикаторы (сопровождаются текстовыми и иконочными маркерами для доступности)
        public static let statusGreen = Color(red: 48 / 255.0, green: 209 / 255.0, blue: 88 / 255.0)
        public static let statusOrange = Color(red: 255 / 255.0, green: 159 / 255.0, blue: 10 / 255.0)
        public static let statusRed = Color(red: 255 / 255.0, green: 69 / 255.0, blue: 58 / 255.0)
        public static let statusNeutral = Color(red: 142 / 255.0, green: 142 / 255.0, blue: 147 / 255.0)
        
        // Нейтральный фон для области просмотра фото без лишних свечений
        public static let photoReviewBackground = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0C / 255.0, alpha: 1.0)
                : UIColor(red: 0xEE / 255.0, green: 0xEF / 255.0, blue: 0xF2 / 255.0, alpha: 1.0)
        })
    }
    
    // MARK: - 2. Интервалы (Spacing)
    
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let section: CGFloat = 32
    }
    
    // MARK: - 3. Скругления (Radius)
    
    public enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let pill: CGFloat = 999
    }
    
    // MARK: - 4. Размеры и доступность (Dimensions)
    
    public enum Dimensions {
        /// Минимальная площадь нажатия согласно HIG (44 × 44 pt)
        public static let minTouchTarget: CGFloat = 44
        
        /// Высота стандартных кнопок действий
        public static let buttonHeight: CGFloat = 44
        
        /// Высота компактных кнопок и чипов
        public static let compactControlHeight: CGFloat = 36
        
        /// Стандартная толщина контура
        public static let borderWidth: CGFloat = 1.0
        
        /// Толщина контура в режиме высокой контрастности
        public static let borderWidthHighContrast: CGFloat = 1.5
    }
    
    // MARK: - 5. Типографика (Typography)
    
    public enum Typography {
        public static let largeTitle = Font.largeTitle.bold()
        public static let title1 = Font.title.bold()
        public static let title2 = Font.title2.bold()
        public static let title3 = Font.title3.bold()
        
        public static let headline = Font.headline
        public static let subheadline = Font.subheadline
        public static let subheadlineBold = Font.subheadline.bold()
        
        public static let body = Font.body
        public static let bodyBold = Font.body.bold()
        
        public static let callout = Font.callout
        public static let footnote = Font.footnote
        
        public static let caption = Font.caption
        public static let captionBold = Font.caption.bold()
        public static let caption2 = Font.caption2
        public static let caption2Bold = Font.caption2.bold()
        
        /// Моноширинный шрифт для IP, портов, скорости и метрик
        public static let code = Font.system(.caption, design: .monospaced)
        public static let metricNumber = Font.system(.title3, design: .default, weight: .bold).monospacedDigit()
    }
    
    // MARK: - 6. Стили кнопок (Button Styles)
    
    /// Основная кнопка действия (синий акцент, белый текст, min 44 pt)
    public struct PrimaryButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        
        public init() {}
        
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(Color.white)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(minHeight: AppTheme.Dimensions.buttonHeight)
                .background(
                    configuration.isPressed
                        ? AppTheme.Colors.accentPressed
                        : AppTheme.Colors.accent
                )
                .clipShape(Capsule())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
    
    /// Вторичная кнопка со стеклянной панелью (нейтральный тон, тонкий контур, min 44 pt)
    public struct SecondaryGlassButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast
        
        public init() {}
        
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: AppTheme.Dimensions.buttonHeight)
                .background(
                    Group {
                        if reduceTransparency {
                            AppTheme.Colors.surfaceSecondary
                        } else {
                            Color(uiColor: .secondarySystemFill)
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            contrast == .increased ? AppTheme.Colors.borderStrong : AppTheme.Colors.borderSubtle,
                            lineWidth: contrast == .increased ? AppTheme.Dimensions.borderWidthHighContrast : AppTheme.Dimensions.borderWidth
                        )
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1.0) : 0.45)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
    
    /// Круглая стеклянная кнопка для иконочных действий (фильтры, «...», закрытие) min 44 × 44 pt
    public struct IconGlassButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast
        
        public init() {}
        
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                .background(
                    Group {
                        if reduceTransparency {
                            AppTheme.Colors.surfaceSecondary
                        } else {
                            Color(uiColor: .secondarySystemFill)
                        }
                    }
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            contrast == .increased ? AppTheme.Colors.borderStrong : AppTheme.Colors.borderSubtle,
                            lineWidth: contrast == .increased ? AppTheme.Dimensions.borderWidthHighContrast : AppTheme.Dimensions.borderWidth
                        )
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1.0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1.0) : 0.45)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

// MARK: - ButtonStyle Convenience Extensions

public extension ButtonStyle where Self == AppTheme.PrimaryButtonStyle {
    static var appPrimary: AppTheme.PrimaryButtonStyle {
        AppTheme.PrimaryButtonStyle()
    }
}

public extension ButtonStyle where Self == AppTheme.SecondaryGlassButtonStyle {
    static var appSecondaryGlass: AppTheme.SecondaryGlassButtonStyle {
        AppTheme.SecondaryGlassButtonStyle()
    }
}

public extension ButtonStyle where Self == AppTheme.IconGlassButtonStyle {
    static var appIconGlass: AppTheme.IconGlassButtonStyle {
        AppTheme.IconGlassButtonStyle()
    }
}
