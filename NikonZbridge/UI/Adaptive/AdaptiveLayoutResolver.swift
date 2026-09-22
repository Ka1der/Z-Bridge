import SwiftUI

/// Режим компоновки адаптивного каркаса
public enum AppLayoutMode: Equatable, Sendable {
    case narrow // Нижняя навигация (Liquid Glass Dock)
    case wide   // Боковая панель (Liquid Glass Sidebar)
}

/// Чистый резолвер компоновки на основе доступной ширины окна и масштаба системного шрифта (Dynamic Type).
/// Полностью исключает привязку исключительно к UIDevice.userInterfaceIdiom.
public struct AdaptiveLayoutResolver: Sendable {
    /// Базовый порог ширины в pt при стандартном размере текста (Large)
    public static let baseBreakpointWidth: CGFloat = 680.0
    
    /// Вычисляет режим компоновки исходя из ширины окна и масштаба системного шрифта (Dynamic Type)
    public static func resolve(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> AppLayoutMode {
        let scale: CGFloat
        switch dynamicTypeSize {
        case .xSmall, .small:
            scale = 0.95
        case .medium, .large:
            scale = 1.00
        case .xLarge:
            scale = 1.08
        case .xxLarge:
            scale = 1.16
        case .xxxLarge:
            scale = 1.25
        case .accessibility1:
            scale = 1.35
        case .accessibility2:
            scale = 1.48
        case .accessibility3:
            scale = 1.62
        case .accessibility4:
            scale = 1.76
        case .accessibility5:
            scale = 1.90
        @unknown default:
            scale = 1.00
        }
        
        let dynamicBreakpoint = baseBreakpointWidth * scale
        return width >= dynamicBreakpoint ? .wide : .narrow
    }
}
