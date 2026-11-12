import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Переиспользуемая дизайн-система приложения NikonZbridge в концепции современного минимализма («Liquid Glass»).
/// Содержит семантические токены цветов, типографики, интервалов,
/// скруглений, геометрии и базовых стилей кнопок, оптимизированных для iPadOS и iOS.
public enum AppTheme {
    
    // MARK: - 1. Цвета (Semantic Colors)
    
    public enum Colors {
        
        // Вспомогательные методы создания кроссплатформенных адаптивных цветов
        private static func platformDynamicColor(
            darkRed: CGFloat, darkGreen: CGFloat, darkBlue: CGFloat, darkAlpha: CGFloat = 1.0,
            lightRed: CGFloat, lightGreen: CGFloat, lightBlue: CGFloat, lightAlpha: CGFloat = 1.0
        ) -> Color {
            #if canImport(UIKit)
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: darkRed, green: darkGreen, blue: darkBlue, alpha: darkAlpha)
                    : UIColor(red: lightRed, green: lightGreen, blue: lightBlue, alpha: lightAlpha)
            })
            #elseif canImport(AppKit)
            return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: darkRed, green: darkGreen, blue: darkBlue, alpha: darkAlpha)
                    : NSColor(red: lightRed, green: lightGreen, blue: lightBlue, alpha: lightAlpha)
            }))
            #else
            return Color(red: darkRed, green: darkGreen, blue: darkBlue, opacity: darkAlpha)
            #endif
        }
        
        private static func platformAlphaColor(
            darkWhite: CGFloat, darkAlpha: CGFloat,
            lightWhite: CGFloat, lightAlpha: CGFloat
        ) -> Color {
            #if canImport(UIKit)
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: darkWhite, alpha: darkAlpha)
                    : UIColor(white: lightWhite, alpha: lightAlpha)
            })
            #elseif canImport(AppKit)
            return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: darkWhite, alpha: darkAlpha)
                    : NSColor(white: lightWhite, alpha: lightAlpha)
            }))
            #else
            return Color(white: darkWhite, opacity: darkAlpha)
            #endif
        }
        
        /// Глубокий обсидиановый фон студии в тёмной теме (#0E0F12) и нейтральный светло-серый в светлой теме (#F2F3F7)
        public static let background = platformDynamicColor(
            darkRed: 0x0E / 255.0, darkGreen: 0x0F / 255.0, darkBlue: 0x12 / 255.0,
            lightRed: 0xF2 / 255.0, lightGreen: 0xF3 / 255.0, lightBlue: 0xF7 / 255.0
        )
        
        /// Основная поверхность карточек (#15161B в тёмной / #FFFFFF в светлой)
        public static let surfacePrimary = platformDynamicColor(
            darkRed: 0x15 / 255.0, darkGreen: 0x16 / 255.0, darkBlue: 0x1B / 255.0,
            lightRed: 1.0, lightGreen: 1.0, lightBlue: 1.0
        )
        
        /// Вторичная поверхность (#1B1D24 в тёмной / #E8E9EE в светлой)
        public static let surfaceSecondary = platformDynamicColor(
            darkRed: 0x1B / 255.0, darkGreen: 0x1D / 255.0, darkBlue: 0x24 / 255.0,
            lightRed: 0xE8 / 255.0, lightGreen: 0xE9 / 255.0, lightBlue: 0xEE / 255.0
        )
        
        /// Приподнятая поверхность HUD / плавающих плашек (#22242D в тёмной / #FFFFFF в светлой)
        public static let surfaceElevated = platformDynamicColor(
            darkRed: 0x22 / 255.0, darkGreen: 0x24 / 255.0, darkBlue: 0x2D / 255.0,
            lightRed: 1.0, lightGreen: 1.0, lightBlue: 1.0
        )
        
        /// Фирменный желтый акцент Nikon (#FFE600 в тёмной теме, контрастный янтарный #D49B00 в светлой)
        public static let accent = platformDynamicColor(
            darkRed: 1.0, darkGreen: 0xE6 / 255.0, darkBlue: 0.0,
            lightRed: 0xD4 / 255.0, lightGreen: 0x9B / 255.0, lightBlue: 0.0
        )
        
        /// Акцентный цвет при нажатии
        public static let accentPressed = platformDynamicColor(
            darkRed: 0xE6 / 255.0, darkGreen: 0xCF / 255.0, darkBlue: 0.0,
            lightRed: 0xB3 / 255.0, lightGreen: 0x83 / 255.0, lightBlue: 0.0
        )
        
        /// Цвет контрастного текста и пиктограмм поверх акцентной подложки
        /// (Глубокий чёрный на желтом фоне в тёмной теме, белый на янтарном фоне в светлой)
        public static let onAccent = platformDynamicColor(
            darkRed: 0x0E / 255.0, darkGreen: 0x0F / 255.0, darkBlue: 0x12 / 255.0,
            lightRed: 1.0, lightGreen: 1.0, lightBlue: 1.0
        )
        
        /// Полупрозрачный желтый оттенок для подложек активных элементов
        public static let accentMuted = accent.opacity(0.18)
        
        /// Фирменный желтый цвет для активного рейтинга звезд
        public static let ratingActive = accent
        
        /// Неактивные звезды рейтинга
        public static let ratingInactive = platformAlphaColor(
            darkWhite: 1.0, darkAlpha: 0.22,
            lightWhite: 0.0, lightAlpha: 0.18
        )
        
        /// Тонкий микро-контур стеклянных панелей (8% белый в тёмной теме, 6% чёрный в светлой)
        public static let borderSubtle = platformAlphaColor(
            darkWhite: 1.0, darkAlpha: 0.08,
            lightWhite: 0.0, lightAlpha: 0.06
        )
        
        /// Усиленный контур для активных/выделенных элементов и режима высокой контрастности
        public static let borderStrong = platformAlphaColor(
            darkWhite: 1.0, darkAlpha: 0.22,
            lightWhite: 0.0, lightAlpha: 0.16
        )
        
        /// Мягкая тень панелей
        public static let shadow = platformAlphaColor(
            darkWhite: 0.0, darkAlpha: 0.24,
            lightWhite: 0.0, lightAlpha: 0.06
        )
        
        // Текстовые цвета
        #if canImport(UIKit)
        public static let textPrimary = Color(uiColor: .label)
        public static let textSecondary = Color(uiColor: .secondaryLabel)
        public static let textTertiary = Color(uiColor: .tertiaryLabel)
        #elseif canImport(AppKit)
        public static let textPrimary = Color(nsColor: .labelColor)
        public static let textSecondary = Color(nsColor: .secondaryLabelColor)
        public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        #else
        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
        public static let textTertiary = Color.secondary.opacity(0.6)
        #endif
        
        // Статусные индикаторы (сопровождаются текстовыми и иконочными маркерами для доступности)
        public static let statusGreen = Color(red: 48 / 255.0, green: 209 / 255.0, blue: 88 / 255.0)
        public static let statusOrange = Color(red: 255 / 255.0, green: 159 / 255.0, blue: 10 / 255.0)
        public static let statusRed = Color(red: 255 / 255.0, green: 69 / 255.0, blue: 58 / 255.0)
        public static let statusNeutral = Color(red: 142 / 255.0, green: 142 / 255.0, blue: 147 / 255.0)
        
        // Нейтральный фон для области просмотра фото без лишних свечений
        public static let photoReviewBackground = platformDynamicColor(
            darkRed: 0x08 / 255.0, darkGreen: 0x09 / 255.0, darkBlue: 0x0B / 255.0,
            lightRed: 0xEE / 255.0, lightGreen: 0xEF / 255.0, lightBlue: 0xF2 / 255.0
        )
        
        /// Синоним для нейтрального фона области просмотра фото
        public static let photoBackground = photoReviewBackground
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
        
        /// Высота компактных кнопок и чипов с учетом пользовательского масштаба
        public static var compactControlHeight: CGFloat {
            let base: CGFloat = isRunningOnMac ? 38 : 36
            return base + max(0, AppFontSizeManager.shared.fontOffset)
        }
        
        /// Стандартная толщина контура
        public static let borderWidth: CGFloat = 1.0
        
        /// Толщина контура в режиме высокой контрастности
        public static let borderWidthHighContrast: CGFloat = 1.5
    }
    
    // MARK: - 4.1 Платформенная адаптация под macOS
    
    /// Флаг запуска приложения в среде macOS (Apple Silicon "Designed for iPad", Mac Catalyst или нативный macOS)
    public static var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return true
        #else
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        } else {
            return false
        }
        #endif
    }
    
    /// Адаптивный размер шрифта с автоматической прибавкой для macOS и пользовательским масштабом
    public static func macFontSize(_ baseSize: CGFloat, macAdd: CGFloat = 2.0) -> CGFloat {
        let baseWithPlatform = isRunningOnMac ? (baseSize + macAdd) : baseSize
        let result = baseWithPlatform + AppFontSizeManager.shared.fontOffset
        return max(8, result)
    }
    
    // MARK: - 5. Типографика (Typography)
    
    public enum Typography {
        private static var offset: CGFloat {
            AppFontSizeManager.shared.fontOffset
        }
        
        public static var largeTitle: Font {
            Font.system(size: max(16, (AppTheme.isRunningOnMac ? 38 : 34) + offset), weight: .bold)
        }
        public static var title1: Font {
            Font.system(size: max(15, (AppTheme.isRunningOnMac ? 30 : 28) + offset), weight: .bold)
        }
        public static var title2: Font {
            Font.system(size: max(14, (AppTheme.isRunningOnMac ? 24 : 22) + offset), weight: .bold)
        }
        public static var title3: Font {
            Font.system(size: max(13, (AppTheme.isRunningOnMac ? 21 : 20) + offset), weight: .bold)
        }
        
        public static var headline: Font {
            Font.system(size: max(12, (AppTheme.isRunningOnMac ? 18 : 17) + offset), weight: .semibold)
        }
        public static var subheadline: Font {
            Font.system(size: max(11, (AppTheme.isRunningOnMac ? 16 : 15) + offset), weight: .regular)
        }
        public static var subheadlineBold: Font {
            Font.system(size: max(11, (AppTheme.isRunningOnMac ? 16 : 15) + offset), weight: .bold)
        }
        
        public static var body: Font {
            Font.system(size: max(12, (AppTheme.isRunningOnMac ? 18 : 17) + offset), weight: .regular)
        }
        public static var bodyBold: Font {
            Font.system(size: max(12, (AppTheme.isRunningOnMac ? 18 : 17) + offset), weight: .bold)
        }
        
        public static var callout: Font {
            Font.system(size: max(11, (AppTheme.isRunningOnMac ? 17 : 16) + offset), weight: .regular)
        }
        public static var footnote: Font {
            Font.system(size: max(10, (AppTheme.isRunningOnMac ? 14.5 : 13) + offset), weight: .regular)
        }
        
        public static var caption: Font {
            Font.system(size: max(9, (AppTheme.isRunningOnMac ? 13.5 : 12) + offset), weight: .regular)
        }
        public static var captionBold: Font {
            Font.system(size: max(9, (AppTheme.isRunningOnMac ? 13.5 : 12) + offset), weight: .bold)
        }
        public static var caption2: Font {
            Font.system(size: max(8, (AppTheme.isRunningOnMac ? 12.5 : 11) + offset), weight: .regular)
        }
        public static var caption2Bold: Font {
            Font.system(size: max(8, (AppTheme.isRunningOnMac ? 12.5 : 11) + offset), weight: .bold)
        }
        
        /// Моноширинный шрифт для IP, портов, скорости и метрик
        public static var code: Font {
            Font.system(size: max(9, (AppTheme.isRunningOnMac ? 13.5 : 12) + offset), weight: .regular, design: .monospaced)
        }
        public static var metricNumber: Font {
            Font.system(size: max(14, (AppTheme.isRunningOnMac ? 23 : 20) + offset), weight: .bold, design: .default).monospacedDigit()
        }
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
                .foregroundStyle(AppTheme.Colors.onAccent)
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
        @Environment(\.colorScheme) private var colorScheme
        
        public init() {}
        
        public func makeBody(configuration: Configuration) -> some View {
            let isHighContrast = (contrast == .increased)
            let strokeColor = isHighContrast ? AppTheme.Colors.borderStrong : AppTheme.Colors.borderSubtle
            let strokeWidth: CGFloat = isHighContrast ? AppTheme.Dimensions.borderWidthHighContrast : 0.8
            
            configuration.label
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: AppTheme.Dimensions.buttonHeight)
                .background(
                    Group {
                        if reduceTransparency {
                            AppTheme.Colors.surfaceSecondary
                        } else {
                            (colorScheme == .dark
                                ? Color(red: 26/255.0, green: 28/255.0, blue: 34/255.0).opacity(0.68)
                                : Color.white.opacity(0.70))
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isHighContrast
                                ? AnyShapeStyle(strokeColor)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.24), Color.white.opacity(0.06)]
                                            : [Color.white.opacity(0.75), Color.black.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                ),
                            lineWidth: strokeWidth
                        )
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.80 : 1.0) : 0.45)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
    
    /// Круглая стеклянная кнопка для иконочных действий (фильтры, «...», закрытие) min 44 × 44 pt
    public struct IconGlassButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.colorScheme) private var colorScheme
        
        public init() {}
        
        public func makeBody(configuration: Configuration) -> some View {
            let isHighContrast = (contrast == .increased)
            let strokeColor = isHighContrast ? AppTheme.Colors.borderStrong : AppTheme.Colors.borderSubtle
            let strokeWidth: CGFloat = isHighContrast ? AppTheme.Dimensions.borderWidthHighContrast : 0.8
            
            configuration.label
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                .background(
                    Group {
                        if reduceTransparency {
                            AppTheme.Colors.surfaceSecondary
                        } else {
                            (colorScheme == .dark
                                ? Color(red: 26/255.0, green: 28/255.0, blue: 34/255.0).opacity(0.68)
                                : Color.white.opacity(0.70))
                            .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isHighContrast
                                ? AnyShapeStyle(strokeColor)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.24), Color.white.opacity(0.06)]
                                            : [Color.white.opacity(0.75), Color.black.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                ),
                            lineWidth: strokeWidth
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

#if !os(iOS)
public enum NavigationBarItem {
    public enum TitleDisplayMode {
        case inline
        case large
        case automatic
    }
}

public extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
    
    @ViewBuilder
    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}
#endif

