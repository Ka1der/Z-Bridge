import SwiftUI

/// Интерактивный экран таблицы аппаратной совместимости Nikon Z
public struct CompatibilityMatrixView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedStatusFilter: StatusFilter = .all
    @State private var searchText: String = ""
    @State private var expandedRecordID: UUID?
    
    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "Все"
        case verified = "В железе"
        case protocolCompliant = "Протокол"
        case untested = "Не проверено"
        
        var id: String { rawValue }
    }
    
    public init() {}
    
    private var filteredRecords: [CompatibilityRecord] {
        let all = NikonCompatibilityMatrix.shared.allRecords
        return all.filter { record in
            let matchesSearch = searchText.isEmpty ||
                record.model.fullName.localizedCaseInsensitiveContains(searchText) ||
                record.transport.title.localizedCaseInsensitiveContains(searchText) ||
                record.notes.localizedCaseInsensitiveContains(searchText)
            
            let matchesFilter: Bool
            switch selectedStatusFilter {
            case .all:
                matchesFilter = true
            case .verified:
                matchesFilter = record.verificationStatus == .verified
            case .protocolCompliant:
                matchesFilter = record.verificationStatus == .protocolCompliant
            case .untested:
                matchesFilter = record.verificationStatus == .untested
            }
            
            return matchesSearch && matchesFilter
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Предупреждающий баннер честности спецификации
                untestedNoticeBanner
                    .padding()
                
                // Фильтры
                Picker("Фильтр", selection: $selectedStatusFilter) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Список записей совместимости
                List {
                    ForEach(filteredRecords) { record in
                        compatibilityCard(record)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Поиск модели (например Z8, Z9, Z50)")
            }
            .background(Color.black.opacity(0.96))
            .navigationTitle("Таблица совместимости")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
    
    private var untestedNoticeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("ПРИНЦИП АППАРАТНОЙ ЧЕСТНОСТИ")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Все сочетания камер и интерфейсов, не прошедшие физическое тестирование на стенде, помечены как «Не проверено в железе». Мы не даем ложных гарантий совместимости.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func compatibilityCard(_ record: CompatibilityRecord) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(record.model.fullName)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                        
                        Text(record.model.processor.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Text(record.transport.title)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                
                Spacer()
                
                // Бейдж статуса проверки
                statusBadge(record.verificationStatus)
            }
            
            HStack(spacing: 8) {
                Text("Прошивки: \(record.firmwareVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
                
                Text("Источник: \(record.infoSource.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Чипы возможностей
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(record.capabilities) { cap in
                        HStack(spacing: 4) {
                            Image(systemName: cap.icon)
                                .font(.caption2)
                            Text(cap.rawValue)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                }
            }
            
            // Примечания и особенности
            if !record.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Примечания:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(record.notes)
                        .font(.caption)
                        .foregroundStyle(record.verificationStatus == .untested ? .orange : .white.opacity(0.85))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(record.verificationStatus == .untested ? Color.orange.opacity(0.1) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(badgeBorderColor(record.verificationStatus), lineWidth: 1)
        )
    }
    
    private func statusBadge(_ status: HardwareVerificationStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeBackgroundColor(status))
        .foregroundStyle(badgeForegroundColor(status))
        .clipShape(Capsule())
    }
    
    private func badgeBackgroundColor(_ status: HardwareVerificationStatus) -> Color {
        switch status {
        case .verified: return Color.green.opacity(0.2)
        case .protocolCompliant: return Color.yellow.opacity(0.2)
        case .untested: return Color.orange.opacity(0.2)
        }
    }
    
    private func badgeForegroundColor(_ status: HardwareVerificationStatus) -> Color {
        switch status {
        case .verified: return Color.green
        case .protocolCompliant: return Color.yellow
        case .untested: return Color.orange
        }
    }
    
    private func badgeBorderColor(_ status: HardwareVerificationStatus) -> Color {
        switch status {
        case .verified: return Color.green.opacity(0.3)
        case .protocolCompliant: return Color.yellow.opacity(0.3)
        case .untested: return Color.orange.opacity(0.5)
        }
    }
}
