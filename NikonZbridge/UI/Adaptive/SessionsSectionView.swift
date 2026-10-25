import SwiftUI

/// Экран раздела «Сессии» в адаптивном каркасе Liquid Glass.
/// Позволяет просматривать текущую активную съемку, историю всех фотосессий,
/// создавать новые сессии, редактировать метаданные, переключаться между ними
/// и экспортировать данные с полной гарантией сохранности оригиналов.
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
    
    // Кэш статистики съемок для быстрого отображения количества кадров в истории
    @State private var sessionStatsCache: [UUID: SessionStats] = [:]
    
    // Лист редактирования метаданных
    @State private var editingMetadataSession: CaptureSession?
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 1. Верхний заголовок и кнопка создания новой съемки
                headerCard
                
                // 2. Карточка текущей активной съемки
                if let active = appState.currentSession {
                    activeSessionCard(active)
                }
                
                // 3. Настройка режима запуска (пустая сессия vs продолжение последней)
                startupPreferenceCard
                
                // 4. Список истории съемок с датой и количеством кадров
                sessionsListSection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background)
        .task(id: appState.availableSessions) {
            await reloadAllSessionStats()
        }
        .onAppear {
            Task {
                await reloadAllSessionStats()
            }
        }
        // Модальное окно создания новой фотосессии
        .alert(tr("Новая фотосессия", "New Photoshoot"), isPresented: $isShowingNewSessionAlert) {
            TextField(tr("Название съемки", "Shoot Name"), text: $newSessionName)
            Button(tr("Создать", "Create")) {
                let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.startNewSession(named: name.isEmpty ? nil : name)
            }
            Button(tr("Отмена", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Будет создана отдельная папка для входящих снимков. Существующие фотографии останутся в своих папках без изменений.", "A dedicated folder will be created for incoming shots. Existing photos remain untouched in their folders."))
        }
        // Модальное окно переименования
        .alert(tr("Переименовать съемку", "Rename Shoot"), isPresented: $isShowingRenameAlert) {
            TextField(tr("Новое имя", "New Name"), text: $renameSessionText)
            Button(tr("Сохранить", "Save")) {
                if let s = renamingSession {
                    let name = renameSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        appState.renameSession(id: s.id, newName: name)
                    }
                }
            }
            Button(tr("Отмена", "Cancel"), role: .cancel) {}
        }
        // Диалог безвозвратного удаления сессии (Опасная зона)
        .alert(
            tr("Удалить съемку «\(sessionToDelete?.name ?? "")»?", "Delete shoot «\(sessionToDelete?.name ?? "")»?"),
            isPresented: $isShowingDeleteAlert,
            presenting: sessionToDelete
        ) { session in
            Button(tr("Удалить навсегда", "Delete Permanently"), role: .destructive) {
                appState.deleteSession(id: session.id) { error in
                    if let err = error {
                        self.errorMessage = err
                        self.isShowingErrorAlert = true
                    }
                }
            }
            Button(tr("Отмена", "Cancel"), role: .cancel) {}
        } message: { session in
            let files = deleteStats?.filesCount ?? 0
            let size = deleteStats?.formattedSize ?? "0 МБ"
            Text(tr("Будет безвозвратно удалено \(files) файлов (\(size)). Файлы будут удалены с диска устройства. Действие необратимо.", "\(files) files (\(size)) will be permanently deleted from the device disk. This action cannot be undone."))
        }
        .alert(tr("Ошибка", "Error"), isPresented: $isShowingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? tr("Неизвестная ошибка", "Unknown error"))
        }
        .sheet(item: $editingMetadataSession) { session in
            SessionMetadataSheetView(session: session, appState: appState)
        }
    }
    
    // MARK: - 1. Верхний заголовок и кнопка новой сессии
    
    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(tr("Фотосессии", "Photoshoots"))
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text(tr("Всего в каталоге: \(appState.availableSessions.count)", "Total in catalog: \(appState.availableSessions.count)"))
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
                    Text(tr("Новая съемка", "New Shoot"))
                }
            }
            .buttonStyle(.appPrimary)
            .accessibilityLabel(tr("Создать новую съемку", "Create new photoshoot"))
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
                        
                        Text(tr("АКТИВНАЯ СЪЕМКА", "ACTIVE SHOOT"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Button {
                            editingMetadataSession = session
                        } label: {
                            Label(tr("Метаданные", "Metadata"), systemImage: "pencil.and.list.clipboard")
                                .font(AppTheme.Typography.captionBold)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Colors.accent)
                        
                        Button {
                            appState.presentExportForSession()
                        } label: {
                            Label(tr("Экспорт", "Export"), systemImage: "square.and.arrow.up")
                                .font(AppTheme.Typography.captionBold)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name)
                        .font(AppTheme.Typography.title3)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    // Краткая сводка метаданных если заполнены
                    if !appState.sessionAuthor.isEmpty || !appState.sessionCopyright.isEmpty {
                        HStack(spacing: 8) {
                            if !appState.sessionAuthor.isEmpty {
                                Label(appState.sessionAuthor, systemImage: "person.crop.circle")
                            }
                            if !appState.sessionCopyright.isEmpty {
                                Label(appState.sessionCopyright, systemImage: "c.circle")
                            }
                        }
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                }
                
                HStack(spacing: AppTheme.Spacing.lg) {
                    Label(tr("\(appState.captureGroups.count) кадров", "\(appState.captureGroups.count) frames"), systemImage: "photo.stack")
                    Label(tr("\(appState.receivedFiles.count) файлов", "\(appState.receivedFiles.count) files"), systemImage: "doc")
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
    
    // MARK: - 3. Настройка режима запуска сессий
    
    private var startupPreferenceCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Toggle(
                    tr("Продолжать последнюю сессию при запуске", "Resume last session on launch"),
                    isOn: $appState.resumeLastSessionOnLaunch
                )
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .tint(AppTheme.Colors.accent)
                
                Text(tr("По умолчанию выключено: приложение начинает работу с новой чистой сессии. Если включено, при старте автоматически открывается последняя активная съемка. Снимки прошлых сессий сохраняются в истории.", "Disabled by default: the app starts with a fresh empty session. When enabled, the last active session opens automatically on startup. Past shots remain safely archived."))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 4. Список съемок в истории
    
    private var sessionsListSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(tr("История съемок", "Shoot History"))
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                    Text(tr("Оригиналы защищены", "Originals Protected"))
                }
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(AppTheme.Colors.statusGreen)
            }
            .padding(.horizontal, AppTheme.Spacing.xs)
            
            if appState.availableSessions.isEmpty {
                GlassCard(cornerRadius: AppTheme.Radius.md) {
                    Text(tr("История съемок пуста", "Shoot history is empty"))
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
        let stats = sessionStatsCache[session.id]
        let framesCount = isActive ? appState.captureGroups.count : (stats?.framesCount ?? 0)
        let formattedSize = isActive
            ? ByteCountFormatter.string(fromByteCount: appState.totalBytesTransferred, countStyle: .file)
            : (stats?.formattedSize ?? "")
        
        return GlassCard(cornerRadius: AppTheme.Radius.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(session.name)
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        if isActive {
                            Text(tr("Активна", "Active"))
                                .font(AppTheme.Typography.caption2Bold)
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.Colors.statusGreen.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text(session.createdAt, style: .date)
                        Text("•")
                        Text("\(framesCount) \(framesWord(for: framesCount))")
                        if !formattedSize.isEmpty && formattedSize != "0 байт" && formattedSize != "Zero KB" {
                            Text("•")
                            Text(formattedSize)
                        }
                    }
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                if !isActive {
                    Button(tr("Выбрать", "Select")) {
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
                        Label(tr("Переименовать...", "Rename..."), systemImage: "pencil")
                    }
                    
                    Button {
                        editingMetadataSession = session
                    } label: {
                        Label(tr("Метаданные...", "Metadata..."), systemImage: "pencil.and.list.clipboard")
                    }
                    
                    Button {
                        appState.switchAndExportSession(session)
                    } label: {
                        Label(tr("Экспорт сессии...", "Export Shoot..."), systemImage: "square.and.arrow.up")
                    }
                    
                    if !isActive {
                        Divider()
                        
                        Button(role: .destructive) {
                            sessionToDelete = session
                            Task {
                                deleteStats = await appState.fetchSessionStats(for: session.id)
                                isShowingDeleteAlert = true
                            }
                        } label: {
                            Label(tr("Удалить съемку...", "Delete Shoot..."), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - Вспомогательные методы
    
    private func reloadAllSessionStats() async {
        for session in appState.availableSessions {
            let stats = await appState.fetchSessionStats(for: session.id)
            await MainActor.run {
                sessionStatsCache[session.id] = stats
            }
        }
    }
    
    private func framesWord(for count: Int) -> String {
        if LocalizationManager.shared.activeLanguage == .en {
            return count == 1 ? "frame" : "frames"
        }
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 {
            return "кадров"
        }
        if mod10 == 1 {
            return "кадр"
        }
        if mod10 >= 2 && mod10 <= 4 {
            return "кадра"
        }
        return "кадров"
    }
}

// MARK: - Модальное окно редактирования метаданных сессии

public struct SessionMetadataSheetView: View {
    let session: CaptureSession
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var author: String = ""
    @State private var copyright: String = ""
    @State private var comment: String = ""
    @State private var isSavedFeedback = false
    
    public init(session: CaptureSession, appState: AppState) {
        self.session = session
        self.appState = appState
        _author = State(initialValue: session.author ?? "")
        _copyright = State(initialValue: session.copyright ?? "")
        _comment = State(initialValue: session.comment ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    GlassCard(cornerRadius: AppTheme.Radius.md) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(AppTheme.Colors.accent)
                                Text(session.name)
                                    .font(AppTheme.Typography.headline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                            }
                            
                            Text(tr("Метаданные автоматически внедряются в экспортируемые файлы и каталоги данной сессии.", "Metadata is automatically embedded into exported files and catalogs for this session."))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .padding(AppTheme.Spacing.md)
                    }
                    
                    GlassCard(cornerRadius: AppTheme.Radius.md) {
                        VStack(spacing: AppTheme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("Автор / Фотограф", "Author / Photographer"))
                                    .font(AppTheme.Typography.captionBold)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                TextField(tr("Имя автора", "Author name"), text: $author)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("Копирайт (Copyright)", "Copyright"))
                                    .font(AppTheme.Typography.captionBold)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                TextField(tr("© 2026 Имя правообладателя", "© 2026 Copyright holder"), text: $copyright)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("Заметка к съемке", "Shoot Note"))
                                    .font(AppTheme.Typography.captionBold)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                TextField(tr("Описание или комментарий", "Description or note"), text: $comment)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(AppTheme.Spacing.md)
                    }
                    
                    if isSavedFeedback {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                            Text(tr("Метаданные успешно сохранены", "Metadata successfully saved"))
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                        }
                        .transition(.opacity)
                    }
                    
                    Button {
                        appState.saveSessionMetadata(
                            for: session.id,
                            author: author.isEmpty ? nil : author,
                            copyright: copyright.isEmpty ? nil : copyright,
                            comment: comment.isEmpty ? nil : comment
                        )
                        withAnimation {
                            isSavedFeedback = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            dismiss()
                        }
                    } label: {
                        Text(tr("Сохранить метаданные", "Save Metadata"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.Colors.background)
            .navigationTitle(tr("Метаданные съёмки", "Shoot Metadata"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Закрыть", "Close")) { dismiss() }
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

