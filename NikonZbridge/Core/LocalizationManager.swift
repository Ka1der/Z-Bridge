import SwiftUI

/// Поддерживаемые варианты выбора языка в приложении
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case russian = "ru"
    case english = "en"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system:
            return LocalizationManager.shared.activeLanguage == .ru ? "Системный" : "System Default"
        case .russian:
            return "Русский"
        case .english:
            return "English"
        }
    }
}

/// Фактически применяемый язык интерфейса
public enum ResolvedLanguage: String, Codable {
    case ru
    case en
    
    public var isRussian: Bool { self == .ru }
    public var isEnglish: Bool { self == .en }
}

/// Центральный менеджер локализации с сохранением предпочтений и определением системного языка
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    private static let storageKey = "selected_app_language_preference"
    
    @Published public var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.storageKey)
            updateActiveLanguage()
        }
    }
    
    @Published public private(set) var activeLanguage: ResolvedLanguage = .en
    @Published public private(set) var detectedSystemLanguageCode: String = "en"
    
    private init() {
        let savedRaw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        self.selectedLanguage = AppLanguage(rawValue: savedRaw) ?? .system
        updateActiveLanguage()
    }
    
    /// Пересчёт активного языка в соответствии с правилом:
    /// - Если выбран конкретный язык (ru или en), используется он;
    /// - Если выбран «системный», считывается основной язык системы.
    ///   Если это русский (ru) — используется русский, во всех остальных случаях (en или любой нереализованный) — английский.
    public func updateActiveLanguage() {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        self.detectedSystemLanguageCode = preferred
        
        switch selectedLanguage {
        case .russian:
            self.activeLanguage = .ru
        case .english:
            self.activeLanguage = .en
        case .system:
            if preferred.hasPrefix("ru") {
                self.activeLanguage = .ru
            } else {
                // Если язык системы не реализован в приложении — по ТЗ устанавливается английский
                self.activeLanguage = .en
            }
        }
    }
    
    /// Отображаемое имя обнаруженного системного языка
    public var detectedSystemLanguageDisplayName: String {
        if detectedSystemLanguageCode.hasPrefix("ru") {
            return activeLanguage == .ru ? "Русский (ru)" : "Russian (ru)"
        } else if detectedSystemLanguageCode.hasPrefix("en") {
            return activeLanguage == .ru ? "Английский (en)" : "English (en)"
        } else {
            let code = Locale.current.language.languageCode?.identifier ?? detectedSystemLanguageCode
            return activeLanguage == .ru ? "\(code) (не реализован → English)" : "\(code) (not supported → English)"
        }
    }
}

/// Глобальная вспомогательная функция для чистой локализации строк
@inline(__always)
public func tr(_ ru: String, _ en: String) -> String {
    LocalizationManager.shared.activeLanguage == .ru ? ru : en
}
