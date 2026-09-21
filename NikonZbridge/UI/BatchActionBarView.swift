import SwiftUI

/// Плавающая нижняя панель групповых действий при включенном режиме выбора
public struct BatchActionBarView: View {
    @ObservedObject var appState: AppState
    @State private var isShowingDeleteAlert = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                // Счетчик выбранных
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text("\(appState.selectedGroupIDs.count)")
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                .padding(.horizontal, AppTheme.Spacing.sm)
                .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Выбрано кадров: \(appState.selectedGroupIDs.count)")
                
                Divider()
                    .frame(height: 24)
                
                // Кнопка сравнения (доступна строго для 2 выбранных кадров)
                Button {
                    appState.presentCompareForSelected()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.split.2x1")
                        Text("Сравнить")
                            .font(AppTheme.Typography.captionBold)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                    .background(appState.canCompareSelected ? AppTheme.Colors.accent.opacity(0.2) : Color.clear)
                    .foregroundStyle(appState.canCompareSelected ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
                    .clipShape(Capsule())
                }
                .disabled(!appState.canCompareSelected)
                .accessibilityLabel("Сравнить два кадра")
                .accessibilityHint(appState.canCompareSelected ? "Нажмите для сравнения двух выбранных кадров" : "Для сравнения выберите ровно 2 кадра")
                
                Divider()
                    .frame(height: 24)
                
                // Рейтинг для выбранных
                HStack(spacing: 2) {
                    Button("0") {
                        appState.batchSetRating(0)
                    }
                    .font(AppTheme.Typography.captionBold)
                    .frame(width: 36, height: AppTheme.Dimensions.minTouchTarget)
                    .contentShape(Rectangle())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityLabel("Снять рейтинг")
                    
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            appState.batchSetRating(star)
                        } label: {
                            HStack(spacing: 1) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                Text("\(star)")
                                    .font(AppTheme.Typography.caption2Bold)
                            }
                            .foregroundStyle(Color.yellow)
                            .frame(width: 36, height: AppTheme.Dimensions.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Установить рейтинг \(star) звезд")
                    }
                }
                
                Divider()
                    .frame(height: 24)
                
                // Флаги отбора для выбранных
                HStack(spacing: 4) {
                    Button {
                        appState.batchSetPickStatus(.picked)
                    } label: {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                            .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Пометить отобранным (Pick)")
                    
                    Button {
                        appState.batchSetPickStatus(.rejected)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusRed)
                            .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Пометить отклонённым (Reject)")
                    
                    Button {
                        appState.batchSetPickStatus(.unflagged)
                    } label: {
                        Image(systemName: "flag.slash")
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Снять метку отбора")
                }
                
                Divider()
                    .frame(height: 24)
                
                // Выбрать все / Снять
                Button("Все") {
                    appState.selectAll()
                }
                .font(AppTheme.Typography.captionBold)
                .frame(minWidth: AppTheme.Dimensions.minTouchTarget, minHeight: AppTheme.Dimensions.minTouchTarget)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .accessibilityLabel("Выбрать все кадры")
                
                Button("Снять") {
                    appState.clearSelection()
                }
                .font(AppTheme.Typography.caption)
                .frame(minWidth: AppTheme.Dimensions.minTouchTarget, minHeight: AppTheme.Dimensions.minTouchTarget)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .accessibilityLabel("Снять выбор со всех кадров")
                
                Divider()
                    .frame(height: 24)
                
                // Экспорт выбранных
                Button {
                    appState.presentExportForSelected()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Экспорт")
                            .font(AppTheme.Typography.captionBold)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                    .background(AppTheme.Colors.accent)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Экспортировать выбранные кадры")
                
                // Удаление выбранных с однозначной подписью и подтверждением
                Button(role: .destructive) {
                    isShowingDeleteAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Удалить (\(appState.selectedGroupIDs.count))")
                            .font(AppTheme.Typography.captionBold)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: AppTheme.Dimensions.minTouchTarget)
                    .background(AppTheme.Colors.statusRed.opacity(0.18))
                    .foregroundStyle(AppTheme.Colors.statusRed)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Удалить выбранные кадры из сессии")
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 4)
        }
        .glassPill(shadowRadius: 10, shadowY: 4)
        .padding(.horizontal, AppTheme.Spacing.md)
        .alert(
            "Удалить \(appState.selectedGroupIDs.count) выбранных кадр(ов)?",
            isPresented: $isShowingDeleteAlert
        ) {
            Button("Удалить", role: .destructive) {
                appState.batchDeleteSelected()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выбранные кадры будут безвозвратно удалены из текущей фотосессии. Это действие невозможно отменить.")
        }
    }
}
