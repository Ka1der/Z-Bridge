import SwiftUI
import CoreGraphics

/// Экран просмотра оглавления карты памяти подключенной по USB камеры
public struct USBCameraBrowserView: View {
    @ObservedObject var usbManager: USBCameraManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var filterMode: FilterMode = .all
    @State private var selectedFileIDs: Set<String> = []
    
    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "Все"
        case rawOnly = "Только RAW"
        case unimported = "Неимпортированные"
        
        var id: String { rawValue }
    }
    
    public init(usbManager: USBCameraManager = .shared) {
        self.usbManager = usbManager
    }
    
    private var filteredFiles: [CameraFileItem] {
        usbManager.catalogFiles.filter { item in
            switch filterMode {
            case .all:
                return true
            case .rawOnly:
                return item.isRAW
            case .unimported:
                return item.status == .notImported
            }
        }
    }
    
    private var selectedFiles: [CameraFileItem] {
        usbManager.catalogFiles.filter { selectedFileIDs.contains($0.id) }
    }
    
    private var selectedTotalBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.fileSize }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Верхняя информационная панель с режимом импорта
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(usbManager.cameraName ?? "Nikon Z")
                                .font(.headline)
                            Text(usbManager.connectionState.displayTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        if usbManager.isDownloading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                    }
                    
                    Divider()
                    
                    // Выбор режима импорта
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Режим импорта по USB:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Режим импорта", selection: Binding(
                            get: { usbManager.importMode },
                            set: { usbManager.setImportMode($0) }
                        )) {
                            ForEach(USBImportMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(usbManager.importMode.descriptionText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Фильтр отображения файлов
                    HStack {
                        Picker("Фильтр", selection: $filterMode) {
                            ForEach(FilterMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Spacer()
                        
                        // Кнопки быстрого выбора
                        Menu {
                            Button("Выбрать все отфильтрованные") {
                                for f in filteredFiles where f.status == .notImported {
                                    selectedFileIDs.insert(f.id)
                                }
                            }
                            Button("Снять выделение") {
                                selectedFileIDs.removeAll()
                            }
                            Button("Выбрать только неимпортированные RAW") {
                                selectedFileIDs.removeAll()
                                for f in usbManager.catalogFiles where f.isRAW && f.status == .notImported {
                                    selectedFileIDs.insert(f.id)
                                }
                            }
                        } label: {
                            Label("Выбор", systemImage: "checklist")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                
                // Список файлов на карте
                if filteredFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(usbManager.isCatalogReady ? "Файлы не найдены" : "Чтение оглавления карты памяти...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredFiles) { item in
                            HStack(spacing: 12) {
                                // Чекбокс выбора
                                if item.status == .notImported {
                                    Image(systemName: selectedFileIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFileIDs.contains(item.id) ? .accentColor : .secondary)
                                        .font(.title3)
                                        .onTapGesture {
                                            if selectedFileIDs.contains(item.id) {
                                                selectedFileIDs.remove(item.id)
                                            } else {
                                                selectedFileIDs.insert(item.id)
                                            }
                                        }
                                } else {
                                    statusIcon(for: item.status)
                                }
                                
                                // Миниатюра или иконка
                                Group {
                                    if let thumb = item.thumbnail {
                                        Image(decorative: thumb, scale: 1.0)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.2))
                                            .overlay(
                                                Image(systemName: item.isRAW ? "camera.fill" : "photo")
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onAppear {
                                    if item.thumbnail == nil {
                                        usbManager.requestThumbnail(for: item)
                                    }
                                }
                                
                                // Имя и метаданные
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.filename)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        if item.isRAW {
                                            Text("RAW")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.15))
                                                .foregroundColor(.purple)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text(item.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if let date = item.creationDate {
                                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // Бейдж статуса
                                statusBadge(for: item.status)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if item.status == .notImported {
                                    if selectedFileIDs.contains(item.id) {
                                        selectedFileIDs.remove(item.id)
                                    } else {
                                        selectedFileIDs.insert(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                
                // Нижняя панель действий
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Выбрано: \(selectedFileIDs.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if selectedTotalBytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: selectedTotalBytes, countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            let toImport = selectedFiles
                            Task {
                                await usbManager.importSelectedFiles(toImport)
                                selectedFileIDs.removeAll()
                            }
                        } label: {
                            Label("Импортировать (\(selectedFileIDs.count))", systemImage: "arrow.down.circle.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFileIDs.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(UIColor.secondarySystemBackground))
            }
            .navigationTitle("Карта памяти камеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func statusIcon(for status: CameraFileImportStatus) -> some View {
        switch status {
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        case .queued, .importing:
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 22, height: 22)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.title3)
        case .notImported:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func statusBadge(for status: CameraFileImportStatus) -> some View {
        switch status {
        case .imported:
            Text("Сохранен")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .clipShape(Capsule())
        case .queued:
            Text("В очереди")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .clipShape(Capsule())
        case .importing(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .clipShape(Capsule())
        case .failed:
            Text("Сбой")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundColor(.red)
                .clipShape(Capsule())
        case .notImported:
            EmptyView()
        }
    }
}
