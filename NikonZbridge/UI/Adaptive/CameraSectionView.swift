import SwiftUI

/// Экран раздела «Камера» в адаптивном каркасе Liquid Glass.
/// Объединяет управление USB-подключением, FTP/Wi-Fi сервером,
/// метрики передачи, компактную плашку прогресса и быстрый переход к карте памяти.
public struct CameraSectionView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 1. Верхняя карточка статуса подключения
                connectionHeaderCard
                
                // 2. Компактная плашка прогресса передачи (при наличии активного задания или очереди)
                if appState.activeTransferJob != nil || appState.activeQueueCount > 0 {
                    progressStripSection
                }
                
                // 3. Метрики передачи (камера, реальная скорость, принятые кадры)
                metricsRow
                
                // 4. Блок прямого USB-подключения и параметров карты памяти
                usbConnectionSection
                
                // 5. Блок Wi-Fi и FTP-сервера (push-режим)
                wifiFtpSection
                
                // 6. Помощники и документация
                toolsSection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background)
    }
    
    // MARK: - 1. Карточка статуса подключения
    
    private var connectionHeaderCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(connectionStatusColor.opacity(0.18))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: connectionIcon)
                        .font(.title2)
                        .foregroundStyle(connectionStatusColor)
                }
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(appState.connectionStatusTitle)
                        .font(AppTheme.Typography.title3)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Text(connectionSubtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Button {
                    appState.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.bold())
                }
                .buttonStyle(.appIconGlass)
                .accessibilityLabel("Настройки подключения")
            }
            .padding(AppTheme.Spacing.md)
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
            return appState.usbCameraName ?? "Nikon Z (USB)"
        } else if appState.isServerRunning {
            return "FTP: порт 2121 • Клиентов: \(appState.connectedClients)"
        } else {
            return "Ожидание подключения по кабелю или Wi-Fi"
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
    
    // MARK: - 3. Метрики передачи (референс)
    
    private var metricsRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Камера
            metricTile(
                icon: "camera",
                value: appState.isCameraConnected ? "Подключено" : "Ожидание",
                label: "Камера",
                valueColor: appState.isCameraConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.textPrimary
            )
            
            // Реальная скорость
            metricTile(
                icon: "bolt.horizontal",
                value: appState.currentTransferSpeedMBs > 0.05
                    ? String(format: "%.1f МБ/с", appState.currentTransferSpeedMBs)
                    : "0 МБ/с",
                label: "Скорость",
                valueColor: appState.currentTransferSpeedMBs > 0.05 ? AppTheme.Colors.statusGreen : AppTheme.Colors.textPrimary
            )
            
            // Получено кадров
            metricTile(
                icon: "photo.stack",
                value: "\(appState.totalFramesCount)",
                label: "Получено",
                valueColor: AppTheme.Colors.accent
            )
        }
    }
    
    private func metricTile(icon: String, value: String, label: String, valueColor: Color) -> some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                
                Text(value)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .monospacedDigit()
                
                Text(label)
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 4. USB-подключение и оглавление карты памяти
    
    private var usbConnectionSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Label("Прямое подключение USB-C", systemImage: "cable.connector")
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                    
                    if appState.usbConnected {
                        Text(appState.currentUSBManager.isCatalogReady ? "Готово к импорту" : "Подключено")
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.statusGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.Colors.statusGreen.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Text("Отключено")
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.Colors.surfaceSecondary)
                            .clipShape(Capsule())
                    }
                }
                
                if appState.usbConnected {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        // Модель камеры
                        HStack(spacing: 6) {
                            Text("Модель камеры:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(appState.usbCameraName ?? "Nikon Z")
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        
                        // Целевая сессия
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text(AppFeatures.sessionManagementEnabled ? "Целевая сессия:" : "Сохранение:")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(AppFeatures.sessionManagementEnabled ? (appState.currentSession?.name ?? "Основная сессия") : "На это устройство")
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
                                Text("Чтение оглавления карты памяти...")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Файлов на карте: \(stats.totalCount) (\(stats.formattedTotalSize))")
                                    .font(AppTheme.Typography.captionBold)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                
                                if stats.unimportedCount > 0 {
                                    Text("Доступно для импорта: \(stats.unimportedCount) новых (\(stats.formattedUnimportedSize))")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.accent)
                                } else {
                                    Text("Все файлы на карте уже загружены на устройство")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.statusGreen)
                                }
                            }
                        }
                        
                        Divider()
                            .background(AppTheme.Colors.borderSubtle)
                        
                        // Независимые настройки автозагрузки
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Toggle("Автоматически загружать новые кадры", isOn: Binding(
                                get: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled },
                                set: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled = $0 }
                            ))
                            .font(AppTheme.Typography.captionBold)
                            
                            Toggle("Загружать файлы с карты при подключении", isOn: Binding(
                                get: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled },
                                set: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled = $0 }
                            ))
                            .font(AppTheme.Typography.captionBold)
                            
                            Text("Ручной импорт не изменяет эти настройки. Параметры сохраняются между запусками.")
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                        .padding(.vertical, 2)
                        
                        // Кнопка перехода к экрану импорта
                        Button {
                            appState.isUSBBrowserPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "folder.badge.gearshape")
                                Text(stats.unimportedCount > 0 ? "Открыть карту памяти (\(stats.unimportedCount) новых)..." : "Открыть карту памяти камеры...")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appPrimary)
                        .disabled(!appState.currentUSBManager.isCatalogReady)
                    }
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Подключите камеру Nikon Z кабелем USB-C к устройству для прямого импорта и быстрого чтения карты памяти.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                            Text("Поддерживаются Z 9, Z 8, Z 7 II, Z 6 III, Z 6 II, Z 5, Z f, Z 50, Z 30, Z fc.")
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 5. Wi-Fi и FTP сервер (push-режим)
    
    private var wifiFtpSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Label("Беспроводная передача Wi-Fi / FTP", systemImage: "wifi")
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
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
                }
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isServerRunning ? AppTheme.Colors.statusGreen : AppTheme.Colors.statusNeutral)
                            .frame(width: 8, height: 8)
                        Text(appState.isServerRunning ? "Сервер работает (порт 2121)" : "Сервер остановлен")
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(appState.isServerRunning ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text("Клиентов: \(appState.connectedClients)")
                            .font(AppTheme.Typography.captionBold)
                            .foregroundStyle(appState.connectedClients > 0 ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                    }
                    
                    if appState.isServerRunning {
                        Text(appState.connectedClients > 0 ? "Идёт приём снимков при съёмке (push-режим камеры)." : "Ожидание отправки снимков с камеры (push-режим).")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                
                // Важное пояснение для пользователя: не обещаем просмотр карты через существующий FTP-сервер
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .padding(.top, 1)
                    Text("FTP-сервер приложения принимает фотографии по мере спуска затвора камеры. Просмотр файлов на карте памяти доступен только при подключении по USB-C.")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                
                Button {
                    appState.isSettingsPresented = true
                } label: {
                    HStack {
                        Image(systemName: "wifi.badge.questionmark")
                        Text("Настройки Wi-Fi и реквизиты FTP...")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(AppTheme.Typography.captionBold)
                }
                .buttonStyle(.appSecondaryGlass)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 6. Инструменты и совместимость
    
    private var toolsSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                appState.isMatrixPresented = true
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Таблица совместимости форматов XMP...")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appSecondaryGlass)
        }
    }
}
