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
        .studioBackground()
    }
    
    // MARK: - 1. Карточка статуса подключения
    
    private var connectionHeaderCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Иконка в стеклянном круге с мягким свечением
                ZStack {
                    Circle()
                        .fill(connectionStatusColor.opacity(0.12))
                        .background(.ultraThinMaterial, in: Circle())
                        .frame(width: 48, height: 48)
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
                        .shadow(color: connectionStatusColor.opacity(appState.isCameraConnected ? 0.35 : 0), radius: 8)
                    
                    Image(systemName: connectionIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(connectionStatusColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: connectionStatusColor.opacity(0.6), radius: 4)
                        
                        Text(appState.connectionStatusTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    Text(connectionSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Button {
                    appState.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .glassSurface(shape: Circle())
                }
                .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(valueColor.opacity(0.85))
                    Spacer()
                }
                
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .monospacedDigit()
                    .shadow(color: valueColor.opacity(valueColor == AppTheme.Colors.accent || valueColor == AppTheme.Colors.statusGreen ? 0.30 : 0), radius: 5)
                
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
    
    // MARK: - 4. USB-подключение и оглавление карты памяти
    
    private var usbConnectionSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "cable.connector")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(appState.usbConnected ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                        Text("Прямое подключение USB-C")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    if appState.usbConnected {
                        HStack(spacing: 5) {
                            Circle().fill(AppTheme.Colors.statusGreen).frame(width: 6, height: 6)
                                .shadow(color: AppTheme.Colors.statusGreen.opacity(0.6), radius: 3)
                            Text(appState.currentUSBManager.isCatalogReady ? "Готово к импорту" : "Подключено")
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
                            Text("Отключено")
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
                            .tint(AppTheme.Colors.accent)
                            
                            Toggle("Загружать файлы с карты при подключении", isOn: Binding(
                                get: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled },
                                set: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled = $0 }
                            ))
                            .font(AppTheme.Typography.captionBold)
                            .tint(AppTheme.Colors.accent)
                            
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
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("Беспроводная передача Wi-Fi / FTP")
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
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isServerRunning ? AppTheme.Colors.statusGreen : AppTheme.Colors.statusNeutral)
                            .frame(width: 8, height: 8)
                            .shadow(color: appState.isServerRunning ? AppTheme.Colors.statusGreen.opacity(0.6) : Color.clear, radius: 4)
                        
                        Text(appState.isServerRunning ? "Сервер работает (порт 2121)" : "Сервер остановлен")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(appState.isServerRunning ? AppTheme.Colors.statusGreen : AppTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text("Клиентов: \(appState.connectedClients)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(appState.connectedClients > 0 ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .background(.ultraThinMaterial, in: Capsule())
                            )
                            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    }
                    
                    if appState.isServerRunning {
                        Text(appState.connectedClients > 0 ? "Идёт приём снимков при съёмке (push-режим камеры)." : "Ожидание отправки снимков с камеры (push-режим).")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                
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
                            .font(.system(size: 13, weight: .semibold))
                        Text("Настройки Wi-Fi и реквизиты FTP...")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.25))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
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
                        .font(.system(size: 13, weight: .semibold))
                    Text("Таблица совместимости форматов XMP...")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}
