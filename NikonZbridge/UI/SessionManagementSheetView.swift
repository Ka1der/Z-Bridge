import SwiftUI

/// Модальное окно управления фотосессиями: история съемок, статистика, создание, переключение и безопасное удаление
public struct SessionManagementSheetView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var isShowingNewSessionAlert = false
    @State private var newSessionName = ""
    
    @State private var isShowingRenameAlert = false
    @State private var renamingSession: CaptureSession?
    @State private var renameSessionText = ""
    
    @State private var sessionToDelete: CaptureSession?
    @State private var deleteStats: SessionStats?
    @State private var isShowingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // 1. Активная сессия
                Section("Текущая активная съемка") {
                    if let active = appState.currentSession {
                        activeSessionRow(active)
                    } else {
                        Text("Нет активной сессии")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 2. История всех съемок
                Section("Предыдущие съемки (\(appState.availableSessions.count))") {
                    if appState.availableSessions.isEmpty {
                        Text("История съемок пуста")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.availableSessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
            .navigationTitle("Управление съемками")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        newSessionName = ""
                        isShowingNewSessionAlert = true
                    } label: {
                        Label("Новая съемка", systemImage: "plus.circle.fill")
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        newSessionName = ""
                        isShowingNewSessionAlert = true
                    } label: {
                        Label("Новая съемка", systemImage: "plus.circle.fill")
                    }
                }
                #endif
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .alert("Новая фотосессия", isPresented: $isShowingNewSessionAlert) {
                TextField("Название (например: Студия_Портрет)", text: $newSessionName)
                Button("Создать") {
                    let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.startNewSession(named: name.isEmpty ? nil : name)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Будет создана новая папка для входящих снимков. Ранее сохраненные фотографии останутся в своих папках.")
            }
            .alert("Переименовать съемку", isPresented: $isShowingRenameAlert) {
                TextField("Новое имя", text: $renameSessionText)
                Button("Сохранить") {
                    if let s = renamingSession {
                        let name = renameSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            appState.renameSession(id: s.id, newName: name)
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .alert(
                "Удалить съемку «\(sessionToDelete?.name ?? "")»?",
                isPresented: $isShowingDeleteAlert,
                presenting: sessionToDelete
            ) { session in
                Button("Удалить навсегда", role: .destructive) {
                    appState.deleteSession(id: session.id) { error in
                        if let err = error {
                            self.errorMessage = err
                            self.isShowingErrorAlert = true
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: { session in
                let files = deleteStats?.filesCount ?? 0
                let size = deleteStats?.formattedSize ?? "0 МБ"
                Text("Будет безвозвратно удалено \(files) файлов общим объемом \(size). Это действие необратимо и удалит файлы с диска.")
            }
            .alert("Ошибка", isPresented: $isShowingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
            .task {
                await appState.reloadSessions()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Активная строка сессии
    
    private func activeSessionRow(_ session: CaptureSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.name)
                    .font(.headline.monospaced())
                Spacer()
                Text("АКТИВНАЯ")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 12) {
                Label("\(appState.captureGroups.count) кадров", systemImage: "photo.stack")
                Label("\(appState.receivedFiles.count) файлов", systemImage: "doc")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: appState.totalBytesTransferred, countStyle: .file))
                    .font(.subheadline.bold())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Строка сессии в истории
    
    private func sessionRow(_ session: CaptureSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.body.weight(.semibold))
                    if session.id == appState.currentSession?.id {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                    if session.isClosed {
                        Text("Завершена")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                Text(session.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Menu {
                if session.id != appState.currentSession?.id {
                    Button {
                        appState.switchSession(to: session.id)
                    } label: {
                        Label("Сделать активной", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                
                Button {
                    renamingSession = session
                    renameSessionText = session.name
                    isShowingRenameAlert = true
                } label: {
                    Label("Переименовать", systemImage: "pencil")
                }
                
                if !session.isClosed {
                    Button {
                        appState.closeSession(id: session.id)
                    } label: {
                        Label("Завершить съемку", systemImage: "lock")
                    }
                }
                
                Divider()
                
                Button(role: .destructive) {
                    sessionToDelete = session
                    Task {
                        self.deleteStats = await appState.fetchSessionStats(for: session.id)
                        self.isShowingDeleteAlert = true
                    }
                } label: {
                    Label("Удалить файлы сессии", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .padding(.vertical, 2)
    }
}
