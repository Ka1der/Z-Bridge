import SwiftUI

/// Плавающая нижняя панель групповых действий при включенном режиме выбора
public struct BatchActionBarView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Счетчик выбранных
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("\(appState.selectedGroupIDs.count)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
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
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(appState.canCompareSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    .foregroundStyle(appState.canCompareSelected ? Color.accentColor : Color.secondary)
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
                    .font(.caption.bold())
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Снять рейтинг")
                    
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            appState.batchSetRating(star)
                        } label: {
                            HStack(spacing: 1) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                Text("\(star)")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(.yellow)
                            .frame(width: 36, height: 44)
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
                            .foregroundStyle(.green)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Пометить отобранным (Pick)")
                    
                    Button {
                        appState.batchSetPickStatus(.rejected)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Пометить отклонённым (Reject)")
                    
                    Button {
                        appState.batchSetPickStatus(.unflagged)
                    } label: {
                        Image(systemName: "flag.slash")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
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
                .font(.caption.bold())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
                .accessibilityLabel("Выбрать все кадры")
                
                Button("Снять") {
                    appState.clearSelection()
                }
                .font(.caption)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(.secondary)
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
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Экспортировать выбранные кадры")
                
                // Удаление выбранных
                Button(role: .destructive) {
                    appState.batchDeleteSelected()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Удалить выбранные кадры из сессии")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
        .overlay(
            Capsule()
                #if canImport(UIKit)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                #else
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                #endif
        )
        .padding(.horizontal, 16)
    }
}
