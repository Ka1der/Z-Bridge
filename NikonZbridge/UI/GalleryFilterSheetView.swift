import SwiftUI

/// Панель фильтрации и сортировки снимков галереи
public struct GalleryFilterSheetView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // 1. Форматы файлов
                Section {
                    Toggle(isOn: Binding(
                        get: { appState.showRAW },
                        set: { _ in appState.toggleRAW() }
                    )) {
                        HStack {
                            Label("RAW", systemImage: "camera.macro")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(appState.rawCount)")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                    
                    Toggle(isOn: Binding(
                        get: { appState.showJPG },
                        set: { _ in appState.toggleJPG() }
                    )) {
                        HStack {
                            Label("JPG", systemImage: "photo")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(appState.jpgCount)")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                    
                    if appState.heifCount > 0 {
                        Toggle(isOn: Binding(
                            get: { appState.showHEIF },
                            set: { _ in appState.toggleHEIF() }
                        )) {
                            HStack {
                                Label("HEIF / HIF", systemImage: "photo.stack")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(appState.heifCount)")
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    
                    if appState.pairedCount > 0 {
                        Toggle(isOn: Binding(
                            get: { appState.onlyPaired },
                            set: { _ in appState.toggleOnlyPaired() }
                        )) {
                            HStack {
                                Label(tr("Только пары RAW+JPG", "RAW+JPG pairs only"), systemImage: "link")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(appState.pairedCount)")
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text(tr("Формат снимков", "Image Format"))
                }
                
                // 2. Сортировка
                Section {
                    Picker(tr("Порядок", "Order"), selection: Binding(
                        get: { appState.sortOrder },
                        set: { appState.setSortOrder($0) }
                    )) {
                        ForEach(SortOrderOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                } header: {
                    Text(tr("Сортировка", "Sorting"))
                }
                
                // 3. Рейтинг
                Section {
                    Picker(tr("Рейтинг", "Rating"), selection: Binding(
                        get: { appState.ratingFilter },
                        set: { appState.setRatingFilter($0) }
                    )) {
                        ForEach(RatingFilterOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                } header: {
                    Text(tr("Рейтинг", "Rating"))
                }
                
                // 4. Флаг отбора
                Section {
                    Picker(tr("Отбор", "Flag"), selection: Binding(
                        get: { appState.pickFilter },
                        set: { appState.setPickFilter($0) }
                    )) {
                        ForEach(PickFilterOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                } header: {
                    Text(tr("Метка отбора", "Pick Flag"))
                }
            }
            .navigationTitle(appState.activeFilterCount > 0 ? tr("Фильтры (\(appState.activeFilterCount))", "Filters (\(appState.activeFilterCount))") : tr("Фильтры", "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Сбросить", "Reset")) {
                        appState.resetFilters()
                    }
                    .disabled(!appState.hasActiveFilters)
                    .accessibilityHint(tr("Сбросить все фильтры к исходным значениям", "Reset all filters to default values"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Готово", "Done")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
