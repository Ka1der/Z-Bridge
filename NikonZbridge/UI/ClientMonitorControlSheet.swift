import SwiftUI

/// Панель управления клиентским монитором для фотографа
public struct ClientMonitorControlSheet: View {
    @ObservedObject var monitorManager: ClientMonitorManager
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    public init(monitorManager: ClientMonitorManager, appState: AppState) {
        self.monitorManager = monitorManager
        self.appState = appState
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Секция статуса внешнего монитора
                Section(header: Text(tr("Внешний монитор (HDMI / USB-C / AirPlay)", "External Monitor (HDMI / USB-C / AirPlay)"))) {
                    HStack(spacing: 12) {
                        Image(systemName: monitorManager.externalDisplayStatus.isConnected ? "tv.fill" : "tv")
                            .font(.system(size: 24))
                            .foregroundStyle(monitorManager.externalDisplayStatus.isConnected ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monitorManager.externalDisplayStatus.isConnected ? tr("Внешний экран подключен", "External display connected") : tr("Внешний экран не обнаружен", "No external display detected"))
                                .font(.system(size: 15, weight: .semibold))
                            
                            if case .connected(let name, let res) = monitorManager.externalDisplayStatus {
                                Text("\(name) • \(res)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(tr("Подключите кабель USB-C/HDMI или включите AirPlay", "Connect via USB-C/HDMI or turn on AirPlay"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if !monitorManager.externalDisplayStatus.isConnected && !appState.isClientMonitorPresented {
                        Button {
                            appState.presentClientMonitor()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text(tr("Открыть клиентский экран на этом устройстве", "Open Client Monitor on this device"))
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                }
                
                // Секция фиксации кадра (Hold)
                Section(header: Text(tr("Удержание кадра (Hold / Pin)", "Frame Freeze (Hold / Pin)"))) {
                    Toggle(isOn: Binding(
                        get: { monitorManager.config.isHoldEnabled },
                        set: { monitorManager.setHold($0, for: appState.selectedGroup, file: appState.selectedCameraFile) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Зафиксировать текущий кадр", "Freeze current frame"))
                                .font(.system(size: 15, weight: .medium))
                            Text(tr("Клиент видит выбранный кадр, пока вы продолжаете съёмку или просмотр других кадров", "Client continues seeing the frozen frame while you shoot or browse"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if monitorManager.config.isHoldEnabled {
                        let heldName = monitorManager.heldGroup?.baseName ?? monitorManager.heldCameraFile?.filename ?? tr("Выбранный кадр", "Selected frame")
                        HStack {
                            Text(tr("Удерживается:", "Frozen:"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(heldName)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                            
                            Button(tr("Отпустить", "Release")) {
                                monitorManager.releaseHold(
                                    latestGroup: appState.filteredGroups.first,
                                    latestFile: appState.currentUSBManager.catalogFiles.last
                                )
                            }
                            .font(.system(size: 12, weight: .bold))
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                // Секция фильтрации для клиента
                Section(
                    header: Text(tr("Фильтрация для клиента", "Client Filtering")),
                    footer: Text(tr("Позволяет показывать клиенту только одобренные вами кадры (Pick) или кадры с высоким рейтингом звёзд.", "Shows only approved photos (Pick) or photos with a specific star rating."))
                ) {
                    Picker(tr("Режим показа", "Display Mode"), selection: $monitorManager.config.filterMode) {
                        ForEach(ClientMonitorFilterMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                }
                
                // Секция задержки переключения
                Section(
                    header: Text(tr("Задержка переключения (Debounce)", "Switch Delay (Debounce)")),
                    footer: Text(tr("Защищает от стробирования и мелькания кадров перед клиентом при быстрой серийной съёмке.", "Prevents flickering when shooting rapid bursts."))
                ) {
                    Picker(tr("Задержка при съёмке", "Delay while shooting"), selection: $monitorManager.config.switchDelay) {
                        ForEach(SwitchDelayOption.allCases) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                }
                
                // Секция оверлея
                Section(header: Text(tr("Интерфейс", "Interface"))) {
                    Toggle(tr("Тонкий информационный оверлей", "Subtle info overlay"), isOn: $monitorManager.config.showSubtleOverlay)
                    
                    if let cur = appState.selectedGroup, cur.id != monitorManager.displayedGroup?.id {
                        Button {
                            monitorManager.forcePresentGroup(cur)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.right.video")
                                Text(tr("Показать текущий выбранный кадр на мониторе", "Show currently selected frame on monitor"))
                            }
                        }
                    } else if let curFile = appState.selectedCameraFile, curFile.id != monitorManager.displayedCameraFile?.id {
                        Button {
                            monitorManager.forcePresentCameraFile(curFile)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.right.video")
                                Text(tr("Показать текущий снимок с камеры на мониторе", "Show current camera photo on monitor"))
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("Клиентский монитор", "Client Monitor"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Готово", "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
