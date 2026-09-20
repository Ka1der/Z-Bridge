import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Окно настроек NikonZbridge, сгруппированное по 5 профессиональным разделам:
/// 1. Подключение USB/Wi-Fi (FTP, учетные данные, клиенты, PTP, мастер)
/// 2. Импорт (Live tethering, автозагрузка карты, форматы, дедупликация)
/// 3. Сессии и хранение (Запуск с пустой сессии vs возобновление, метаданные, кэш, каталог)
/// 4. Клиентский экран (HDMI, режимы показа, удержание Hold, водяной знак)
/// 5. Диагностика (DiskSpaceGuard, SQLite WAL, сверка каталога, журнал событий)
public struct ConnectionSheetView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: SettingsTab = .connection
    @State private var copiedNotice = ""
    @State private var isPasswordVisible = false
    
    // Поля метаданных сессии
    @State private var sessionAuthorText = ""
    @State private var sessionCopyrightText = ""
    @State private var sessionCommentText = ""
    @State private var sessionMetadataSavedNotice = false
    
    // Статистика базы данных и сверки
    @State private var dbStats: CatalogDatabase.DatabaseStats? = nil
    @State private var reconciliationNotice = ""
    @State private var isReconciling = false
    @State private var cacheClearedNotice = false
    
    
    public init(appState: AppState) {
        self.appState = appState
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
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Селектор 5 профессиональных групп настроек
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                Divider()
                    .background(Color.white.opacity(0.12))
                
                // Содержимое выбранной группы
                ScrollView {
                    VStack(spacing: 18) {
                        switch selectedTab {
                        case .connection:
                            connectionGroupContent
                        case .importTab:
                            importGroupContent
                        case .sessions:
                            sessionsGroupContent
                        case .clientScreen:
                            clientScreenGroupContent
                        case .diagnostics:
                            diagnosticsGroupContent
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.black.opacity(0.95))
            .navigationTitle("Настройки и подключение")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $appState.isWizardPresented) {
            ConnectionWizardView(appState: appState)
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
    
    // MARK: - Переключатель 5 групп настроек
    
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.blue : Color(white: 0.2))
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel(tab.rawValue)
                }
            }
        }
    }
    
    // MARK: - ГРУППА 1: Подключение USB / Wi-Fi
    
    private var connectionGroupContent: some View {
        VStack(spacing: 16) {
            // Общий статус подключения
            statusCard
            
            // Секция 1: Подключение по кабелю USB-C
            usbSectionCard
            
            // Секция 2: Подключение по воздуху (Wi-Fi через FTP-сервер)
            wifiAndFTPSettingsCard
        }
    }
    
    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.isCameraConnected ? Color.green : Color.orange)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.connectionStatusTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(appState.isCameraConnected ? "Камера готова к передаче снимков" : "Ожидание подключения кабеля или Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if appState.connectedClients > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Text("\(appState.connectedClients)")
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.25))
                .foregroundStyle(.green)
                .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(white: 0.15).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var usbSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.green)
                Text("ПОДКЛЮЧЕНИЕ ПО КАБЕЛЮ USB-C (БЕЗ FTP)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                Spacer()
                Text("Рекомендуется")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.usbConnected ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(appState.usbConnected ? "USB-камера подключена (\(appState.currentUSBManager.cameraName ?? "Nikon Z"))" : "Кабель USB-C не подключен")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            
            // Инструкция для USB
            VStack(alignment: .leading, spacing: 4) {
                Text("1. В меню камеры: **Настройки ➔ USB ➔ «Передача файлов»**.")
                Text("2. Соедините камеру и iPad/Mac кабелем Type-C.")
                Text("3. **Всё! Настраивать FTP в камере НЕ НУЖНО.** Приложение сразу распознает камеру.")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            
            // Кнопки мастера подключения и таблицы совместимости
            VStack(spacing: 8) {
                Button {
                    appState.isWizardPresented = true
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Мастер подключения Nikon Z")
                                .font(.caption.bold())
                            Text("Пошаговый подбор настроек вашей модели")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Button {
                    appState.isMatrixPresented = true
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Таблица совместимости моделей и прошивок")
                            .font(.caption.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(9)
                    .background(Color(white: 0.2))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(Color(white: 0.15).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var wifiAndFTPSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(.blue)
                Text("ПО ВОЗДУХУ: WI-FI ЧЕРЕЗ FTP-СЕРВЕР")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                Spacer()
                
                switch appState.serverState {
                case .running(let port):
                    Text("Порт \(port) активен")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                case .starting:
                    Text("Запуск...")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                case .stopped:
                    Text("Остановлен")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                case .failed(let err):
                    Text("Ошибка: \(err)")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            
            if !copiedNotice.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(copiedNotice)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 2)
            }
            
            // Количество подключенных клиентов FTP
            HStack {
                Text("Подключено FTP-клиентов камеры:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.connectedClients)")
                    .font(.caption.bold())
                    .foregroundStyle(appState.connectedClients > 0 ? Color.green : Color.white.opacity(0.7))
            }
            
            // IP и порт FTP-сервера
            if let primary = appState.primaryIP {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("СЕРВЕР (IP И ПОРТ):")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("\(primary.ipAddress) : \(appState.serverPort)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        copyToClipboard(primary.ipAddress, notice: "IP скопирован!")
                    } label: {
                        Text("Копировать IP")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Учетные данные FTP (Логин и Пароль из Keychain)
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ИМЯ ПОЛЬЗОВАТЕЛЯ (USER):")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(appState.ftpUsername)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        copyToClipboard(appState.ftpUsername, notice: "Логин скопирован!")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ПАРОЛЬ (PASS) В KEYCHAIN:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(isPasswordVisible ? appState.ftpPassword : "••••••••")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        copyToClipboard(appState.ftpPassword, notice: "Пароль скопирован!")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        appState.regenerateFTPPassword()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .padding(6)
                            .background(Color.orange.opacity(0.3))
                            .foregroundStyle(.orange)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // Управление приемом и перезапуском
            VStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { appState.isFTPReceivingEnabled },
                    set: { appState.toggleFTPReceiving($0) }
                )) {
                    Text("Разрешить входящие соединения FTP")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .tint(.green)
                
                Toggle(isOn: Binding(
                    get: { appState.isFTPAutoStartEnabled },
                    set: { appState.toggleFTPAutoStart($0) }
                )) {
                    Text("Автозапуск FTP при старте программы")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .tint(.blue)
                
                Button {
                    appState.restartServer()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Перезапустить FTP-сервер")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            
            // Техническая инструкция для Nikon Z / WT-7
            VStack(alignment: .leading, spacing: 4) {
                Text("Инструкция по настройке камеры Nikon Z:")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text("1. Меню сети 📡 ➔ **«Подключение к FTP-серверу»** ➔ Создать профиль.")
                Text("2. Укажите IP-адрес, порт, логин и пароль выше.")
                Text("3. Включите **«Автоматическая отправка»** в меню параметров FTP.")
                Text("4. Для беспроводного адаптера **Nikon WT-7**: переведите переключатель в режим FTP и используйте те же реквизиты.")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding()
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - ГРУППА 2: Импорт
    
    private var importGroupContent: some View {
        VStack(spacing: 16) {
            // Карточка настроек автоматической загрузки
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                    Text("АВТОЗАГРУЗКА И ПРЕДПОЧТЕНИЯ ФОРМАТОВ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                }
                
                Toggle(
                    "Автозагрузка новых кадров (live tethering)",
                    isOn: Binding(
                        get: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled },
                        set: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled = $0 }
                    )
                )
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .tint(.green)
                Text("Автоматически загружать новые снимки в активную сессию сразу при нажатии спуска затвора камеры.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Divider().background(Color.white.opacity(0.1))
                
                Toggle(
                    "Автозагрузка карты памяти при подключении",
                    isOn: Binding(
                        get: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled },
                        set: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled = $0 }
                    )
                )
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .tint(.green)
                Text("Автоматически ставить в очередь на скачивание все кадры с карты памяти при соединении по кабелю USB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Divider().background(Color.white.opacity(0.1))
                
                // Выбор предпочтительного формата
                VStack(alignment: .leading, spacing: 6) {
                    Text("Предпочтительный формат для импорта:")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    
                    Picker("Формат импорта", selection: $appState.importFormatPreference) {
                        ForEach(ImportFormatPreference.allCases) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Определяет, какие файлы загружаются при импорте. Фильтрация просмотра в галерее настраивается отдельно.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Уведомление о сессионной дедупликации
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(.green)
                    Text("Защита от дубликатов с изоляцией по сессиям")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                
                Text("Файлы отслеживаются по уникальному идентификатору камеры в пределах текущей сессии. Повторный импорт в ту же сессию исключает повторную загрузку, а открытие новой сессии позволяет безопасно скачивать кадры заново.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Кнопка быстрого перехода в экран импорта
            Button {
                dismiss()
                appState.isUSBBrowserPresented = true
            } label: {
                HStack {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Открыть экран «Импорт с камеры»")
                            .font(.headline.bold())
                        Text("Просмотр карты памяти, пакетный выбор и пофайловый прогресс")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .padding(14)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    
    // MARK: - ГРУППА 3: Сессии и хранение
    
    private var sessionsGroupContent: some View {
        VStack(spacing: 16) {
            // Режим запуска: пустая сессия по умолчанию vs продолжение последней
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Продолжать последнюю сессию при запуске", isOn: $appState.resumeLastSessionOnLaunch)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .tint(.blue)
                
                Text("По умолчанию выключено: приложение начинает работу с новой пустой сессии. Если включено, при старте автоматически открывается последняя активная съемка. Предыдущие снимки и сессии всегда сохраняются в истории съемок.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Метаданные текущей сессии (Автор, Копирайт, Комментарий)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "pencil.and.list.clipboard")
                        .foregroundStyle(.orange)
                    Text("МЕТАДАННЫЕ АКТИВНОЙ СЪЕМКИ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                    Spacer()
                    if let session = appState.currentSession {
                        Text(session.name)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                
                VStack(spacing: 10) {
                    HStack {
                        Text("Автор:")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        TextField("Имя фотографа", text: $sessionAuthorText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Копирайт:")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        TextField("© 2026 Фотограф", text: $sessionCopyrightText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Заметка:")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        TextField("Описание съемки", text: $sessionCommentText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                HStack {
                    if sessionMetadataSavedNotice {
                        Text("Метаданные сохранены!")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
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
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Каталог хранения и очистка кэша миниатюр
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.yellow)
                    Text("КАТАЛОГ ХРАНЕНИЯ И ПРЕВЬЮ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Базовый каталог сессий на диске:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(StorageManager.shared.baseStorageURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text("Оригиналы никогда не перезаписываются и сохраняются в неизменном виде в каталогах сессий.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Кэш миниатюр в оперативной памяти")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text(cacheClearedNotice ? "Кэш очищен!" : "Освобождает ОЗУ без удаления файлов на диске")
                            .font(.caption2)
                            .foregroundStyle(cacheClearedNotice ? Color.green : Color.secondary)
                    }
                    Spacer()
                    Button("Очистить кэш") {
                        PreviewMemoryCache.shared.clear()
                        withAnimation { cacheClearedNotice = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { cacheClearedNotice = false }
                        }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - ГРУППА 4: Клиентский экран
    
    private var clientScreenGroupContent: some View {
        VStack(spacing: 16) {
            // Статус внешнего экрана (HDMI / AirPlay)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.clientMonitorManager.externalDisplayStatus.isConnected ? "tv.fill" : "tv")
                        .font(.title2)
                        .foregroundStyle(appState.clientMonitorManager.externalDisplayStatus.isConnected ? .green : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.clientMonitorManager.externalDisplayStatus.isConnected ? "Внешний монитор подключен" : "Внешний экран не обнаружен")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(appState.clientMonitorManager.externalDisplayStatus.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                if !appState.clientMonitorManager.externalDisplayStatus.isConnected {
                    Text("Подключите кабель USB-C / HDMI или включите трансляцию AirPlay. Вы также можете открыть монитор прямо на этом устройстве.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Режимы показа и задержка
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.blue)
                    Text("РЕЖИМЫ ПОКАЗА ДЛЯ КЛИЕНТА")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
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
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Фиксация кадра (Hold / Pin) и водяной знак
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                    Text("УДЕРЖАНИЕ (HOLD) И ВОДЯНОЙ ЗНАК")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                }
                
                Toggle("Зафиксировать текущий кадр (Hold)", isOn: Binding(
                    get: { appState.clientMonitorManager.config.isHoldEnabled },
                    set: { appState.clientMonitorManager.setHold($0, for: appState.selectedGroup) }
                ))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                
                if let held = appState.clientMonitorManager.heldGroup {
                    HStack {
                        Text("Удерживается кадр:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(held.baseName)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Button("Отпустить") {
                            appState.clientMonitorManager.releaseHold(latestGroup: appState.filteredGroups.first)
                        }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                Toggle("Показывать плашку информации и водяной знак", isOn: Binding(
                    get: { appState.clientMonitorManager.config.showSubtleOverlay },
                    set: { appState.clientMonitorManager.config.showSubtleOverlay = $0 }
                ))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Отображает ненавязчивое имя кадра или плашку конфиденциальности на мониторе клиента.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Кнопка запуска клиентского монитора
            Button {
                dismiss()
                appState.presentClientMonitor()
            } label: {
                HStack {
                    Image(systemName: "play.tv.fill")
                    Text("Открыть клиентский монитор на весь экран")
                        .font(.headline.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .padding(14)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    
    // MARK: - ГРУППА 5: Диагностика
    
    private var diagnosticsGroupContent: some View {
        VStack(spacing: 16) {
            // Контроль свободного места (DiskSpaceGuard)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(.green)
                    Text("ЗАЩИТА ДИСКОВОГО ПРОСТРАНСТВА (DISKSPACEGUARD)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
                
                let freeBytes = DiskSpaceGuard().availableFreeBytes(at: StorageManager.shared.baseStorageURL)
                let freeGB = Double(freeBytes) / 1_073_741_824.0
                let reserveMB = DiskSpaceGuard.defaultReserveBytes / (1024 * 1024)
                
                HStack {
                    Text("Доступно на накопителе:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f ГБ", freeGB))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                
                HStack {
                    Text("Неснижаемый резерв безопасности:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(reserveMB) МБ")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Запись блокируется автоматически при остатке памяти менее \(reserveMB) МБ.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // База данных SQLite с WAL-режимом
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundStyle(.blue)
                    Text("КАТАЛОГ SQLITE (РЕЖИМ WAL)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                }
                
                if let stats = dbStats {
                    HStack {
                        Text("Версия схемы:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("v\(stats.schemaVersion)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Text("Режим журнала:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(stats.journalMode)
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    
                    HStack {
                        Text("Всего сессий в базе:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(stats.totalSessions)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Text("Всего зарегистрировано кадров:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(stats.totalAssets)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    
                    let dbSizeKB = Double(stats.fileSizeBytes) / 1024.0
                    HStack {
                        Text("Размер файла БД:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f КБ", dbSizeKB))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Сверка каталога с диском
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                    Text("СВЕРКА КАТАЛОГА С ДИСКОМ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                }
                
                Text("Проверяет соответствие файлов в папке активной сессии записям в базе данных SQLite. Восстанавливает неотслеженные кадры и отмечает удаленные.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !reconciliationNotice.isEmpty {
                    Text(reconciliationNotice)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
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
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isReconciling ? "Выполняется сверка..." : "Запустить сверку с диском")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(isReconciling)
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Диагностический журнал событий
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.yellow)
                    Text("ЖУРНАЛ ДИАГНОСТИЧЕСКИХ СОБЫТИЙ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
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
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
                
                Text("Журнал содержит технические детали сетевых сессий и конвейера. Конфиденциальные данные и пароли маскируются.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(white: 0.15).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
