//
//  XMPCompatibilityGuideView.swift
//  NikonZbridge
//
//  Created by Antigravity on 2026-09-18.
//

import SwiftUI

/// Экран справочника совместимости XMP метаданных с фоторедакторами
public struct XMPCompatibilityGuideView: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Важные правила и принципы
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Неизменность RAW-оригиналов", systemImage: "lock.shield.fill")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                        
                        Text("Z-Bridge гарантирует 100% неприкосновенность оригинальных файлов (NEF, JPG, HEIF). Все оценки, отметки и метаданные записываются исключительно в сопутствующие файлы XMP sidecar.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ограничения Lightroom Classic", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Text("Флаг «Выбран» (Pick) в Adobe Lightroom хранится исключительно внутри каталога (.lrcat) и не имеет стандарта в XMP спецификации Adobe. Для совместимости мы транслируем Pick в xmp:Label=\"Pick\" и photoshop:Urgency=\"1\". В Lightroom используйте фильтр по метке «Pick».")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Принципы экспорта метаданных")
                }
                
                // MARK: - Список целевых редакторов
                Section {
                    ForEach(XMPCompatibilityGuide.allEditors) { editor in
                        EditorCompatibilityRow(editor: editor)
                    }
                } header: {
                    Text("Совместимость с редакторами")
                } footer: {
                    Text("Для синхронизации в Lightroom нажмите «Metadata > Read Metadata from Files». В Capture One включите «Auto Sync Sidecar XMP».")
                }
                
                // MARK: - Соглашения об именовании
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Стандартное (DSC_0001.xmp)")
                            .font(.subheadline).bold()
                        Text("Рекомендуется для Adobe Lightroom Classic, Camera Raw, Photoshop, Bridge и Capture One Pro. Одно общее имя для базового кадра.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Полное имя (DSC_0001.NEF.xmp)")
                            .font(.subheadline).bold()
                        Text("Рекомендуется для darktable и RawTherapee. Позволяет раздельно хранить метаданные для NEF и JPG файлов одной серии.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Соглашения об именовании XMP")
                }
            }
            .navigationTitle("Совместимость XMP")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Строка редактора

private struct EditorCompatibilityRow: View {
    let editor: EditorCompatibilityInfo
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName(for: editor.target))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                Text(editor.name)
                    .font(.headline)
                
                Spacer()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 12) {
                StatusTag(title: "Рейтинг", isSupported: editor.ratingSupported)
                StatusTag(title: "Pick/Reject", isSupported: editor.pickSupported || editor.rejectSupported)
                StatusTag(title: "Автор/Копирайт", isSupported: editor.metadataSupported)
            }
            
            if isExpanded {
                Divider().padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    DetailLine(label: "Рейтинг (0–5★):", value: editor.ratingNotes)
                    DetailLine(label: "Pick (Выбран):", value: editor.pickNotes)
                    DetailLine(label: "Reject (Отклонен):", value: editor.rejectNotes)
                    DetailLine(label: "Имя файла:", value: editor.recommendedNaming.displayName)
                    
                    if let tip = editor.workflowTip {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(tip)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconName(for target: TargetEditor) -> String {
        switch target {
        case .lightroomClassic: return "photo.stack"
        case .adobeCameraRaw: return "slider.horizontal.3"
        case .adobeBridge: return "folder.badge.gearshape"
        case .captureOne: return "camera.filters"
        case .photoMechanic: return "bolt.shield"
        case .darktable: return "moon.circle"
        case .rawTherapee: return "sparkles"
        case .applePhotos: return "photo.on.rectangle.angled"
        }
    }
}

// MARK: - Вспомогательные элементы

private struct StatusTag: View {
    let title: String
    let isSupported: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isSupported ? .green : .orange)
                .font(.caption2)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct DetailLine: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.caption).bold()
                .foregroundColor(.primary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
