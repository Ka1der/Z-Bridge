import SwiftUI

/// Широкая компоновка адаптивного каркаса Liquid Glass (iPad, широкий Split View, горизонтальный iPhone).
/// Использует боковую панель навигации (Sidebar) с разделами («Снимки», «Камера», «Сессии»),
/// кнопкой «Настройки» внизу боковой панели и полноразмерной полосой прогресса внизу рабочей зоны.
public struct WideAppShellView: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // 1. Боковая панель навигации (Sidebar с поддержкой сворачивания)
            if !appState.isSidebarCollapsed {
                sidebar
                    .frame(width: 230)
                    .background(AppTheme.Colors.surfacePrimary.opacity(0.85))
                    .overlay(
                        Rectangle()
                            .fill(AppTheme.Colors.borderSubtle)
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
                case .sessions:
                    if AppFeatures.sessionManagementEnabled { SessionsSectionView(appState: appState) } else { NikonTetherRootView(appState: appState) }
                }
                
                // 3. Полноразмерная полоса прогресса передачи внизу экрана (референс iPad)
                if let activeJob = appState.activeTransferJob {
                    TransferProgressStrip(
                        filename: activeJob.filename,
                        transferredBytes: activeJob.transferredBytes,
                        totalBytes: activeJob.totalBytes,
                        speedMBs: appState.currentTransferSpeedMBs,
                        isUSB: activeJob.source.transportType == .usb,
                        onTap: {
                            appState.isQueuePresented = true
                        },
                        onCancel: {
                            appState.cancelJob(id: activeJob.id)
                        }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.xs)
                } else if appState.activeQueueCount > 0 {
                    TransferProgressStrip(
                        completedCount: appState.completedJobs.count,
                        totalCount: appState.completedJobs.count + appState.activeQueueCount,
                        label: "Загружено \(appState.completedJobs.count) из \(appState.completedJobs.count + appState.activeQueueCount)",
                        actionTitle: "Очередь",
                        onTap: {
                            appState.isQueuePresented = true
                        }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Боковая панель
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Заголовок приложения в точности как на референсе iPad
            HStack(spacing: AppTheme.Spacing.xs + 2) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.Colors.accent)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nikon Z Bridge")
                        .font(AppTheme.Typography.headline.weight(.heavy))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Text("Liquid Glass")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        appState.toggleSidebar()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Свернуть боковую панель")
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.lg)
            
            Divider()
                .padding(.horizontal, AppTheme.Spacing.md)
            
            // Список разделов
            VStack(spacing: AppTheme.Spacing.xs) {
                ForEach(AppSection.visibleCases) { section in
                    sidebarItem(for: section)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            
            Spacer()
            
            Divider()
                .padding(.horizontal, AppTheme.Spacing.md)
            
            // Кнопка «Настройки» внизу боковой панели (min 44 pt)
            Button {
                appState.isSettingsPresented = true
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "gearshape")
                        .font(.body)
                    
                    Text("Настройки")
                        .font(AppTheme.Typography.subheadlineBold)
                    
                    Spacer()
                }
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }
    
    private func sidebarItem(for section: AppSection) -> some View {
        let isSelected = appState.selectedSection == section
        
        return Button {
            if appState.selectedSection != section {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    appState.selectedSection = section
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: isSelected ? section.selectedIconName : section.iconName)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .frame(width: 24, height: 24)
                
                Text(section.rawValue)
                    .font(AppTheme.Typography.subheadlineBold)
                
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.white : AppTheme.Colors.textPrimary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
            .background(
                Group {
                    if isSelected {
                        AppTheme.Colors.accent
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                            .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 6, x: 0, y: 2)
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    // MARK: - Свернутая панель навигации (быстрый доступ и раскрытие)
    
    private var collapsedSidebarRail: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    appState.toggleSidebar()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                    .glassSurface(shape: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Развернуть боковую панель")
            .padding(.top, AppTheme.Spacing.lg)
            
            Divider()
                .padding(.horizontal, AppTheme.Spacing.xs)
            
            // Быстрые иконки разделов
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(AppSection.visibleCases) { section in
                    let isSelected = appState.selectedSection == section
                    Button {
                        if appState.selectedSection != section {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                appState.selectedSection = section
                            }
                        }
                    } label: {
                        Image(systemName: isSelected ? section.selectedIconName : section.iconName)
                            .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.white : AppTheme.Colors.textSecondary)
                            .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            .background(
                                Group {
                                    if isSelected {
                                        AppTheme.Colors.accent
                                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            
            Spacer()
            
            // Кнопка «Настройки»
            Button {
                appState.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Настройки")
            .padding(.bottom, AppTheme.Spacing.md)
        }
        .frame(width: 56)
        .background(AppTheme.Colors.surfacePrimary.opacity(0.85))
        .overlay(
            Rectangle()
                .fill(AppTheme.Colors.borderSubtle)
                .frame(width: 1),
            alignment: .trailing
        )
        .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
    }
}
