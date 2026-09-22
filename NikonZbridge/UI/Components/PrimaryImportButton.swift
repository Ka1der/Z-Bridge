import SwiftUI

/// Универсальная акцентная кнопка «Импортировать» для запуска и контроля загрузки с камеры.
/// 
/// Особенности:
/// - Единый системный синий акцент согласно гайдлайнам оформления Liquid Glass;
/// - Минимальная площадь нажатия 44 × 44 pt;
/// - Иконка со стрелкой «↓» и адаптивный текст (ViewThatFits: «Импортировать» / «Импорт»);
/// - Интегрированное состояние чтения каталога карты памяти (анимированный спиннер);
/// - Бейдж количества новых неимпортированных кадров;
/// - Полная поддержка VoiceOver и динамических шрифтов (Dynamic Type).
public struct PrimaryImportButton: View {
    public let isReadingCatalog: Bool
    public let unimportedCount: Int
    public let title: String
    public let shortTitle: String
    public let loadingTitle: String
    public let iconName: String
    public let action: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        isReadingCatalog: Bool = false,
        unimportedCount: Int = 0,
        title: String = "Импортировать",
        shortTitle: String = "Импорт",
        loadingTitle: String = "Чтение...",
        iconName: String = "arrow.down",
        action: @escaping () -> Void
    ) {
        self.isReadingCatalog = isReadingCatalog
        self.unimportedCount = unimportedCount
        self.title = title
        self.shortTitle = shortTitle
        self.loadingTitle = loadingTitle
        self.iconName = iconName
        self.action = action
    }
    
    public var body: some View {
        Button {
            guard !isReadingCatalog else { return }
            action()
        } label: {
            HStack(spacing: AppTheme.Spacing.xs + 2) {
                if isReadingCatalog {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                    
                    Text(loadingTitle)
                        .font(AppTheme.Typography.subheadlineBold)
                        .lineLimit(1)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                    
                    ViewThatFits(in: .horizontal) {
                        Text(title)
                            .font(AppTheme.Typography.subheadlineBold)
                            .lineLimit(1)
                        
                        Text(shortTitle)
                            .font(AppTheme.Typography.subheadlineBold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    if unimportedCount > 0 {
                        Text("\(unimportedCount)")
                            .font(AppTheme.Typography.caption2Bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.32))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
            .background(AppTheme.Colors.accent)
            .foregroundStyle(Color.white)
            .clipShape(Capsule())
            .shadow(color: AppTheme.Colors.accent.opacity(0.3), radius: 6, x: 0, y: 2)
        }
        .disabled(isReadingCatalog)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isReadingCatalog ? "Пожалуйста, подождите завершения чтения карты памяти" : "Нажмите для выбора и загрузки снимков с карты памяти камеры")
    }
    
    private var accessibilityText: String {
        if isReadingCatalog {
            return "Идет чтение карты памяти камеры"
        } else if unimportedCount > 0 {
            return "\(title). Доступно неимпортированных снимков: \(unimportedCount)"
        } else {
            return title
        }
    }
}
