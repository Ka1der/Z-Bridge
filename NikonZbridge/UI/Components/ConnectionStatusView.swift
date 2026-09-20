import SwiftUI

/// Переиспользуемый компонент статуса подключения к камере или серверу.
/// 
/// Особенности:
/// - Оформление на базе стеклянной панели (GlassSurface);
/// - Семантический индикатор статуса (зелёный/оранжевый/серый/красный);
/// - Доступность: статус не передаётся исключительно цветом, поддерживается
///   настройка «Дифференциация без цвета» (`accessibilityDifferentiateWithoutColor`);
/// - Минимальная площадь взаимодействия 44 × 44 pt при интерактивном режиме;
/// - Три режима отображения:
///   - `.inline`: аккуратная строка с цветной точкой для шапки экрана (как на референсе: «● Nikon Z5 · USB»);
///   - `.pill`: компактная плашка HUD со стеклянным фоном;
///   - `.card`: полноразмерная карточка для дашборда и настроек.
public struct ConnectionStatusView: View {
    
    public enum Status: Equatable {
        case connected
        case connecting
        case disconnected
        case idle
        
        public var defaultColor: Color {
            switch self {
            case .connected: return AppTheme.Colors.statusGreen
            case .connecting: return AppTheme.Colors.statusOrange
            case .disconnected: return AppTheme.Colors.statusRed
            case .idle: return AppTheme.Colors.statusNeutral
            }
        }
        
        public var accessibilityDescription: String {
            switch self {
            case .connected: return "Подключено"
            case .connecting: return "Подключение"
            case .disconnected: return "Отключено"
            case .idle: return "Остановлен"
            }
        }
        
        public var shapeSymbol: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .connecting: return "arrow.triangle.2.circlepath"
            case .disconnected: return "xmark.circle.fill"
            case .idle: return "minus.circle.fill"
            }
        }
    }
    
    public enum Style {
        case inline
        case pill
        case card
    }
    
    public let status: Status
    public let title: String
    public let shortTitle: String?
    public let detail: String?
    public let iconName: String?
    public let style: Style
    public let action: (() -> Void)?
    
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    
    public init(
        status: Status,
        title: String,
        shortTitle: String? = nil,
        detail: String? = nil,
        iconName: String? = nil,
        style: Style = .pill,
        action: (() -> Void)? = nil
    ) {
        self.status = status
        self.title = title
        self.shortTitle = shortTitle
        self.detail = detail
        self.iconName = iconName
        self.style = style
        self.action = action
    }
    
    public var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(status.accessibilityDescription): \(title)")
            .accessibilityHint("Нажмите для открытия настроек подключения")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(status.accessibilityDescription): \(title)")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch style {
        case .inline:
            inlineLayout
        case .pill:
            pillLayout
        case .card:
            cardLayout
        }
    }
    
    // MARK: - 1. Inline строка (референс «Студийная съёмка \n ● Nikon Z5 · USB»)
    
    private var inlineLayout: some View {
        HStack(spacing: AppTheme.Spacing.xs + 2) {
            statusDot
            
            Text(title)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
            
            if differentiateWithoutColor {
                Image(systemName: status.shapeSymbol)
                    .font(.caption2)
                    .foregroundStyle(status.defaultColor)
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: action != nil ? AppTheme.Dimensions.minTouchTarget : nil)
    }
    
    // MARK: - 2. Компактный Pill для верхнего HUD
    
    private var pillLayout: some View {
        HStack(spacing: AppTheme.Spacing.xs + 2) {
            if let icon = iconName {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(status.defaultColor)
            } else {
                statusDot
            }
            
            if let short = shortTitle {
                ViewThatFits(in: .horizontal) {
                    Text(title)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(short)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                }
            } else {
                Text(title)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
            }
            
            if differentiateWithoutColor {
                Image(systemName: status.shapeSymbol)
                    .font(.caption2)
                    .foregroundStyle(status.defaultColor)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
        .glassPill()
    }
    
    // MARK: - 3. Карточка для дашборда
    
    private var cardLayout: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if let icon = iconName {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(status.defaultColor)
                    .frame(width: 36, height: 36)
            } else {
                statusDot
                    .scaleEffect(1.2)
            }
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(title)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    if differentiateWithoutColor {
                        Image(systemName: status.shapeSymbol)
                            .font(.caption2)
                            .foregroundStyle(status.defaultColor)
                    }
                }
                
                if let detail = detail {
                    Text(detail)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            
            Spacer(minLength: AppTheme.Spacing.sm)
            
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
        .glassSurface(cornerRadius: AppTheme.Radius.md)
    }
    
    // MARK: - Точечный индикатор
    
    private var statusDot: some View {
        Circle()
            .fill(status.defaultColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(AppTheme.Colors.borderSubtle, lineWidth: 0.5)
            )
    }
}
