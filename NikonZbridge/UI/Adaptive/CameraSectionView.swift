import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Экран раздела «Подключение» в адаптивном каркасе Liquid Glass.
/// Объединяет управление подключениями (кабель USB-C, Wi-Fi / FTP-сервер),
/// параметры импорта, клиентский монитор и расширенную диагностику в одном окне без модальных перекрытий.
public struct CameraSectionView: View {
    @ObservedObject var appState: AppState
    
    @State private var selectedTab: SettingsTab = .connection
    @State private var copiedNotice: String = ""
    @State private var isPasswordVisible: Bool = false
    
    // Поля метаданных активной сессии (для режима сессий)
    @State private var sessionAuthorText = ""
    @State private var sessionCopyrightText = ""
    @State private var sessionCommentText = ""
    @State private var sessionMetadataSavedNotice = false
    
    // Статистика базы данных, сверка и кэш
    @State private var dbStats: CatalogDatabase.DatabaseStats? = nil
    @State private var reconciliationNotice = ""
    @State private var isReconciling = false
    @State private var cacheClearedNotice = false
    
    // Удаление активной сессии
    @State private var isShowingDeleteActiveAlert = false
    @State private var deleteStats: SessionStats? = nil
    
    public init(appState: AppState, initialTab: SettingsTab = .connection) {
        self.appState = appState
        self._selectedTab = State(initialValue: SettingsTab.visibleCases.contains(initialTab) ? initialTab : .connection)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 1. Верхняя карточка статуса камеры (с фото, нормализованным именем и индикатором)
                connectionHeaderCard
                
                // 2. Компактная плашка прогресса передачи (при наличии активного задания или очереди)
                if appState.activeTransferJob != nil || appState.activeQueueCount > 0 {
                    progressStripSection
                }
                
                // 3. Селектор подразделов настроек и подключения (Liquid Glass pills)
                categoryPicker
                
                // 4. Плашка уведомления о копировании в буфер обмена
                if !copiedNotice.isEmpty {
                    copiedNoticeBanner
                }
                
                // 5. Контент активного подраздела
                switch selectedTab {
                case .connection:
                    connectionTabContent
                case .importTab:
                    importTabContent
                case .clientScreen:
                    clientScreenTabContent
                case .diagnostics:
                    diagnosticsTabContent
                case .sessions:
                    if AppFeatures.sessionManagementEnabled {
                        sessionsTabContent
                    } else {
                        connectionTabContent
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .studioBackground()
        .sheet(isPresented: $appState.isMatrixPresented) {
            CompatibilityMatrixView()
        }
        .onAppear {
            sessionAuthorText = appState.sessionAuthor
            sessionCopyrightText = appState.sessionCopyright
            sessionCommentText = appState.sessionComment
            loadDatabaseStats()
        }
    }
    
    // MARK: - 1. Верхняя карточка статуса подключения
    
    private var connectionHeaderCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(spacing: AppTheme.Spacing.sm) {
                if appState.isCameraConnected {
                    // 1. Название камеры с маленькой иконкой камеры (по центру)
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                        
                        Text(appState.normalizedCameraName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    
                    // 2. Логотип / изображение корпуса камеры (прозрачный PNG без фона, по центру)
                    CameraProductImageView(model: appState.connectedCameraModel)
                        .frame(height: 120)
                        .padding(.vertical, 4)
                    
                    // 3. Статус: зеленый индикатор + надпись "Подключено" (по центру)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.Colors.statusGreen)
                            .frame(width: 8, height: 8)
                            .shadow(color: AppTheme.Colors.statusGreen.opacity(0.8), radius: 5)
                        
                        Text(tr("Подключено", "Connected"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glassPill(tint: AppTheme.Colors.statusGreen)
                    
                    // 4. Тип подключения (по центру)
                    Text(connectionTransportDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    // Иконка ожидания в стеклянном круге (по центру)
                    ZStack {
                        Circle()
                            .fill(connectionStatusColor.opacity(0.12))
                            .background(.ultraThinMaterial, in: Circle())
                            .frame(width: 56, height: 56)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [connectionStatusColor.opacity(0.45), connectionStatusColor.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: connectionIcon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(connectionStatusColor)
                    }
                    .padding(.bottom, 2)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 8, height: 8)
                        
                        Text(tr("Ожидание камеры", "Waiting for camera"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    Text(connectionSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .padding(.horizontal, AppTheme.Spacing.md)
        }
    }
    
    private var connectionTransportDescription: String {
        if appState.usbConnected {
            return "USB-C"
        } else if appState.isServerRunning {
            return "Wi-Fi FTP"
        } else {
            return tr("Беспроводная сеть", "Wireless Network")
        }
    }
    
    private var connectionIcon: String {
        if appState.usbConnected {
            return "cable.connector"
        } else if appState.isServerRunning {
            return "wifi"
        } else {
            return "camera"
        }
    }
    
    private var connectionStatusColor: Color {
        if appState.isCameraConnected {
            return AppTheme.Colors.statusGreen
        } else if appState.isCameraConnecting {
            return AppTheme.Colors.statusOrange
        } else {
            return AppTheme.Colors.statusNeutral
        }
    }
    
    private var connectionSubtitle: String {
        if appState.usbConnected {
            return appState.normalizedCameraName
        } else if appState.isServerRunning {
            return tr("FTP: порт \(appState.serverPort) • Клиентов: \(appState.connectedClients)", "FTP: port \(appState.serverPort) • Clients: \(appState.connectedClients)")
        } else {
            return tr("Подключите камеру Nikon Z по USB-C или Wi-Fi", "Connect Nikon Z camera via USB-C or Wi-Fi")
        }
    }
    
    // MARK: - 2. Компактная плашка прогресса передачи
    
    @ViewBuilder
    private var progressStripSection: some View {
        if let job = appState.activeTransferJob {
            TransferProgressStrip(
                filename: job.filename,
                transferredBytes: job.transferredBytes,
                totalBytes: job.totalBytes,
                speedMBs: appState.currentTransferSpeedMBs,
                isUSB: appState.usbConnected,
                onTap: {
                    appState.isQueuePresented = true
                },
                onCancel: {
                    appState.cancelJob(id: job.id)
                }
            )
        } else if appState.activeQueueCount > 0 {
            TransferProgressStrip(
                completedCount: appState.totalFramesCount,
                totalCount: appState.totalFramesCount + appState.activeQueueCount,
                label: "В очереди: \(appState.activeQueueCount) кадров",
                actionTitle: "Очередь",
                onTap: {
                    appState.isQueuePresented = true
                }
            )
        }
    }
    
    // MARK: - 3. Селектор подразделов настроек (Liquid Glass Pills)
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsTab.visibleCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            Text(tab.title)
                                .font(AppTheme.Typography.captionBold)
                        }
                        .foregroundStyle(isSelected ? AppTheme.Colors.onAccent : AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if isSelected {
                                    AppTheme.Colors.accent
                                        .clipShape(Capsule())
                                        .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 6, y: 2)
                                } else {
                                    Color.white.opacity(0.06)
                                        .clipShape(Capsule())
                                }
                            }
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(isSelected ? 0 : 0.10), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
    
    private var copiedNoticeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.Colors.statusGreen)
            Text(copiedNotice)
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.statusGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPill(tint: AppTheme.Colors.statusGreen)
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - 4. Подраздел: Подключение (USB-C и Wi-Fi FTP)
    
    private var connectionTabContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            usbConnectionSection
            wifiFtpSection
            toolsSection
        }
    }
    
    // MARK: - Прямое USB-подключение
    
    private var usbConnectionSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "cable.connector")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(appState.usbConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                        Text(tr("Прямое подключение USB-C", "Direct USB-C Connection"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    if appState.usbConnected {
                        HStack(spacing: 5) {
                            Circle().fill(AppTheme.Colors.statusGreen).frame(width: 6, height: 6)
                                .shadow(color: AppTheme.Colors.statusGreen.opacity(0.6), radius: 3)
                            Text(appState.currentUSBManager.isCatalogReady ? tr("Готово к импорту", "Ready to import") : tr("Подключено", "Connected"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.statusGreen)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.statusGreen.opacity(0.12))
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .overlay(Capsule().stroke(AppTheme.Colors.statusGreen.opacity(0.30), lineWidth: 1))
                    } else {
                        HStack(spacing: 5) {
                            Circle().fill(Color.white.opacity(0.35)).frame(width: 6, height: 6)
                            Text(tr("Отключено", "Disconnected"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
                
                if appState.usbConnected {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        // Модель камеры
                        HStack(spacing: 6) {
                            Text(tr("Модель камеры:", "Camera Model:"))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(appState.normalizedCameraName)
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        
                        // Целевая сессия
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text(AppFeatures.sessionManagementEnabled ? tr("Целевая сессия:", "Target Session:") : tr("Сохранение:", "Save To:"))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(AppFeatures.sessionManagementEnabled ? (appState.currentSession?.name ?? tr("Основная сессия", "Main Session")) : tr("На это устройство", "This Device"))
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        
                        Divider()
                            .background(AppTheme.Colors.borderSubtle)
                        
                        // Состояние каталога карты памяти
                        let stats = appState.currentUSBManager.catalogStats
                        
                        if !appState.currentUSBManager.isCatalogReady {
                            HStack(spacing: AppTheme.Spacing.xs) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text(tr("Чтение оглавления карты памяти...", "Reading memory card catalog..."))
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("Файлов на карте: \(stats.totalCount) (\(stats.formattedTotalSize))", "Files on card: \(stats.totalCount) (\(stats.formattedTotalSize))"))
                                    .font(AppTheme.Typography.captionBold)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                
                                if stats.unimportedCount > 0 {
                                    Text(tr("Доступно для импорта: \(stats.unimportedCount) новых (\(stats.formattedUnimportedSize))", "Available for import: \(stats.unimportedCount) new (\(stats.formattedUnimportedSize))"))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.accent)
                                } else {
                                    Text(tr("Все файлы на карте уже загружены на устройство", "All files on card are already downloaded to device"))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.statusGreen)
                                }
                            }
                        }
                        
                        Divider()
                            .background(AppTheme.Colors.borderSubtle)
                        
                        // Независимые настройки автозагрузки
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Toggle(tr("Автоматически загружать новые кадры (live tethering)", "Automatically download new shots (live tethering)"), isOn: Binding(
                                get: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled },
                                set: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled = $0 }
                            ))
                            .font(AppTheme.Typography.captionBold)
                            .tint(AppTheme.Colors.accent)
                            
                            Toggle(tr("Загружать файлы с карты при подключении", "Download files from card on connection"), isOn: Binding(
                                get: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled },
                                set: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled = $0 }
                            ))
                            .font(AppTheme.Typography.captionBold)
                            .tint(AppTheme.Colors.accent)
                            
                            Text(tr("Ручной импорт не изменяет эти настройки. Параметры сохраняются между запусками.", "Manual import does not alter these settings. Preferences persist between launches."))
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(tr("Подключите камеру Nikon Z кабелем USB-C к устройству для прямого импорта и быстрого чтения карты памяти.", "Connect Nikon Z camera via USB-C cable for direct import and fast memory card access."))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            instructionStepRow(number: "1", text: tr("В меню камеры: **Настройки ➔ USB ➔ «Передача файлов»**.", "In camera menu: **Setup ➔ USB ➔ «File Transfer (MTP/PTP)»**."))
                            instructionStepRow(number: "2", text: tr("Соедините камеру и устройство кабелем Type-C.", "Connect camera and device with a USB-C cable."))
                            instructionStepRow(number: "3", text: tr("**Настраивать FTP в камере НЕ НУЖНО.** Приложение сразу распознает камеру.", "**No camera FTP configuration required.** The app detects camera directly."), isSecondary: true)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                            Text(tr("Поддерживаются Z 9, Z 8, Z 7 II, Z 6 III, Z 6 II, Z 5, Z f, Z 50, Z 30, Z fc.", "Supports Z 9, Z 8, Z 7 II, Z 6 III, Z 6 II, Z 5, Z f, Z 50, Z 30, Z fc."))
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - Wi-Fi и FTP сервер (встроенные реквизиты)
    
    private var wifiFtpSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text(tr("Беспроводная передача Wi-Fi / FTP", "Wireless Transfer Wi-Fi / FTP"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { appState.isServerRunning },
                        set: { running in
                            if running {
                                appState.startServer()
                            } else {
                                appState.stopServer()
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(AppTheme.Colors.accent)
                }
                
                HStack(spacing: 6) {
                    serverStateBadge
                    Spacer()
                    HStack(spacing: 5) {
                        if appState.connectedClients > 0 {
                            Circle()
                                .fill(AppTheme.Colors.statusGreen)
                                .frame(width: 6, height: 6)
                                .shadow(color: AppTheme.Colors.statusGreen.opacity(0.8), radius: 4)
                        }
                        Text(tr("Клиентов: \(appState.connectedClients)", "Clients: \(appState.connectedClients)"))
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(appState.connectedClients > 0 ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassPill(tint: appState.connectedClients > 0 ? AppTheme.Colors.statusGreen : nil)
                }
                
                // IP и порт для ввода в камеру
                if let primary = appState.primaryIP {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("СЕРВЕР (IP И ПОРТ):", "SERVER (IP & PORT):"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text("\(primary.ipAddress) : \(appState.serverPort)")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        Spacer()
                        Button {
                            copyToClipboard(primary.ipAddress, notice: tr("IP-адрес скопирован!", "IP address copied!"))
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .bold))
                                Text(tr("Копировать IP", "Copy IP"))
                                    .font(AppTheme.Typography.captionBold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassPill()
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .glassInset(cornerRadius: AppTheme.Radius.sm)
                }
                
                // Учетные данные FTP
                VStack(spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("ИМЯ ПОЛЬЗОВАТЕЛЯ (USER):", "USERNAME (USER):"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(appState.ftpUsername)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        Spacer()
                        Button {
                            copyToClipboard(appState.ftpUsername, notice: tr("Логин скопирован!", "Username copied!"))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium))
                                .padding(8)
                                .glassSurface(shape: Circle())
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().overlay(AppTheme.Colors.borderSubtle)
                    
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("ПАРОЛЬ (PASS) В KEYCHAIN:", "PASSWORD (PASS) IN KEYCHAIN:"))
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
                                .font(.system(size: 13, weight: .medium))
                                .padding(8)
                                .glassSurface(shape: Circle())
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            copyToClipboard(appState.ftpPassword, notice: tr("Пароль скопирован!", "Password copied!"))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium))
                                .padding(8)
                                .glassSurface(shape: Circle())
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            appState.regenerateFTPPassword()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .medium))
                                .padding(8)
                                .glassSurface(shape: Circle(), tint: AppTheme.Colors.statusOrange)
                                .foregroundStyle(AppTheme.Colors.statusOrange)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .glassInset(cornerRadius: AppTheme.Radius.sm)
                
                // Переключатели и перезапуск FTP
                VStack(spacing: 8) {
                    Toggle(tr("Разрешить входящие соединения FTP", "Allow incoming FTP connections"), isOn: Binding(
                        get: { appState.isFTPReceivingEnabled },
                        set: { appState.toggleFTPReceiving($0) }
                    ))
                    .font(AppTheme.Typography.captionBold)
                    .tint(AppTheme.Colors.accent)
                    .padding(10)
                    .glassInset(cornerRadius: AppTheme.Radius.sm)
                    
                    Toggle(tr("Автозапуск FTP при старте программы", "Auto-start FTP on app launch"), isOn: Binding(
                        get: { appState.isFTPAutoStartEnabled },
                        set: { appState.toggleFTPAutoStart($0) }
                    ))
                    .font(AppTheme.Typography.captionBold)
                    .tint(AppTheme.Colors.accent)
                    .padding(10)
                    .glassInset(cornerRadius: AppTheme.Radius.sm)
                    
                    Button {
                        appState.restartServer()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text(tr("Перезапустить FTP-сервер", "Restart FTP Server"))
                        }
                        .font(AppTheme.Typography.captionBold)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondaryGlass)
                    .padding(.top, 4)
                }
                
                // Инструкция для меню Nikon Z
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Инструкция по настройке камеры Nikon Z:", "Nikon Z Camera Setup Guide:"))
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .padding(.top, 4)
                    
                    instructionStepRow(number: "1", text: tr("Меню сети 📡 ➔ **«Подключение к FTP-серверу»** ➔ Создать профиль.", "Network Menu 📡 ➔ **«Connect to FTP server»** ➔ Create profile."))
                    instructionStepRow(number: "2", text: tr("Укажите IP-адрес, порт, логин и пароль выше.", "Enter the IP address, port, username and password shown above."))
                    instructionStepRow(number: "3", text: tr("Включите **«Автоматическая отправка»** в меню параметров FTP.", "Enable **«Auto send»** in FTP options menu."))
                    instructionStepRow(number: "4", text: tr("Для адаптера **Nikon WT-7**: режим FTP с теми же реквизитами.", "For **Nikon WT-7** adapter: use FTP mode with the same credentials."), isSecondary: true)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    @ViewBuilder
    private var serverStateBadge: some View {
        switch appState.serverState {
        case .running(let port):
            HStack(spacing: 5) {
                Circle()
                    .fill(AppTheme.Colors.statusGreen)
                    .frame(width: 6, height: 6)
                    .shadow(color: AppTheme.Colors.statusGreen.opacity(0.8), radius: 4)
                Text(tr("Порт \(port) активен", "Port \(port) active"))
                    .font(AppTheme.Typography.caption2Bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassPill(tint: AppTheme.Colors.statusGreen)
            .foregroundStyle(AppTheme.Colors.statusGreen)
        case .starting:
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.6)
                Text(tr("Запуск...", "Starting..."))
                    .font(AppTheme.Typography.caption2Bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassPill(tint: AppTheme.Colors.statusOrange)
            .foregroundStyle(AppTheme.Colors.statusOrange)
        case .stopped:
            HStack(spacing: 5) {
                Circle()
                    .fill(AppTheme.Colors.textTertiary)
                    .frame(width: 6, height: 6)
                Text(tr("Остановлен", "Stopped"))
                    .font(AppTheme.Typography.caption2Bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassPill()
            .foregroundStyle(AppTheme.Colors.textSecondary)
        case .failed(let message):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(message)
                    .font(AppTheme.Typography.caption2Bold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassPill(tint: AppTheme.Colors.statusRed)
            .foregroundStyle(AppTheme.Colors.statusRed)
        }
    }
    
    private var toolsSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                appState.isMatrixPresented = true
            } label: {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text("Таблица совместимости моделей и форматов XMP...")
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                .padding(14)
                .glassInset(cornerRadius: AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 5. Подраздел: Параметры импорта
    
    private var importTabContent: some View {
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
                    
                    Text("Автоматически скачивать новые снимки на устройство сразу при спуске затвора камеры.")
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
        }
    }
    
    // MARK: - 6. Подраздел: Клиентский экран
    
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
                    
                    Toggle("Полупрозрачный оверлей метаданных", isOn: Binding(
                        get: { appState.clientMonitorManager.config.showSubtleOverlay },
                        set: { appState.clientMonitorManager.config.showSubtleOverlay = $0 }
                    ))
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .tint(AppTheme.Colors.accent)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            Button {
                appState.presentClientMonitor()
            } label: {
                HStack {
                    Image(systemName: "tv")
                    Text("Открыть окно клиентского монитора...")
                }
                .font(AppTheme.Typography.captionBold)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
        }
    }
    
    private var clientScreenTabContent: some View {
        clientScreenGroupContent
    }
    
    // MARK: - 7. Подраздел: Диагностика и система
    
    private var diagnosticsTabContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Файловая система
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
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(8)
                                    .glassSurface(shape: Circle())
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .glassInset(cornerRadius: AppTheme.Radius.sm)
                    }
                    
                    Text("Оригиналы никогда не перезаписываются и сохраняются в неизменном виде в хранилище приложения.")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                .padding(AppTheme.Spacing.md)
            }
            
            // Защита дискового пространства
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
            
            // База данных SQLite WAL
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
                            Text("Режим журнала:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text(stats.journalMode)
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.statusGreen)
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
            
            // Безопасная очистка кэша миниатюр в ОЗУ
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .glassPill(tint: AppTheme.Colors.statusGreen)
                    }
                    
                    Text("Очистка кэша миниатюр освобождает оперативную память устройства. Исходные файлы RAW и JPEG на диске остаются в полной сохранности.")
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
                        Button {
                            PreviewMemoryCache.shared.clear()
                            withAnimation { cacheClearedNotice = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { cacheClearedNotice = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cacheClearedNotice ? "checkmark" : "trash")
                                Text(cacheClearedNotice ? "Очищено" : "Очистить кэш ОЗУ")
                            }
                            .font(AppTheme.Typography.captionBold)
                        }
                        .buttonStyle(.appSecondaryGlass)
                    }
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
                                Image(systemName: "doc.on.doc")
                                Text("Экспорт журнала")
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
    
    // MARK: - 8. Подраздел: Сессии (при включенном флаге)
    
    private var sessionsTabContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            GlassCard(cornerRadius: AppTheme.Radius.md) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Продолжать последнюю сессию при запуске",
                        isOn: $appState.resumeLastSessionOnLaunch
                    )
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .tint(AppTheme.Colors.accent)
                    
                    Text("По умолчанию выключено: приложение начинает работу с новой пустой сессии. Если включено, при старте автоматически открывается последняя активная съемка.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
            }
            
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
                                .font(AppTheme.Typography.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .glassInset(cornerRadius: 8)
                        }
                        
                        HStack {
                            Text("Копирайт:")
                                .font(AppTheme.Typography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            TextField("© 2026 Фотограф", text: $sessionCopyrightText)
                                .font(AppTheme.Typography.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .glassInset(cornerRadius: 8)
                        }
                        
                        HStack {
                            Text("Заметка:")
                                .font(AppTheme.Typography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            TextField("Описание съемки", text: $sessionCommentText)
                                .font(AppTheme.Typography.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .glassInset(cornerRadius: 8)
                        }
                    }
                    
                    HStack {
                        if sessionMetadataSavedNotice {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Метаданные сохранены!")
                            }
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
        }
    }
    
    // MARK: - Вспомогательные методы
    
    private func instructionStepRow(number: String, text: String, isSecondary: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    )
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            
            Text(LocalizedStringKey(text))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(isSecondary ? AppTheme.Colors.textTertiary : AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
    
    private func loadDatabaseStats() {
        Task {
            let stats = await appState.fetchDatabaseStats()
            await MainActor.run {
                self.dbStats = stats
            }
        }
    }
}
