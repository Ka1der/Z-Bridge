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
                Section(header: Text("Внешний монитор (HDMI / USB-C / AirPlay)")) {
                    HStack(spacing: 12) {
                        Image(systemName: monitorManager.externalDisplayStatus.isConnected ? "tv.fill" : "tv")
                            .font(.system(size: 24))
                            .foregroundStyle(monitorManager.externalDisplayStatus.isConnected ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monitorManager.externalDisplayStatus.isConnected ? "Внешний экран подключен" : "Внешний экран не обнаружен")
                                .font(.system(size: 15, weight: .semibold))
                            
                            if case .connected(let name, let res) = monitorManager.externalDisplayStatus {
                                Text("\(name) • \(res)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Подключите кабель USB-C/HDMI или включите AirPlay")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if !monitorManager.externalDisplayStatus.isConnected {
                        Button {
                            dismiss()
                            appState.isClientMonitorPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "ipad.and.arrow.forward")
                                Text("Открыть клиентский режим на iPad")
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                
                // Секция фиксации кадра (Hold)
                Section(header: Text("Удержание кадра (Hold / Pin)")) {
                    Toggle(isOn: Binding(
                        get: { monitorManager.config.isHoldEnabled },
                        set: { monitorManager.setHold($0, for: appState.selectedGroup) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Зафиксировать текущий кадр")
                                .font(.system(size: 15, weight: .medium))
                            Text("Клиент видит выбранный кадр, пока вы продолжаете съёмку или просмотр других кадров")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if monitorManager.config.isHoldEnabled, let held = monitorManager.heldGroup {
                        HStack {
                            Text("Удерживается:")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(held.baseName)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                            
                            Button("Отпустить") {
                                monitorManager.releaseHold(latestGroup: appState.filteredGroups.first)
                            }
                            .font(.system(size: 12, weight: .bold))
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                // Секция фильтрации для клиента
                Section(
                    header: Text("Фильтрация для клиента"),
                    footer: Text("Позволяет показывать клиенту только одобренные вами кадры (Pick) или кадры с высоким рейтингом звёзд.")
                ) {
                    Picker("Режим показа", selection: $monitorManager.config.filterMode) {
                        ForEach(ClientMonitorFilterMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                }
                
                // Секция задержки переключения
                Section(
                    header: Text("Задержка переключения (Debounce)"),
                    footer: Text("Защищает от стробирования и мелькания кадров перед клиентом при быстрой серийной съёмке.")
                ) {
                    Picker("Задержка при съёмке", selection: $monitorManager.config.switchDelay) {
                        ForEach(SwitchDelayOption.allCases) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                }
                
                // Секция оверлея
                Section(header: Text("Интерфейс")) {
                    Toggle("Тонкий информационный оверлей", isOn: $monitorManager.config.showSubtleOverlay)
                    
                    if let cur = appState.selectedGroup, cur.id != monitorManager.displayedGroup?.id {
                        Button {
                            monitorManager.forcePresentGroup(cur)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.right.video")
                                Text("Показать текущий выбранный кадр на мониторе")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Клиентский монитор")
            #if os(iOS)
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
