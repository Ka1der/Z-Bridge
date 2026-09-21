import SwiftUI

/// Экран раздела «Сессии» в адаптивном каркасе Liquid Glass.
/// Позволяет просматривать текущую активную съемку, историю всех фотосессий,
/// создавать новые сессии, переключаться между ними и экспортировать данные.
public struct SessionsSectionView: View {
    @ObservedObject var appState: AppState
    
    @State private var isShowingNewSessionAlert = false
    @State private var newSessionName = ""
    @State private var isShowingRenameAlert = false
    @State private var renamingSession: CaptureSession?
    @State private var renameSessionText = ""
    @State private var sessionToDelete: CaptureSession?
    @State private var isShowingDeleteAlert = false
    @State private var deleteStats: SessionStats?
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 1. Верхний заголовок и кнопка создания
                headerCard
                
                // 2. Карточка текущей активной сессии
                if let active = appState.currentSession {
                    activeSessionCard(active)
                }
                
                // 3. Список предыдущих сессий
                sessionsListSection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background)
        .alert("Новая фотосессия", isPresented: $isShowingNewSessionAlert) {
            TextField("Название съемки", text: $newSessionName)
            Button("Создать") {
                let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.startNewSession(named: name.isEmpty ? nil : name)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет создана отдельная папка для входящих снимков. Существующие фотографии останутся в своих сессиях.")
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
            Text("Будет безвозвратно удалено \(files) файлов (\(size)). Это действие необратимо.")
        }
        .alert("Ошибка", isPresented: $isShowingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }
    
    // MARK: - 1. Верхний заголовок и кнопка новой сессии
    
    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text("Фотосессии")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text("Всего съемок: \(appState.availableSessions.count)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button {
                newSessionName = ""
                isShowingNewSessionAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Новая съемка")
                }
            }
            .buttonStyle(.appPrimary)
        }
    }
    
    // MARK: - 2. Карточка активной сессии
    
    private func activeSessionCard(_ session: CaptureSession) -> some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    HStack(spacing: AppTheme.Spacing.xs + 2) {
                        Circle()
                            .fill(AppTheme.Colors.statusGreen)
                            .frame(width: 8, height: 8)
                        
                        Text("АКТИВНАЯ СЪЕМКА")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    }
                    
                    Spacer()
                    
                    Button {
                        appState.presentExportForSession()
                    } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up")
                            .font(AppTheme.Typography.captionBold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Colors.accent)
                }
                
                Text(session.name)
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: AppTheme.Spacing.lg) {
                    Label("\(appState.captureGroups.count) кадров", systemImage: "photo.stack")
                    Label("\(appState.receivedFiles.count) файлов", systemImage: "doc")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: appState.totalBytesTransferred, countStyle: .file))
                        .font(AppTheme.Typography.captionBold)
                        .monospacedDigit()
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 3. Список съемок в истории
    
    private var sessionsListSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("История съемок")
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.xs)
            
            if appState.availableSessions.isEmpty {
                GlassCard(cornerRadius: AppTheme.Radius.md) {
                    Text("История съемок пуста")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(AppTheme.Spacing.xl)
                }
            } else {
                ForEach(appState.availableSessions) { session in
                    sessionItemCard(session)
                }
            }
        }
    }
    
    private func sessionItemCard(_ session: CaptureSession) -> some View {
        let isActive = session.id == appState.currentSession?.id
        
        return GlassCard(cornerRadius: AppTheme.Radius.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(session.name)
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        if isActive {
                            Text("Активна")
                                .font(AppTheme.Typography.caption2Bold)
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.Colors.statusGreen.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(session.createdAt, style: .date)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                if !isActive {
                    Button("Выбрать") {
                        appState.switchSession(to: session.id)
                    }
                    .buttonStyle(.appSecondaryGlass)
                }
                
                Menu {
                    Button {
                        renamingSession = session
                        renameSessionText = session.name
                        isShowingRenameAlert = true
                    } label: {
                        Label("Переименовать...", systemImage: "pencil")
                    }
                    
                    if !isActive {
                        Button(role: .destructive) {
                            sessionToDelete = session
                            Task {
                                deleteStats = await appState.fetchSessionStats(for: session.id)
                                isShowingDeleteAlert = true
                            }
                        } label: {
                            Label("Удалить съемку...", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
}
