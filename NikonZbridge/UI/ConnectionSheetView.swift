import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Окно настроек NikonZbridge в дизайн-системе Liquid Glass.
/// Поддерживает адаптивную компоновку для iPhone и iPad:
/// - На узком окне: вертикальная навигационная иерархия (NavigationStack) без обрезки заголовков;
/// - На широком окне: двухколоночная компоновка (сайдбар разделов + контент справа);
/// 
/// Группировка настроек по 5 ключевым профессиональным разделам:
/// 1. Подключение (кабель USB-C, Wi-Fi, FTP-сервер, мастер подключения, таблица совместимости);
/// 2. Импорт (Live tethering, автозагрузка с карты памяти, предпочтительный формат, дедупликация);
/// 3. Сессии и хранение (Запуск с пустой сессии vs возобновление, метаданные, безопасная очистка кэша ОЗУ);
/// 4. Клиентский экран (HDMI / AirPlay, режимы показа, задержка, удержание Hold, водяной знак);
/// 5. Диагностика (Базовые пути хранения, DiskSpaceGuard, SQLite WAL, сверка каталога с диском, журнал).
public struct ConnectionSheetView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: SettingsTab = .connection
    @State private var navigationPath = NavigationPath()
    @State private var copiedNotice = ""
    @State private var isPasswordVisible = false
    
    // Поля метаданных активной сессии
    @State private var sessionAuthorText = ""
    @State private var sessionCopyrightText = ""
    @State private var sessionCommentText = ""
    @State private var sessionMetadataSavedNotice = false
    
    // Статистика базы данных, сверка и кэш
    @State private var dbStats: CatalogDatabase.DatabaseStats? = nil
    @State private var reconciliationNotice = ""
    @State private var isReconciling = false
    @State private var cacheClearedNotice = false
    
    // Опасная зона: удаление активной сессии
    @State private var isShowingDeleteActiveAlert = false
    @State private var deleteStats: SessionStats? = nil
    
    public init(appState: AppState, initialTab: SettingsTab = .connection) {
        self.appState = appState
        self._selectedTab = State(initialValue: SettingsTab.visibleCases.contains(initialTab) ? initialTab : .connection)
    }
    
    private func copyToClipboard(_ text: String, notice: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation {
            copiedNotice = notice
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNotice = ""
            }
        }
    }
    
    private func closeSettings() {
        withAnimation {
            appState.isSettingsPresented = false
            appState.isShowingConnectionSheet = false
        }
        dismiss()
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 620
            
            Group {
                if isWide {
                    wideSettingsLayout
                } else {
                    narrowSettingsLayout
                }
            }
        }
        .sheet(isPresented: $appState.isMatrixPresented) {
            CompatibilityMatrixView()
        }
        .onAppear {
            sessionAuthorText = appState.sessionAuthor
            sessionCopyrightText = appState.sessionCopyright
            sessionCommentText = appState.sessionComment
            loadDatabaseStats()
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Адаптивная компоновка: Узкое окно (iPhone, узкий Split View)
    
    private var narrowSettingsLayout: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    // Плашка быстрого статуса в шапке
                    quickStatusHeader
                    
                    // Вертикальный список 5 групп настроек (без горизонтальной обрезки)
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(SettingsTab.visibleCases) { tab in
                            Button {
                                navigationPath.append(tab)
                            } label: {
                                settingsCategoryRow(tab: tab)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            .background(AppTheme.Colors.background)
            .navigationTitle("Настройки")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { closeSettings() }
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
            .navigationDestination(for: SettingsTab.self) { tab in
                ScrollView {
                    content(for: tab)
                        .padding(AppTheme.Spacing.md)
                }
                .background(AppTheme.Colors.background)
                .navigationTitle(tab.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
    }
    
    // MARK: - Адаптивная компоновка: Широкое окно (iPad, ландшафт, Mac)
    
    private var wideSettingsLayout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Левая боковая панель со списком разделов
                VStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(SettingsTab.visibleCases) { tab in
                        let isSelected = selectedTab == tab
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                                        .fill(tab.systemColor.opacity(isSelected ? 0.25 : 0.12))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: tab.iconName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(tab.systemColor)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.title)
                                        .font(AppTheme.Typography.subheadlineBold)
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    Text(tab.subtitle)
                                        .font(AppTheme.Typography.caption2)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.bold())
                                        .foregroundStyle(AppTheme.Colors.accent)
                                }
                            }
                            .padding(AppTheme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .fill(isSelected ? AppTheme.Colors.surfaceSecondary : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    quickStatusHeader
                }
                .padding(AppTheme.Spacing.md)
                .frame(width: 290)
                .background(AppTheme.Colors.surfacePrimary.opacity(0.6))
                
                Divider()
                    .overlay(AppTheme.Colors.borderSubtle)
                
                // Правая панель с подробными настройками
                ScrollView {
                    content(for: selectedTab)
                        .padding(AppTheme.Spacing.lg)
                }
                .background(AppTheme.Colors.background)
            }
            .navigationTitle("Настройки")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { closeSettings() }
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
    }
    
    // MARK: - Строка категории настроек (для вертикального меню)
    
    private func settingsCategoryRow(tab: SettingsTab) -> some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(tab.systemColor.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: tab.iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tab.systemColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.title)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Text(tab.subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - Быстрый статус в заголовке
    
    private var quickStatusHeader: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Circle()
                    .fill(appState.isCameraConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.statusOrange)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.connectionStatusTitle)
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(appState.isCameraConnected ? "Камера готова к передаче" : "Ожидание подключения")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                if appState.connectedClients > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi")
                        Text("\(appState.connectedClients)")
                    }
                    .font(AppTheme.Typography.caption2Bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppTheme.Colors.statusGreen.opacity(0.18))
                    .foregroundStyle(AppTheme.Colors.statusGreen)
                    .clipShape(Capsule())
                }
            }
            .padding(AppTheme.Spacing.sm)
        }
    }
    
    // MARK: - Маршрутизация контента разделов
    
    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            switch tab {
            case .connection:
                connectionGroupContent
            case .importTab:
                importGroupContent
            case .sessions:
                if AppFeatures.sessionManagementEnabled { sessionsGroupContent }
            case .clientScreen:
                clientScreenGroupContent
            case .diagnostics:
                diagnosticsGroupContent
            }
        }
    }
    
    // MARK: - 1. ГРУППА: Подключение (USB-C, Wi-Fi, FTP)
    
    private var connectionGroupContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Общий статус подключения
            statusCard
            
            // Секция 1: Подключение по кабелю USB-C
            usbSectionCard
            
            // Секция 2: Подключение по воздуху (Wi-Fi через FTP-сервер)
            wifiAndFTPSettingsCard
        }
    }
    
    private var statusCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            HStack(spacing: 12) {
                Circle()
                    .fill(appState.isCameraConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.statusOrange)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.connectionStatusTitle)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(appState.isCameraConnected ? "Камера готова к передаче снимков" : "Ожидание подключения кабеля или Wi-Fi")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                if appState.connectedClients > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                        Text("\(appState.connectedClients)")
                    }
                    .font(AppTheme.Typography.captionBold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.Colors.statusGreen.opacity(0.18))
                    .foregroundStyle(AppTheme.Colors.statusGreen)
                    .clipShape(Capsule())
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    private var usbSectionCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(AppTheme.Colors.statusGreen)
                    Text("ПОДКЛЮЧЕНИЕ ПО КАБЕЛЮ USB-C (БЕЗ FTP)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.statusGreen)
                    Spacer()
                    Text("Рекомендуется")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.statusGreen.opacity(0.15))
                        .foregroundStyle(AppTheme.Colors.statusGreen)
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 10) {
                    Circle()
                        .fill(appState.usbConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.textTertiary)
                        .frame(width: 8, height: 8)
                    Text(appState.usbConnected ? "USB-камера подключена (\(appState.currentUSBManager.cameraName ?? "Nikon Z"))" : "Кабель USB-C не подключен")
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. В меню камеры: **Настройки ➔ USB ➔ «Передача файлов»**.")
                    Text("2. Соедините камеру и устройство кабелем Type-C.")
                    Text("3. **Настраивать FTP в камере НЕ НУЖНО.** Приложение сразу распознает камеру.")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                
                VStack(spacing: 8) {
                    Button {
                        appState.isMatrixPresented = true
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                            Text("Таблица совместимости моделей и прошивок")
                                .font(AppTheme.Typography.captionBold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .padding(10)
                        .background(AppTheme.Colors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    private var wifiAndFTPSettingsCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text("ПО ВОЗДУХУ: WI-FI ЧЕРЕЗ FTP-СЕРВЕР")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    Spacer()
                    
                    switch appState.serverState {
                    case .running(let port):
                        Text("Порт \(port) активен")
                            .font(AppTheme.Typography.caption2Bold)
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    case .starting:
                        Text("Запуск...")
                            .font(AppTheme.Typography.caption2Bold)
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                    case .stopped:
                        Text("Остановлен")
                            .font(AppTheme.Typography.caption2Bold)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    case .failed(let err):
                        Text("Ошибка: \(err)")
                            .font(AppTheme.Typography.caption2Bold)
                            .foregroundStyle(AppTheme.Colors.statusRed)
                    }
                }
                
                if !copiedNotice.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                        Text(copiedNotice)
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    }
                }
                
                HStack {
                    Text("Подключено клиентов камеры:")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(appState.connectedClients)")
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(appState.connectedClients > 0 ? AppTheme.Colors.statusGreen : AppTheme.Colors.textPrimary)
                }
                
                // IP и порт
                if let primary = appState.primaryIP {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("СЕРВЕР (IP И ПОРТ):")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text("\(primary.ipAddress) : \(appState.serverPort)")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        Spacer()
                        Button {
                            copyToClipboard(primary.ipAddress, notice: "IP скопирован!")
                        } label: {
                            Text("Копировать IP")
                                .font(AppTheme.Typography.captionBold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.Colors.surfaceSecondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(AppTheme.Colors.surfacePrimary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                }
                
                // Учетные данные FTP
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ИМЯ ПОЛЬЗОВАТЕЛЯ (USER):")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(appState.ftpUsername)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        Spacer()
                        Button {
                            copyToClipboard(appState.ftpUsername, notice: "Логин скопирован!")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .padding(8)
                                .background(AppTheme.Colors.surfaceSecondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().overlay(AppTheme.Colors.borderSubtle)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ПАРОЛЬ (PASS) В KEYCHAIN:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(isPasswordVisible ? appState.ftpPassword : "••••••••")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        Spacer()
                        
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .font(.caption)
                                .padding(8)
                                .background(AppTheme.Colors.surfaceSecondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            copyToClipboard(appState.ftpPassword, notice: "Пароль скопирован!")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .padding(8)
                                .background(AppTheme.Colors.surfaceSecondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            appState.regenerateFTPPassword()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .padding(8)
                                .background(AppTheme.Colors.statusOrange.opacity(0.2))
                                .foregroundStyle(AppTheme.Colors.statusOrange)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(AppTheme.Colors.surfacePrimary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                
                // Переключатели FTP
                VStack(spacing: 8) {
                    Toggle("Разрешить входящие соединения FTP", isOn: Binding(
                        get: { appState.isFTPReceivingEnabled },
                        set: { appState.toggleFTPReceiving($0) }
                    ))
                    .font(AppTheme.Typography.captionBold)
                    .tint(AppTheme.Colors.statusGreen)
                    
                    Toggle("Автозапуск FTP при старте программы", isOn: Binding(
                        get: { appState.isFTPAutoStartEnabled },
                        set: { appState.toggleFTPAutoStart($0) }
                    ))
                    .font(AppTheme.Typography.captionBold)
                    .tint(AppTheme.Colors.accent)
                    
                    Button {
                        appState.restartServer()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Перезапустить FTP-сервер")
                        }
                        .font(AppTheme.Typography.captionBold)
                    }
                    .buttonStyle(.appSecondaryGlass)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Инструкция по настройке камеры Nikon Z:")
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("1. Меню сети 📡 ➔ **«Подключение к FTP-серверу»** ➔ Создать профиль.")
                    Text("2. Укажите IP-адрес, порт, логин и пароль выше.")
                    Text("3. Включите **«Автоматическая отправка»** в меню параметров FTP.")
                    Text("4. Для адаптера **Nikon WT-7**: режим FTP с теми же реквизитами.")
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 2. ГРУППА: Импорт
    
    private var importGroupContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("АВТОЗАГРУЗКА И ПРЕДПОЧТЕНИЯ ФОРМАТОВ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    
                    Toggle(
                        "Автозагрузка новых кадров (live tethering)",
                        isOn: Binding(
                            get: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled },
                            set: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled = $0 }
                        )
                    )
                    .font(AppTheme.Typography.subheadlineBold)
                    .tint(AppTheme.Colors.statusGreen)
                    
                    Text("Автоматически загружать новые снимки на устройство сразу при спуске затвора камеры.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    
                    Divider().overlay(AppTheme.Colors.borderSubtle)
                    
                    Toggle(
                        "Автозагрузка карты памяти при подключении",
                        isOn: Binding(
                            get: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled },
                            set: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled = $0 }
                        )
                    )
                    .font(AppTheme.Typography.subheadlineBold)
                    .tint(AppTheme.Colors.statusGreen)
                    
                    Text("Автоматически ставить в очередь на скачивание все кадры с карты памяти при подключении кабеля USB.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    
                    Divider().overlay(AppTheme.Colors.borderSubtle)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Предпочтительный формат для импорта:")
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        
                        Picker("Формат импорта", selection: $appState.importFormatPreference) {
                            ForEach(ImportFormatPreference.allCases) { pref in
                                Text(pref.rawValue).tag(pref)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text("Определяет, какие файлы загружаются при импорте. Фильтрация просмотра в галерее настраивается отдельно.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                        Text("Защита от повторной загрузки")
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    Text("Уже загруженные файлы исключаются из повторного импорта.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            Button {
                closeSettings()
                appState.isUSBBrowserPresented = true
            } label: {
                HStack {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Открыть экран «Импорт с камеры»")
                            .font(AppTheme.Typography.headline)
                        Text("Просмотр карты памяти, выбор файлов и прогресс")
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.appPrimary)
        }
    }
    
    // MARK: - 3. ГРУППА: Сессии и хранение
    
    private var sessionsGroupContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Режим запуска приложения
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Продолжать последнюю сессию при запуске",
                        isOn: $appState.resumeLastSessionOnLaunch
                    )
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .tint(AppTheme.Colors.accent)
                    
                    Text("По умолчанию выключено: приложение начинает работу с новой пустой сессии. Если включено, при старте автоматически открывается последняя активная съемка. Снимки прошлых сессий сохраняются в истории съемок.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Метаданные текущей активной съемки
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "pencil.and.list.clipboard")
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Text("МЕТАДАННЫЕ АКТИВНОЙ СЪЕМКИ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Spacer()
                        if let session = appState.currentSession {
                            Text(session.name)
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                    }
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("Автор:")
                                .font(AppTheme.Typography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            TextField("Имя фотографа", text: $sessionAuthorText)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Копирайт:")
                                .font(AppTheme.Typography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            TextField("© 2026 Фотограф", text: $sessionCopyrightText)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Заметка:")
                                .font(AppTheme.Typography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            TextField("Описание съемки", text: $sessionCommentText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    HStack {
                        if sessionMetadataSavedNotice {
                            Text("Метаданные сохранены!")
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                        }
                        Spacer()
                        Button("Сохранить метаданные") {
                            appState.saveSessionMetadata(
                                author: sessionAuthorText.isEmpty ? nil : sessionAuthorText,
                                copyright: sessionCopyrightText.isEmpty ? nil : sessionCopyrightText,
                                comment: sessionCommentText.isEmpty ? nil : sessionCommentText
                            )
                            withAnimation { sessionMetadataSavedNotice = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { sessionMetadataSavedNotice = false }
                            }
                        }
                        .font(AppTheme.Typography.captionBold)
                        .buttonStyle(.appPrimary)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Безопасная очистка кэша миниатюр в ОЗУ (отделена от удаления снимков!)
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                        Text("КЭШ МИНИАТЮР В ОПЕРАТИВНОЙ ПАМЯТИ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                        Spacer()
                        Text("Безопасное действие")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.statusGreen.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Text("Очистка кэша миниатюр освобождает оперативную память и временные превью. Исходные файлы RAW и JPEG на диске остаются в полной сохранности.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Кэш превью в RAM")
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text(cacheClearedNotice ? "Кэш успешно очищен!" : "Файлы на диске не затрагиваются")
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(cacheClearedNotice ? AppTheme.Colors.statusGreen : AppTheme.Colors.textTertiary)
                        }
                        Spacer()
                        Button("Очистить кэш миниатюр") {
                            PreviewMemoryCache.shared.clear()
                            withAnimation { cacheClearedNotice = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { cacheClearedNotice = false }
                            }
                        }
                        .buttonStyle(.appSecondaryGlass)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Опасная зона: управление удалением сессии
            if let active = appState.currentSession {
                GlassCard(cornerRadius: AppTheme.Radius.md, tint: AppTheme.Colors.statusRed) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.Colors.statusRed)
                            Text("ОПАСНАЯ ЗОНА: УПРАВЛЕНИЕ СЪЕМКОЙ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.statusRed)
                        }
                        
                        Text("Удаление активной съемки «\(active.name)» приведет к безвозвратному удалению всех входящих кадров с диска устройства.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        
                        Button(role: .destructive) {
                            Task {
                                deleteStats = await appState.fetchSessionStats(for: active.id)
                                isShowingDeleteActiveAlert = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Удалить текущую съемку «\(active.name)»...")
                            }
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.statusRed)
                        }
                        .buttonStyle(.appSecondaryGlass)
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .alert(
                    "Удалить съемку «\(appState.currentSession?.name ?? "")»?",
                    isPresented: $isShowingDeleteActiveAlert
                ) {
                    Button("Удалить навсегда", role: .destructive) {
                        if let session = appState.currentSession {
                            appState.deleteSession(id: session.id) { _ in }
                        }
                    }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    let files = deleteStats?.filesCount ?? appState.receivedFiles.count
                    let size = deleteStats?.formattedSize ?? ByteCountFormatter.string(fromByteCount: appState.totalBytesTransferred, countStyle: .file)
                    Text("Будет безвозвратно удалено \(files) файлов (\(size)). Файлы будут удалены с диска устройства. Действие необратимо.")
                }
            }
        }
    }
    
    // MARK: - 4. ГРУППА: Клиентский экран
    
    private var clientScreenGroupContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: appState.clientMonitorManager.externalDisplayStatus.isConnected ? "tv.fill" : "tv")
                            .font(.title2)
                            .foregroundStyle(appState.clientMonitorManager.externalDisplayStatus.isConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.clientMonitorManager.externalDisplayStatus.isConnected ? "Внешний монитор подключен" : "Внешний экран не обнаружен")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text(appState.clientMonitorManager.externalDisplayStatus.displayName)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    
                    if !appState.clientMonitorManager.externalDisplayStatus.isConnected {
                        Text("Подключите кабель USB-C / HDMI или включите трансляцию AirPlay. Вы также можете открыть монитор прямо на этом устройстве.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("РЕЖИМЫ ПОКАЗА ДЛЯ КЛИЕНТА")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    
                    Picker("Фильтр кадров", selection: Binding(
                        get: { appState.clientMonitorManager.config.filterMode },
                        set: { appState.clientMonitorManager.config.filterMode = $0 }
                    )) {
                        ForEach(ClientMonitorFilterMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Задержка переключения", selection: Binding(
                        get: { appState.clientMonitorManager.config.switchDelay },
                        set: { appState.clientMonitorManager.config.switchDelay = $0 }
                    )) {
                        ForEach(SwitchDelayOption.allCases) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Text("УДЕРЖАНИЕ (HOLD) И ВОДЯНОЙ ЗНАК")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                    }
                    
                    Toggle("Зафиксировать текущий кадр (Hold)", isOn: Binding(
                        get: { appState.clientMonitorManager.config.isHoldEnabled },
                        set: { appState.clientMonitorManager.setHold($0, for: appState.selectedGroup) }
                    ))
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .tint(AppTheme.Colors.statusOrange)
                    
                    if let held = appState.clientMonitorManager.heldGroup {
                        HStack {
                            Text("Удерживается кадр:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text(held.baseName)
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.statusOrange)
                            Button("Отпустить") {
                                appState.clientMonitorManager.releaseHold(latestGroup: appState.filteredGroups.first)
                            }
                            .buttonStyle(.appSecondaryGlass)
                        }
                    }
                    
                    Divider().overlay(AppTheme.Colors.borderSubtle)
                    
                    Toggle("Показывать плашку информации и водяной знак", isOn: Binding(
                        get: { appState.clientMonitorManager.config.showSubtleOverlay },
                        set: { appState.clientMonitorManager.config.showSubtleOverlay = $0 }
                    ))
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Text("Отображает ненавязчивое имя кадра или плашку конфиденциальности на мониторе клиента.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            Button {
                closeSettings()
                appState.presentClientMonitor()
            } label: {
                HStack {
                    Image(systemName: "play.tv.fill")
                    Text("Открыть клиентский монитор на весь экран")
                        .font(AppTheme.Typography.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.appPrimary)
        }
    }
    
    // MARK: - 5. ГРУППА: Диагностика (Файловая система, SQLite, Сверка, Журнал)
    
    private var diagnosticsGroupContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Технические пути файловой системы (Размещены в диагностике!)
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("ФАЙЛОВАЯ СИСТЕМА И ПУТИ ХРАНЕНИЯ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Каталог файлов приложения:")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        
                        HStack {
                            Text(appState.currentSessionDirectory.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(2)
                            
                            Spacer()
                            
                            Button {
                                copyToClipboard(appState.currentSessionDirectory.path, notice: "Путь скопирован!")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .padding(6)
                                    .background(AppTheme.Colors.surfaceSecondary)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(AppTheme.Colors.surfacePrimary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs))
                    }
                    
                    if let current = appState.currentSession {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Папка загрузки:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            
                            HStack {
                                Text(current.folderURL.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(2)
                                
                                Spacer()
                                
                                Button {
                                    copyToClipboard(current.folderURL.path, notice: "Путь скопирован!")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .padding(6)
                                        .background(AppTheme.Colors.surfaceSecondary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(AppTheme.Colors.surfacePrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs))
                        }
                    }
                    
                    Text("Оригиналы никогда не перезаписываются и сохраняются в неизменном виде в хранилище приложения.")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Защита дискового пространства (DiskSpaceGuard)
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                        Text("ЗАЩИТА ДИСКОВОГО ПРОСТРАНСТВА (DISKSPACEGUARD)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    }
                    
                    let freeBytes = DiskSpaceGuard().availableFreeBytes(at: StorageManager.shared.baseStorageURL)
                    let freeGB = Double(freeBytes) / 1_073_741_824.0
                    let reserveMB = DiskSpaceGuard.defaultReserveBytes / (1024 * 1024)
                    
                    HStack {
                        Text("Доступно на накопителе:")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f ГБ", freeGB))
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    HStack {
                        Text("Неснижаемый резерв безопасности:")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Spacer()
                        Text("\(reserveMB) МБ")
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                        Text("Запись блокируется автоматически при остатке памяти менее \(reserveMB) МБ.")
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Каталог SQLite (режим WAL)
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "cylinder.split.1x2.fill")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("КАТАЛОГ SQLITE (РЕЖИМ WAL)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    
                    if let stats = dbStats {
                        HStack {
                            Text("Версия схемы базы:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text("v\(stats.schemaVersion)")
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        
                        HStack {
                            Text("Режим журнала транзакций:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text(stats.journalMode)
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                        }
                        
                        HStack {
                            Text("Папок в хранилище:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text("\(stats.totalSessions)")
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        
                        HStack {
                            Text("Всего зарегистрировано кадров:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text("\(stats.totalAssets)")
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        
                        let dbSizeKB = Double(stats.fileSizeBytes) / 1024.0
                        HStack {
                            Text("Размер файла БД на диске:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f КБ", dbSizeKB))
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Сверка каталога с диском
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Text("СВЕРКА КАТАЛОГА С ДИСКОМ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                    }
                    
                    Text("Проверяет соответствие файлов в папке загрузки записям в базе данных SQLite. Восстанавливает неотслеженные кадры и отмечает удаленные.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    
                    if !reconciliationNotice.isEmpty {
                        Text(reconciliationNotice)
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    }
                    
                    Button {
                        isReconciling = true
                        Task {
                            let (missing, recovered) = await appState.runCatalogReconciliation()
                            await MainActor.run {
                                isReconciling = false
                                reconciliationNotice = "Сверка завершена: отсутствующих \(missing), восстановлено \(recovered)"
                                loadDatabaseStats()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isReconciling {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isReconciling ? "Выполняется сверка..." : "Запустить сверку с диском")
                        }
                        .font(AppTheme.Typography.captionBold)
                    }
                    .buttonStyle(.appSecondaryGlass)
                    .disabled(isReconciling)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Диагностический журнал событий
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Text("ЖУРНАЛ ДИАГНОСТИЧЕСКИХ СОБЫТИЙ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusOrange)
                        Spacer()
                        
                        Button {
                            let report = appState.diagnosticLogger.exportDiagnosticReport(
                                sessionName: appState.currentSession?.name,
                                cameraModel: appState.connectionStatusTitle,
                                totalAssets: appState.receivedFiles.count,
                                networkIPs: appState.activeIPs.map { "\($0.interfaceName): \($0.ipAddress)" }
                            )
                            copyToClipboard(report, notice: "Журнал скопирован!")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedNotice.isEmpty ? "doc.on.doc" : "checkmark")
                                Text(copiedNotice.isEmpty ? "Экспорт журнала" : "Скопирован!")
                            }
                            .font(AppTheme.Typography.captionBold)
                        }
                        .buttonStyle(.appSecondaryGlass)
                    }
                    
                    Text("Журнал содержит технические детали сетевых сессий и конвейера. Конфиденциальные данные и пароли маскируются.")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
            }
        }
    }
    
    private func loadDatabaseStats() {
        Task {
            let stats = await appState.fetchDatabaseStats()
            await MainActor.run {
                self.dbStats = stats
            }
        }
    }
}
