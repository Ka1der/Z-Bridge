import SwiftUI

/// Интерактивный экран таблицы совместимости камер линейки Nikon Z
public struct CompatibilityMatrixView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    
    public init() {}
    
    private var filteredModels: [NikonCameraModel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NikonCameraModel.allCases
        }
        let query = trimmed.lowercased()
        let compactQuery = query.replacingOccurrences(of: " ", with: "")
        
        return NikonCameraModel.allCases.filter { model in
            let name = model.fullName.lowercased()
            let raw = model.rawValue.lowercased().replacingOccurrences(of: " ", with: "")
            let proc = model.processor.rawValue.lowercased()
            let sensor = model.sensorDescription.lowercased()
            
            return name.contains(query) ||
                raw.contains(compactQuery) ||
                proc.contains(query) ||
                sensor.contains(query)
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Список камер без задвоений
                List {
                    ForEach(filteredModels) { model in
                        cameraCard(model)
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
    
    private func cameraCard(_ model: NikonCameraModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок камеры
            HStack(spacing: 8) {
                Text(model.fullName)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                
                Text(model.processor.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                
                Text(model.sensorDescription)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.blue)
                
                Spacer()
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Способы подключения
            VStack(alignment: .leading, spacing: 10) {
                Text("Способы подключения:")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                
                // 1. Кабель
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .frame(width: 22)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cableTitle(for: model))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text(cableSubtitle(for: model))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 2. Wi-Fi
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wifi")
                        .foregroundStyle(.cyan)
                        .font(.subheadline)
                        .frame(width: 22)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Встроенный Wi-Fi (FTP)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Диапазоны: \(model.wifiBands.joined(separator: ", ")) · Прямое подключение к iPad/Mac или через общий роутер")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 3. Ethernet (проводная сеть)
                if let eth = ethernetInfo(for: model) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "network")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                            .frame(width: 22)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eth.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text(eth.details)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Чипы возможностей
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chipView(icon: "bolt.horizontal.fill", text: "Автоотправка при съёмке")
                    chipView(icon: "square.stack.3d.forward.dottedline", text: "Связывание RAW + JPEG")
                    chipView(icon: "sdcard", text: "Просмотр и выборка с карты памяти")
                    chipView(icon: "arrow.down.to.line", text: "Потоковый приём по FTP")
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    private func chipView(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.15))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }
    
    private func cableTitle(for model: NikonCameraModel) -> String {
        switch model {
        case .z50:
            return "Кабель Micro-USB (PTP)"
        case .z8:
            return "Двойной порт USB-C (PTP / Питание)"
        default:
            return "Прямой кабель USB-C (PTP)"
        }
    }
    
    private func cableSubtitle(for model: NikonCameraModel) -> String {
        switch model {
        case .z50:
            return "Разъем Micro-B. Автоматический импорт новых кадров и просмотр карты памяти."
        case .z8:
            return "Верхний порт: передача данных SuperSpeed 3.2. Нижний порт: независимое питание USB-PD."
        default:
            return "SuperSpeed USB 3.2. Мгновенное обнаружение, чтение карты памяти и импорт без задержек."
        }
    }
    
    private func ethernetInfo(for model: NikonCameraModel) -> (title: String, details: String)? {
        if model.hasBuiltInRJ45 {
            return (
                title: "Встроенный Ethernet 1000BASE-T (RJ-45)",
                details: "Аппаратный порт RJ-45 в корпусе. Скорость до 110 МБ/с, максимальная надёжность передачи по FTP."
            )
        } else if model.supportedTransports.contains(.usbToEthernet) {
            return (
                title: "Адаптер USB-C ➔ Ethernet (FTP)",
                details: "Подключение гигабитного адаптера USB-LAN в порт данных. Проводная сеть без встроенного RJ-45."
            )
        } else if model.supportedTransports.contains(.wt7Transmitter) {
            return (
                title: "Передатчик WT-7 (Ethernet / Wi-Fi)",
                details: "Внешний беспроводной модуль с аппаратным разъемом LAN и антеннами повышенной дальности."
            )
        }
        return nil
    }
}
