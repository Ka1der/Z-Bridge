import SwiftUI

/// Поддерживаемые варианты масштаба шрифта и элементов интерфейса
public enum AppFontSizeOption: String, CaseIterable, Identifiable, Codable {
    case compact = "compact"       // Компактный (-2 pt)
    case standard = "standard"     // Стандартный (0 pt)
    case medium = "medium"         // Увеличенный (+2.5 pt)
    case large = "large"           // Крупный (+5.0 pt)
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .compact:
            return tr("Компактный", "Compact")
        case .standard:
            return tr("Стандарт", "Standard")
        case .medium:
            return tr("Увеличенный", "Large")
        case .large:
            return tr("Крупный", "Extra Large")
        }
    }
    
    /// Смещение размера шрифта в пунктах (pt)
    public var fontOffset: CGFloat {
        switch self {
        case .compact:
            return -2.0
        case .standard:
            return 0.0
        case .medium:
            return 2.5
        case .large:
            return 5.0
        }
    }
    
    /// Множитель масштаба
    public var scaleMultiplier: CGFloat {
        switch self {
        case .compact:
            return 0.88
        case .standard:
            return 1.0
        case .medium:
            return 1.15
        case .large:
            return 1.30
        }
    }
}

/// Центральный менеджер масштабирования шрифтов приложения с сохранением в UserDefaults
public final class AppFontSizeManager: ObservableObject {
    public static let shared = AppFontSizeManager()
    
    private static let storageKey = "selected_app_font_size_preference"
    
    @Published public var selectedOption: AppFontSizeOption {
        didSet {
            UserDefaults.standard.set(selectedOption.rawValue, forKey: Self.storageKey)
        }
    }
    
    public var fontOffset: CGFloat {
        selectedOption.fontOffset
    }
    
    public var scaleMultiplier: CGFloat {
        selectedOption.scaleMultiplier
    }
    
    private init() {
        let savedRaw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppFontSizeOption.standard.rawValue
        self.selectedOption = AppFontSizeOption(rawValue: savedRaw) ?? .standard
    }
    
    /// Разрешение DynamicTypeSize для окружения SwiftUI в зависимости от платформы
    public func resolvedDynamicTypeSize(isMac: Bool) -> DynamicTypeSize {
        switch selectedOption {
        case .compact:
            return isMac ? .large : .medium
        case .standard:
            return isMac ? .xLarge : .large
        case .medium:
            return isMac ? .xxLarge : .xLarge
        case .large:
            return isMac ? .xxxLarge : .xxLarge
        }
    }
}
