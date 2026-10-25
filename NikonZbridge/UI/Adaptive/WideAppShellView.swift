import SwiftUI

/// Широкая компоновка адаптивного каркаса (iPad, ландшафтный режим, macOS).
/// Реализована в точности по референсу дизайна Liquid Glass:
/// - Узкая компактная боковая панель (~88 pt) с логотипом Z-Bridge, кнопкой меню и 4 ключевыми разделами
///   («Tether» с желтой рамкой и индикатором, «Storage», «Sessions», «Settings»);
/// - Полноэкранная рабочая зона без лишних статических полос.
public struct WideAppShellView: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // 1. Боковая панель навигации (Pro Slim Rail)
            if !appState.isSidebarCollapsed {
                proSidebarRail
                    .frame(width: 88)
                    .background(
                        Color(red: 20/255.0, green: 22/255.0, blue: 27/255.0).opacity(0.85)
                            .background(.ultraThinMaterial)
                    )
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1),
                        alignment: .trailing
                    )
                    .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
            } else {
                collapsedSidebarRail
            }
            
            // 2. Основная рабочая область активного раздела
            VStack(spacing: 0) {
                switch appState.selectedSection {
                case .photos:
                    NikonTetherRootView(appState: appState)
                case .camera:
                    CameraSectionView(appState: appState)
                case .settings:
                    SettingsSectionView(appState: appState)
                case .sessions:
                    if AppFeatures.sessionManagementEnabled {
                        SessionsSectionView(appState: appState)
                    } else {
                        NikonTetherRootView(appState: appState)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Pro Slim Sidebar (согласно референсу iPad)
    
    private var proSidebarRail: some View {
        VStack(spacing: 0) {
            // Заголовок приложения: Z-Bridge + иконка меню
            HStack(alignment: .center, spacing: 4) {
                Text("Z-Bridge")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                
                Spacer()
                
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        appState.toggleSidebar()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Свернуть боковую панель")
            }
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 24)
            
            // 4 вертикальных раздела
            VStack(spacing: 14) {
                // 1. Tether (Съемка)
                proRailItem(
                    title: tr("Съемка", "Tether"),
                    iconName: "photo.on.rectangle",
                    isSelected: appState.selectedSection == .photos
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        appState.selectedSection = .photos
                    }
                }
                
                // 2. Connect (Подключение)
                proRailItem(
                    title: tr("Камера", "Connect"),
                    iconName: "cable.connector",
                    isSelected: appState.selectedSection == .camera
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        appState.selectedSection = .camera
                    }
                }
                
                // 3. Settings (Настройки)
                proRailItem(
                    title: tr("Настройки", "Settings"),
                    iconName: "gearshape",
                    isSelected: appState.selectedSection == .settings
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        appState.selectedSection = .settings
                    }
                }
                
                // 4. Sessions (Сессии)
                if AppFeatures.sessionManagementEnabled {
                    proRailItem(
                        title: tr("Сессии", "Sessions"),
                        iconName: "list.bullet.rectangle",
                        isSelected: appState.selectedSection == .sessions
                    ) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            appState.selectedSection = .sessions
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Кнопка раздела сайдбара
    
    private func proRailItem(
        title: String,
        iconName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Желтая вертикальная черта-индикатор на левом крае
                if isSelected {
                    Capsule()
                        .fill(AppTheme.Colors.accent)
                        .frame(width: 3, height: 24)
                        .offset(x: -6)
                }
                
                VStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.Colors.accent : Color.white.opacity(0.65))
                    
                    Text(title)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.Colors.accent : Color.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppTheme.Colors.accent.opacity(0.85), lineWidth: 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(AppTheme.Colors.accent.opacity(0.08))
                                )
                        } else {
                            Color.clear
                        }
                    }
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    // MARK: - Свернутый минималистичный вид
    
    private var collapsedSidebarRail: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    appState.toggleSidebar()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(width: 40, height: 40)
                    .glassSurface(shape: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Развернуть боковую панель")
            .padding(.top, 16)
            
            Divider()
                .padding(.horizontal, AppTheme.Spacing.xs)
            
            // Иконки разделов
            VStack(spacing: 12) {
                collapsedItem(iconName: "photo.on.rectangle", isSelected: appState.selectedSection == .photos) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        appState.selectedSection = .photos
                    }
                }
                
                collapsedItem(iconName: "cable.connector", isSelected: appState.selectedSection == .camera) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        appState.selectedSection = .camera
                    }
                }
                
                collapsedItem(iconName: "gearshape", isSelected: appState.selectedSection == .settings) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        appState.selectedSection = .settings
                    }
                }
                
                if AppFeatures.sessionManagementEnabled {
                    collapsedItem(iconName: "list.bullet.rectangle", isSelected: appState.selectedSection == .sessions) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            appState.selectedSection = .sessions
                        }
                    }
                }
            }
            
            Spacer()
        }
        .frame(width: 52)
        .background(
            Color(red: 20/255.0, green: 22/255.0, blue: 27/255.0).opacity(0.85)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: .trailing
        )
        .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
    }
    
    private func collapsedItem(iconName: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? AppTheme.Colors.accent : Color.white.opacity(0.65))
                .frame(width: 36, height: 36)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.Colors.accent, lineWidth: 1.5)
                                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.accent.opacity(0.12)))
                        } else {
                            Color.clear
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}
