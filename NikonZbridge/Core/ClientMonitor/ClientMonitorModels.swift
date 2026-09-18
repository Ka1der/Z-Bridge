import Foundation
import SwiftUI

/// Режим фильтрации кадров для клиентского монитора
public enum ClientMonitorFilterMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case all = "Все кадры"
    case onlyPicked = "Только отобранные (Pick)"
    case rated1Plus = "Рейтинг ★ 1+"
    case rated2Plus = "Рейтинг ★ 2+"
    case rated3Plus = "Рейтинг ★ 3+"
    case rated4Plus = "Рейтинг ★ 4+"
    case rated5Only = "Рейтинг ★ 5"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "photo.stack"
        case .onlyPicked: return "flag.fill"
        case .rated1Plus, .rated2Plus, .rated3Plus, .rated4Plus, .rated5Only: return "star.fill"
        }
    }
    
    /// Проверка, подходит ли кадр под критерии фильтра клиентского монитора
    public func matches(group: CaptureGroup) -> Bool {
        switch self {
        case .all:
            return true
        case .onlyPicked:
            return group.pickStatus == .picked
        case .rated1Plus:
            return group.rating >= 1
        case .rated2Plus:
            return group.rating >= 2
        case .rated3Plus:
            return group.rating >= 3
        case .rated4Plus:
            return group.rating >= 4
        case .rated5Only:
            return group.rating == 5
        }
    }
    
    public func matches(asset: MediaAsset) -> Bool {
        switch self {
        case .all:
            return true
        case .onlyPicked:
            return asset.pickStatus == .picked
        case .rated1Plus:
            return asset.rating >= 1
        case .rated2Plus:
            return asset.rating >= 2
        case .rated3Plus:
            return asset.rating >= 3
        case .rated4Plus:
            return asset.rating >= 4
        case .rated5Only:
            return asset.rating == 5
        }
    }
}

/// Настройка задержки автоматического переключения клиентского монитора
public enum SwitchDelayOption: Double, CaseIterable, Identifiable, Sendable, Codable {
    case instant = 0.0
    case halfSecond = 0.5
    case oneSecond = 1.0
    case twoSeconds = 2.0
    case threeSeconds = 3.0
    case fiveSeconds = 5.0
    
    public var id: Double { rawValue }
    
    public var seconds: TimeInterval { rawValue }
    
    public var displayName: String {
        switch self {
        case .instant: return "Мгновенно (0 с)"
        case .halfSecond: return "0.5 сек"
        case .oneSecond: return "1 сек (Оптимально)"
        case .twoSeconds: return "2 сек"
        case .threeSeconds: return "3 сек"
        case .fiveSeconds: return "5 сек"
        }
    }
}

/// Статус подключения внешнего экрана (HDMI / USB-C / AirPlay)
public enum ExternalDisplayStatus: Sendable, Equatable {
    case disconnected
    case connected(name: String, resolution: String)
    
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    public var displayName: String {
        switch self {
        case .disconnected:
            return "Внешний экран не подключен"
        case .connected(let name, let resolution):
            return "\(name) (\(resolution))"
        }
    }
}

/// Конфигурация клиентского монитора
public struct ClientMonitorConfig: Sendable, Codable, Equatable {
    public var switchDelay: SwitchDelayOption
    public var filterMode: ClientMonitorFilterMode
    public var isHoldEnabled: Bool
    public var heldGroupID: String?
    public var showSubtleOverlay: Bool
    public var transitionDuration: Double
    
    public init(
        switchDelay: SwitchDelayOption = .oneSecond,
        filterMode: ClientMonitorFilterMode = .all,
        isHoldEnabled: Bool = false,
        heldGroupID: String? = nil,
        showSubtleOverlay: Bool = true,
        transitionDuration: Double = 0.35
    ) {
        self.switchDelay = switchDelay
        self.filterMode = filterMode
        self.isHoldEnabled = isHoldEnabled
        self.heldGroupID = heldGroupID
        self.showSubtleOverlay = showSubtleOverlay
        self.transitionDuration = transitionDuration
    }
}
