import SwiftUI

/// Узкая компоновка адаптивного каркаса Liquid Glass (iPhone, узкий Split View на iPad).
/// Использует нижнюю плавающую панель навигации (Dock), плашку активной передачи
/// и сохраняет доступ ко всем 3 разделам («Снимки», «Камера», «Сессии») и настройкам.
public struct NarrowAppShellView: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Основная область активного раздела
            VStack(spacing: 0) {
                switch appState.selectedSection {
                case .photos:
                    NikonTetherRootView(appState: appState)
                case .camera:
                    CameraSectionView(appState: appState)
                case .sessions:
                    SessionsSectionView(appState: appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 2. Плавающий нижний блок (плашка передачи + нижний док навигации)
            VStack(spacing: AppTheme.Spacing.xs) {
                // Плашка активной передачи файла или суммарной очереди
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
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                } else if appState.activeQueueCount > 0 {
                    TransferProgressStrip(
                        completedCount: appState.completedJobs.count,
                        totalCount: appState.completedJobs.count + appState.activeQueueCount,
                        label: "\(appState.completedJobs.count) из \(appState.completedJobs.count + appState.activeQueueCount)",
                        onTap: {
                            appState.isQueuePresented = true
                        }
                    )
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                }
                
                // Нижняя плавающая панель навигации Liquid Glass
                bottomFloatingDock
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
    }
    
    // MARK: - Нижняя плавающая панель навигации
    
    private var bottomFloatingDock: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(AppSection.allCases) { section in
                tabButton(for: section)
            }
        }
        .padding(AppTheme.Spacing.xs)
        .glassPill(shadowRadius: 10, shadowY: 4)
    }
    
    private func tabButton(for section: AppSection) -> some View {
        let isSelected = appState.selectedSection == section
        
        return Button {
            if appState.selectedSection != section {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    appState.selectedSection = section
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: isSelected ? section.selectedIconName : section.iconName)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                
                Text(section.rawValue)
                    .font(AppTheme.Typography.captionBold)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : AppTheme.Colors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        AppTheme.Colors.accent
                            .clipShape(Capsule())
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
}
