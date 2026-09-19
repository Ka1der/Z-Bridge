import SwiftUI

public struct NikonTetherRootView: View {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingConnectionSheet = false
    @State private var isShowingSessionSheet = false
    @State private var isShowingClearAlert = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. ВЕРХНЯЯ ПАНЕЛЬ (HUD): Статус камеры, IP/Кабель, Скорость, Настройки
                topHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                
                if case .accessDenied(let reason) = appState.usbConnectionState {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(6)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                
                // 2. ПАНЕЛЬ РЕЖИМОВ ОТОБРАЖЕНИЯ (Селектор: Просмотр / Иконки / Список / Таблица)
                viewModeSelector
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                
                // 3. ПАНЕЛЬ ФИЛЬТРАЦИИ И ДЕЙСТВИЙ (Галочки RAW, JPG, Автопросмотр, Очистить)
                filterAndActionsBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                
                Divider()
                    .background(Color.white.opacity(0.12))
                
                // 4. ОСНОВНОЙ КОНТЕНТ (В зависимости от выбранного режима)
                mainContentArea
            }
            
            // Всплывающее уведомление о новом кадре при активной инспекции
            if let notification = appState.pendingIncomingFrameNotification {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.green)
                        Text(notification)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Button {
                            appState.switchToPendingGroup()
                        } label: {
                            Text("Показать")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        
                        Button {
                            appState.dismissPendingNotification()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 45)
                    
                    Spacer()
                }
            }
            
            // Плавающая панель массовых действий при множественном выборе
            if appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
                VStack {
                    Spacer()
                    batchActionBar
                        .padding(.bottom, 16)
                }
            }
            
            // Невидимые триггеры аппаратной клавиатуры iPad
            keyboardShortcutsView
        }
        .sheet(isPresented: $isShowingConnectionSheet) {
            ConnectionSheetView(appState: appState)
        }
        .sheet(isPresented: $isShowingSessionSheet) {
            SessionManagementSheetView(appState: appState)
        }
        .sheet(isPresented: $appState.isUSBBrowserPresented) {
            USBCameraBrowserView(usbManager: appState.currentUSBManager)
        }
        .sheet(isPresented: $appState.isQueuePresented) {
            TransferQueueView(appState: appState)
        }
        .sheet(isPresented: $appState.isWizardPresented) {
            ConnectionWizardView(appState: appState)
        }
        .sheet(isPresented: $appState.isMatrixPresented) {
            CompatibilityMatrixView()
        }
        .sheet(isPresented: $appState.isComparePresented) {
            CompareView(appState: appState, initialGroupA: appState.selectedGroup, initialGroupB: appState.compareCandidateGroup)
        }
        .sheet(isPresented: $appState.isExportSheetPresented) {
            ExportSheetView(appState: appState, groups: appState.exportTargetGroups)
        }
        .sheet(isPresented: $appState.isClientControlSheetPresented) {
            ClientMonitorControlSheet(monitorManager: appState.clientMonitorManager, appState: appState)
        }
        .fullScreenCover(isPresented: $appState.isClientMonitorPresented) {
            ClientMonitorView(monitorManager: appState.clientMonitorManager, appState: appState)
        }
        .onChange(of: scenePhase) { newPhase in
            appState.handleScenePhaseChange(newPhase)
        }
        .alert("Очистить все снимки?", isPresented: $isShowingClearAlert) {
            Button("Очистить", role: .destructive) {
                appState.clearGallery()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
    
    // MARK: - Клавиатурные команды iPad
    
    @ViewBuilder
    private var keyboardShortcutsView: some View {
        ZStack {
            // Рейтинг 0..5
            Button("") { applyRating(0) }.keyboardShortcut("0", modifiers: [])
            Button("") { applyRating(1) }.keyboardShortcut("1", modifiers: [])
            Button("") { applyRating(2) }.keyboardShortcut("2", modifiers: [])
            Button("") { applyRating(3) }.keyboardShortcut("3", modifiers: [])
            Button("") { applyRating(4) }.keyboardShortcut("4", modifiers: [])
            Button("") { applyRating(5) }.keyboardShortcut("5", modifiers: [])
            
            // Флаги: P (Pick), X (Reject), U (Unflag)
            Button("") { applyPickStatus(.picked) }.keyboardShortcut("p", modifiers: [])
            Button("") { applyPickStatus(.rejected) }.keyboardShortcut("x", modifiers: [])
            Button("") { applyPickStatus(.unflagged) }.keyboardShortcut("u", modifiers: [])
            
            // Навигация
            Button("") { appState.selectPreviousGroup() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { appState.selectNextGroup() }.keyboardShortcut(.rightArrow, modifiers: [])
            
            // Зум и сравнение
            Button("") { appState.isUserInspecting.toggle() }.keyboardShortcut(.space, modifiers: [])
            Button("") { appState.isUserInspecting.toggle() }.keyboardShortcut("z", modifiers: [])
            Button("") {
                if let sel = appState.selectedGroup ?? appState.filteredGroups.first {
                    appState.compareCandidateGroup = appState.filteredGroups.first(where: { $0.id != sel.id }) ?? sel
                    appState.isComparePresented.toggle()
                }
            }.keyboardShortcut("c", modifiers: [])
            
            // Клиентский монитор: H (Hold / Удержание), M (Monitor / Показ)
            Button("") { appState.toggleClientMonitorHold() }.keyboardShortcut("h", modifiers: [])
            Button("") { appState.presentClientMonitor() }.keyboardShortcut("m", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
    
    private func applyRating(_ rating: Int) {
        if appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
            appState.batchSetRating(rating)
        } else if let sel = appState.selectedGroup {
            appState.setRating(rating, for: sel)
        }
    }
    
    private func applyPickStatus(_ status: PickStatus) {
        if appState.isSelectionMode && !appState.selectedGroupIDs.isEmpty {
            appState.batchSetPickStatus(status)
        } else if let sel = appState.selectedGroup {
            appState.setPickStatus(status, for: sel)
        }
    }
    
    // MARK: - Batch Action Bar
    
    private var batchActionBar: some View {
        HStack(spacing: 12) {
            Text("Выбрано: \(appState.selectedGroupIDs.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))
            
            // Быстрый рейтинг для выбранных
            HStack(spacing: 4) {
                Button("0") { appState.batchSetRating(0) }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                
                ForEach(1...5, id: \.self) { star in
                    Button("★\(star)") { appState.batchSetRating(star) }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))
            
            // Флаги отбора для выбранных
            HStack(spacing: 6) {
                Button {
                    appState.batchSetPickStatus(.picked)
                } label: {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                        .padding(5)
                        .background(Color.green.opacity(0.2))
                        .clipShape(Circle())
                }
                
                Button {
                    appState.batchSetPickStatus(.rejected)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.red)
                        .padding(5)
                        .background(Color.red.opacity(0.2))
                        .clipShape(Circle())
                }
                
                Button {
                    appState.batchSetPickStatus(.unflagged)
                } label: {
                    Image(systemName: "flag.slash")
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))
            
            Button("Все") {
                appState.selectAll()
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            
            Button("Снять") {
                appState.clearSelection()
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))
            
            Button {
                appState.presentExportForSelected()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Экспорт")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            
            Button(role: .destructive) {
                appState.batchDeleteSelected()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(5)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 8)
    }
    
    // MARK: - Top HUD
    
    private var topHUD: some View {
        HStack(spacing: 8) {
            // Кнопка сессии
            Button {
                isShowingSessionSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(appState.currentSession?.name ?? "Сессия")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            
            // Кнопка статуса подключения камеры
            Button {
                isShowingConnectionSheet = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isCameraConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(appState.connectionStatusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            
            // Кнопка браузера карты памяти камеры по USB
            if appState.usbConnected {
                Button {
                    appState.isUSBBrowserPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sdcard")
                            .font(.system(size: 11))
                        Text("Карта")
                            .font(.system(size: 12, weight: .bold))
                        let count = appState.currentUSBManager.catalogFiles.count
                        if count > 0 {
                            Text("(\(count))")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.35))
                    .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Индикатор активного сетевого адреса (IP и порт)
            Button {
                isShowingConnectionSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.usbConnected ? "cable.connector" : "wifi")
                        .font(.system(size: 12))
                        .foregroundStyle(appState.usbConnected ? .green : .blue)
                    if appState.usbConnected {
                        Text("USB")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                    } else if let primary = appState.primaryIP {
                        Text("\(primary.ipAddress):\(appState.serverPort)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    } else {
                        Text("Нет сети")
                            .font(.system(size: 12))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            
            // Моментальная скорость передачи
            if appState.currentTransferSpeedMBs > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text(String(format: "%.0f МБ/с", appState.currentTransferSpeedMBs))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
            }
            
            // Кнопка очереди переноса (Этап 6)
            Button {
                appState.isQueuePresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 12))
                    if appState.activeQueueCount > 0 {
                        Text("\(appState.activeQueueCount)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            
            // Кнопка клиентского монитора (Этап 11)
            Button {
                appState.presentClientControlSheet()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: appState.clientMonitorManager.externalDisplayStatus.isConnected ? "tv.fill" : "tv")
                        .font(.system(size: 12))
                        .foregroundStyle(appState.clientMonitorManager.externalDisplayStatus.isConnected ? Color.green : (appState.clientMonitorManager.config.isHoldEnabled ? Color.orange : Color.white))
                    
                    if appState.clientMonitorManager.config.isHoldEnabled {
                        Text("HOLD")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    } else if appState.clientMonitorManager.externalDisplayStatus.isConnected {
                        Text("HDMI")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        Text("Клиент")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(appState.clientMonitorManager.config.isHoldEnabled ? Color.orange.opacity(0.18) : Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            
            // Кнопка настроек
            Button {
                isShowingConnectionSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
    }
    
    // MARK: - View Mode Selector
    
    private var viewModeSelector: some View {
        Picker("Вид", selection: $appState.viewMode) {
            ForEach(ViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Filter & Actions Bar
    
    private var filterAndActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Фильтр RAW
                Button {
                    appState.toggleRAW()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.showRAW ? "checkmark.square.fill" : "square")
                            .foregroundStyle(appState.showRAW ? Color.orange : Color.secondary)
                            .font(.system(size: 14))
                        Text("RAW")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(appState.showRAW ? .white : .secondary)
                        Text("(\(appState.rawCount))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(appState.showRAW ? 0.12 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Фильтр JPG
                Button {
                    appState.toggleJPG()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.showJPG ? "checkmark.square.fill" : "square")
                            .foregroundStyle(appState.showJPG ? Color.blue : Color.secondary)
                            .font(.system(size: 14))
                        Text("JPG")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(appState.showJPG ? .white : .secondary)
                        Text("(\(appState.jpgCount))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(appState.showJPG ? 0.12 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Фильтр HEIF
                if appState.heifCount > 0 {
                    Button {
                        appState.toggleHEIF()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: appState.showHEIF ? "checkmark.square.fill" : "square")
                                .foregroundStyle(appState.showHEIF ? Color.purple : Color.secondary)
                                .font(.system(size: 14))
                            Text("HEIF")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(appState.showHEIF ? .white : .secondary)
                            Text("(\(appState.heifCount))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(appState.showHEIF ? 0.12 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                // Фильтр «Только пары RAW+JPG»
                if appState.pairedCount > 0 {
                    Button {
                        appState.toggleOnlyPaired()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: appState.onlyPaired ? "link.circle.fill" : "link.circle")
                                .foregroundStyle(appState.onlyPaired ? Color.green : Color.secondary)
                                .font(.system(size: 14))
                            Text("Пары")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(appState.onlyPaired ? .white : .secondary)
                            Text("(\(appState.pairedCount))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(appState.onlyPaired ? 0.15 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.2))
                
                // Сортировка
                Menu {
                    Picker("Сортировка", selection: $appState.sortOrder) {
                        ForEach(SortOrderOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(appState.sortOrder.title)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Фильтр по рейтингу
                Menu {
                    Picker("Рейтинг", selection: $appState.ratingFilter) {
                        ForEach(RatingFilterOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.ratingFilter == .all ? "star" : "star.fill")
                            .foregroundStyle(appState.ratingFilter == .all ? Color.secondary : Color.yellow)
                        Text(appState.ratingFilter.title)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appState.ratingFilter == .all ? Color.secondary : Color.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(appState.ratingFilter == .all ? 0.04 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Фильтр по флагу отбора
                Menu {
                    Picker("Отбор", selection: $appState.pickFilter) {
                        ForEach(PickFilterOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.pickFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(appState.pickFilter == .all ? Color.secondary : Color.green)
                        Text(appState.pickFilter.title)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appState.pickFilter == .all ? Color.secondary : Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(appState.pickFilter == .all ? 0.04 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.2))
                
                // Кнопка режима множественного выбора
                Button {
                    withAnimation {
                        appState.isSelectionMode.toggle()
                        if !appState.isSelectionMode {
                            appState.clearSelection()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(appState.isSelectionMode ? "Готово" : "Выбрать")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appState.isSelectionMode ? Color.blue : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(appState.isSelectionMode ? 0.18 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Кнопка сравнения двух кадров
                Button {
                    if let sel = appState.selectedGroup ?? appState.filteredGroups.first {
                        appState.compareCandidateGroup = appState.filteredGroups.first(where: { $0.id != sel.id }) ?? sel
                        appState.isComparePresented = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.split.2x1")
                        Text("Сравнить")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Кнопка экспорта всей сессии
                Button {
                    appState.presentExportForSession()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Экспорт")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Переключатель «Автопросмотр»
                Button {
                    appState.isAutoScrollEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isAutoScrollEnabled ? "bolt.circle.fill" : "bolt.circle")
                        Text("Автопросмотр")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appState.isAutoScrollEnabled ? Color.blue : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(appState.isAutoScrollEnabled ? 0.12 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Кнопка очистки
                Button(role: .destructive) {
                    isShowingClearAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // MARK: - Main Content Area
    
    @ViewBuilder
    private var mainContentArea: some View {
        if appState.captureGroups.isEmpty && appState.receivedFiles.isEmpty {
            waitingPlaceholder
        } else if appState.filteredGroups.isEmpty && appState.filteredFiles.isEmpty {
            emptyFilteredPlaceholder
        } else {
            switch appState.viewMode {
            case .viewer:
                viewerView
            case .icons:
                IconsGridView(
                    groups: appState.filteredGroups,
                    selectedGroup: appState.selectedGroup,
                    isSelectionMode: appState.isSelectionMode,
                    selectedGroupIDs: appState.selectedGroupIDs,
                    onToggleSelect: { group in
                        appState.toggleSelectGroup(group)
                    }
                ) { group in
                    appState.selectedGroup = group
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .viewer
                    }
                }
            case .list:
                PhotoListView(
                    groups: appState.filteredGroups,
                    selectedGroup: appState.selectedGroup,
                    isSelectionMode: appState.isSelectionMode,
                    selectedGroupIDs: appState.selectedGroupIDs,
                    onToggleSelect: { group in
                        appState.toggleSelectGroup(group)
                    }
                ) { group in
                    appState.selectedGroup = group
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .viewer
                    }
                }
            case .table:
                PhotoTableView(
                    groups: appState.filteredGroups,
                    selectedGroup: appState.selectedGroup,
                    isSelectionMode: appState.isSelectionMode,
                    selectedGroupIDs: appState.selectedGroupIDs,
                    onToggleSelect: { group in
                        appState.toggleSelectGroup(group)
                    }
                ) { group in
                    appState.selectedGroup = group
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.viewMode = .viewer
                    }
                }
            }
        }
    }
    
    // MARK: - Mode 1: Viewer
    
    private var viewerView: some View {
        VStack(spacing: 0) {
            if let currentGroup = appState.selectedGroup ?? appState.filteredGroups.first {
                PhotoDetailView(group: currentGroup, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let currentFile = appState.selectedFile ?? appState.filteredFiles.first {
                PhotoDetailView(file: currentFile, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            bottomFilmstrip
        }
    }
    
    // MARK: - Bottom Filmstrip
    
    private var bottomFilmstrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(appState.filteredGroups.count) из \(appState.totalFramesCount) кадров")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                if appState.pairedCount > 0 {
                    Text("• \(appState.pairedCount) пар")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                Spacer()
                
                // Переключатель «Автопросмотр» в нижней панели
                Button {
                    appState.isAutoScrollEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isAutoScrollEnabled ? "bolt.circle.fill" : "bolt.circle")
                        Text("Автопросмотр")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(appState.isAutoScrollEnabled ? .blue : .secondary)
                }
            }
            .padding(.horizontal, 16)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(appState.filteredGroups) { group in
                            FilmstripTile(
                                group: group,
                                isSelected: appState.selectedGroup?.id == group.id
                            )
                            .id(group.id)
                            .onTapGesture {
                                appState.selectedGroup = group
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 72)
                .onChange(of: appState.filteredGroups.first?.id) { _, newID in
                    if appState.isAutoScrollEnabled, let id = newID {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .leading)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }
    
    // MARK: - Placeholders
    
    private var waitingPlaceholder: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 140, height: 140)
                
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            VStack(spacing: 10) {
                Text("Готов к приему снимков")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "cable.connector")
                            .foregroundStyle(.green)
                        Text("По проводу: USB ➔ «Передача файлов» (без FTP!)")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    if let ip = appState.primaryIP?.ipAddress {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi")
                                .foregroundStyle(.blue)
                            Text("По воздуху: Wi-Fi FTP ➔ \(ip):\(appState.serverPort)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Button {
                isShowingConnectionSheet = true
            } label: {
                Text("Инструкция подключения")
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyFilteredPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 50, weight: .thin))
                .foregroundStyle(.secondary)
            
            Text("Нет снимков выбранного формата")
                .font(.headline)
                .foregroundStyle(.white)
            
            Text("Включите галочки RAW или JPG в строке фильтрации сверху.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                appState.showRAW = true
                appState.showJPG = true
            } label: {
                Text("Показать все форматы")
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mode 2: Icons Grid View

struct IconsGridView: View {
    let groups: [CaptureGroup]
    let selectedGroup: CaptureGroup?
    var isSelectionMode: Bool = false
    var selectedGroupIDs: Set<String> = []
    var onToggleSelect: ((CaptureGroup) -> Void)? = nil
    let onSelect: (CaptureGroup) -> Void
    
    init(
        groups: [CaptureGroup],
        selectedGroup: CaptureGroup? = nil,
        isSelectionMode: Bool = false,
        selectedGroupIDs: Set<String> = [],
        onToggleSelect: ((CaptureGroup) -> Void)? = nil,
        onSelect: @escaping (CaptureGroup) -> Void
    ) {
        self.groups = groups
        self.selectedGroup = selectedGroup
        self.isSelectionMode = isSelectionMode
        self.selectedGroupIDs = selectedGroupIDs
        self.onToggleSelect = onToggleSelect
        self.onSelect = onSelect
    }
    
    init(
        files: [IngestedFile],
        selectedFile: IngestedFile? = nil,
        onSelect: @escaping (IngestedFile) -> Void
    ) {
        self.groups = files.map { file in
            if let asset = file.mediaAsset {
                return CaptureGroup(asset: asset)
            }
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            return CaptureGroup(asset: asset)
        }
        self.selectedGroup = groups.first
        self.isSelectionMode = false
        self.selectedGroupIDs = []
        self.onToggleSelect = nil
        self.onSelect = { group in
            if let first = group.primaryAsset {
                onSelect(IngestedFile(from: first))
            }
        }
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 8)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(groups) { group in
                    IconGridCard(
                        group: group,
                        isSelected: isSelectionMode ? selectedGroupIDs.contains(group.id) : (selectedGroup?.id == group.id),
                        isSelectionMode: isSelectionMode
                    )
                    .onTapGesture {
                        if isSelectionMode {
                            onToggleSelect?(group)
                        } else {
                            onSelect(group)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct IconGridCard: View {
    let group: CaptureGroup
    let isSelected: Bool
    var isSelectionMode: Bool = false
    @State private var previewState: PreviewState = .idle
    
    init(group: CaptureGroup, isSelected: Bool, isSelectionMode: Bool = false) {
        self.group = group
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
    }
    
    init(file: IngestedFile, isSelected: Bool) {
        if let asset = file.mediaAsset {
            self.group = CaptureGroup(asset: asset)
        } else {
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            self.group = CaptureGroup(asset: asset)
        }
        self.isSelected = isSelected
        self.isSelectionMode = false
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.white.opacity(0.06)
                    switch previewState {
                    case .success(let img):
                        #if canImport(UIKit)
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #elseif canImport(AppKit)
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #endif
                    case .loading, .idle:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .failure(let error):
                        VStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 16))
                                .foregroundStyle(.orange)
                            Text("Ошибка")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Button {
                                loadThumbnail()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .frame(height: 105)
                .clipped()
                
                // Верхний левый угол: индикатор выбора или флаг отбора
                VStack {
                    HStack {
                        if isSelectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(isSelected ? Color.blue : Color.white.opacity(0.8))
                                .background(Circle().fill(Color.black.opacity(0.5)))
                                .padding(4)
                        } else if group.pickStatus == .picked {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.green)
                                .clipShape(Circle())
                                .padding(4)
                        } else if group.pickStatus == .rejected {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .padding(4)
                        }
                        
                        Spacer()
                    }
                    Spacer()
                }
                
                // Бейдж формата кадра
                Text(group.formatBadge)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(badgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(group.baseName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if group.rating > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text("\(group.rating)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                
                HStack {
                    Text(group.formattedTotalSize)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let primary = group.primaryAsset {
                        Text(primary.formattedTime)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(Color.white.opacity(isSelected ? 0.15 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 300)
                }
            }
        }
    }
    
    private var badgeColor: Color {
        if group.hasBothRawAndJpeg {
            return Color.green
        } else if group.rawAsset != nil {
            return Color.orange
        } else if group.heifAsset != nil {
            return Color.purple
        } else {
            return Color.blue
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 300)
            if Task.isCancelled { return }
            switch result {
            case .success(let img):
                previewState = .success(img)
            case .failure(let err):
                if err != .cancelled {
                    previewState = .failure(err)
                }
            }
        }
    }
}

// MARK: - Mode 3: Photo List View

struct PhotoListView: View {
    let groups: [CaptureGroup]
    let selectedGroup: CaptureGroup?
    var isSelectionMode: Bool = false
    var selectedGroupIDs: Set<String> = []
    var onToggleSelect: ((CaptureGroup) -> Void)? = nil
    let onSelect: (CaptureGroup) -> Void
    
    init(
        groups: [CaptureGroup],
        selectedGroup: CaptureGroup? = nil,
        isSelectionMode: Bool = false,
        selectedGroupIDs: Set<String> = [],
        onToggleSelect: ((CaptureGroup) -> Void)? = nil,
        onSelect: @escaping (CaptureGroup) -> Void
    ) {
        self.groups = groups
        self.selectedGroup = selectedGroup
        self.isSelectionMode = isSelectionMode
        self.selectedGroupIDs = selectedGroupIDs
        self.onToggleSelect = onToggleSelect
        self.onSelect = onSelect
    }
    
    init(
        files: [IngestedFile],
        selectedFile: IngestedFile? = nil,
        onSelect: @escaping (IngestedFile) -> Void
    ) {
        self.groups = files.map { file in
            if let asset = file.mediaAsset {
                return CaptureGroup(asset: asset)
            }
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            return CaptureGroup(asset: asset)
        }
        self.selectedGroup = groups.first
        self.isSelectionMode = false
        self.selectedGroupIDs = []
        self.onToggleSelect = nil
        self.onSelect = { group in
            if let first = group.primaryAsset {
                onSelect(IngestedFile(from: first))
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(groups) { group in
                    PhotoListRow(
                        group: group,
                        isSelected: isSelectionMode ? selectedGroupIDs.contains(group.id) : (selectedGroup?.id == group.id),
                        isSelectionMode: isSelectionMode
                    )
                    .onTapGesture {
                        if isSelectionMode {
                            onToggleSelect?(group)
                        } else {
                            onSelect(group)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct PhotoListRow: View {
    let group: CaptureGroup
    let isSelected: Bool
    var isSelectionMode: Bool = false
    @State private var previewState: PreviewState = .idle
    
    init(group: CaptureGroup, isSelected: Bool, isSelectionMode: Bool = false) {
        self.group = group
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
    }
    
    init(file: IngestedFile, isSelected: Bool) {
        if let asset = file.mediaAsset {
            self.group = CaptureGroup(asset: asset)
        } else {
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            self.group = CaptureGroup(asset: asset)
        }
        self.isSelected = isSelected
        self.isSelectionMode = false
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Чекбокс выбора
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
            }
            
            // Превью
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Color.white.opacity(0.06)
                    switch previewState {
                    case .success(let img):
                        #if canImport(UIKit)
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #elseif canImport(AppKit)
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #endif
                    case .loading, .idle:
                        ProgressView()
                            .scaleEffect(0.6)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 58, height: 58)
                .clipped()
                
                Text(group.formatBadge)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(group.hasBothRawAndJpeg ? Color.green : (group.rawAsset != nil ? Color.orange : Color.blue))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Метаданные
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.baseName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    
                    if group.pickStatus == .picked {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else if group.pickStatus == .rejected {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    
                    if group.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...group.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                
                HStack(spacing: 8) {
                    if let primary = group.primaryAsset {
                        Label(primary.formattedTime, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(group.availableOriginalsSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Размер и переход
            VStack(alignment: .trailing, spacing: 4) {
                Text(group.formattedTotalSize)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(isSelected ? 0.12 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 180)
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 180)
            if Task.isCancelled { return }
            switch result {
            case .success(let img):
                previewState = .success(img)
            case .failure(let err):
                if err != .cancelled {
                    previewState = .failure(err)
                }
            }
        }
    }
}

// MARK: - Mode 4: Photo Table View

struct PhotoTableView: View {
    let groups: [CaptureGroup]
    let selectedGroup: CaptureGroup?
    var isSelectionMode: Bool = false
    var selectedGroupIDs: Set<String> = []
    var onToggleSelect: ((CaptureGroup) -> Void)? = nil
    let onSelect: (CaptureGroup) -> Void
    
    init(
        groups: [CaptureGroup],
        selectedGroup: CaptureGroup? = nil,
        isSelectionMode: Bool = false,
        selectedGroupIDs: Set<String> = [],
        onToggleSelect: ((CaptureGroup) -> Void)? = nil,
        onSelect: @escaping (CaptureGroup) -> Void
    ) {
        self.groups = groups
        self.selectedGroup = selectedGroup
        self.isSelectionMode = isSelectionMode
        self.selectedGroupIDs = selectedGroupIDs
        self.onToggleSelect = onToggleSelect
        self.onSelect = onSelect
    }
    
    init(
        files: [IngestedFile],
        selectedFile: IngestedFile? = nil,
        onSelect: @escaping (IngestedFile) -> Void
    ) {
        self.groups = files.map { file in
            if let asset = file.mediaAsset {
                return CaptureGroup(asset: asset)
            }
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            return CaptureGroup(asset: asset)
        }
        self.selectedGroup = groups.first
        self.isSelectionMode = false
        self.selectedGroupIDs = []
        self.onToggleSelect = nil
        self.onSelect = { group in
            if let first = group.primaryAsset {
                onSelect(IngestedFile(from: first))
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Шапка таблицы
            tableHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
            
            Divider().background(Color.white.opacity(0.15))
            
            // Строки таблицы
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        PhotoTableRow(
                            index: groups.count - index,
                            group: group,
                            isSelected: isSelectionMode ? selectedGroupIDs.contains(group.id) : (selectedGroup?.id == group.id),
                            isEven: index % 2 == 0,
                            isSelectionMode: isSelectionMode
                        )
                        .onTapGesture {
                            if isSelectionMode {
                                onToggleSelect?(group)
                            } else {
                                onSelect(group)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("№")
                .frame(width: 22, alignment: .leading)
            Text("Кадр")
                .frame(minWidth: 90, alignment: .leading)
            Spacer()
            Text("Отбор")
                .frame(width: 48, alignment: .center)
            Text("Формат")
                .frame(width: 68, alignment: .center)
            Text("Оригиналы")
                .frame(width: 70, alignment: .trailing)
            Text("Объём")
                .frame(width: 65, alignment: .trailing)
            Text("Время")
                .frame(width: 55, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }
}

struct PhotoTableRow: View {
    let index: Int
    let group: CaptureGroup
    let isSelected: Bool
    let isEven: Bool
    var isSelectionMode: Bool = false
    @State private var previewState: PreviewState = .idle
    
    init(index: Int, group: CaptureGroup, isSelected: Bool, isEven: Bool, isSelectionMode: Bool = false) {
        self.index = index
        self.group = group
        self.isSelected = isSelected
        self.isEven = isEven
        self.isSelectionMode = isSelectionMode
    }
    
    init(index: Int, file: IngestedFile, isSelected: Bool, isEven: Bool) {
        self.index = index
        if let asset = file.mediaAsset {
            self.group = CaptureGroup(asset: asset)
        } else {
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            self.group = CaptureGroup(asset: asset)
        }
        self.isSelected = isSelected
        self.isEven = isEven
        self.isSelectionMode = false
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                    .frame(width: 16)
            } else {
                Text("\(index)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
            }
            
            HStack(spacing: 6) {
                ZStack {
                    Color.white.opacity(0.1)
                    if case .success(let img) = previewState {
                        #if canImport(UIKit)
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #elseif canImport(AppKit)
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #endif
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                
                Text(group.baseName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(minWidth: 90, alignment: .leading)
            
            Spacer()
            
            // Колонка отбора (флаг и рейтинг)
            HStack(spacing: 3) {
                if group.pickStatus == .picked {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                } else if group.pickStatus == .rejected {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                }
                
                if group.rating > 0 {
                    Text("★\(group.rating)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                }
            }
            .frame(width: 48, alignment: .center)
            
            Text(group.formatBadge)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(group.hasBothRawAndJpeg ? Color.green : (group.rawAsset != nil ? Color.orange : Color.blue))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 68, alignment: .center)
            
            Text("\(group.allAssets.count) файл(а)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 70, alignment: .trailing)
            
            Text(group.formattedTotalSize)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 65, alignment: .trailing)
            
            if let primary = group.primaryAsset {
                Text(primary.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color.blue.opacity(0.2)
                : (isEven ? Color.white.opacity(0.02) : Color.white.opacity(0.05))
        )
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
        )
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 80)
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 80)
            if Task.isCancelled { return }
            switch result {
            case .success(let img):
                previewState = .success(img)
            case .failure(let err):
                if err != .cancelled {
                    previewState = .failure(err)
                }
            }
        }
    }
}

// MARK: - Filmstrip Tile

struct FilmstripTile: View {
    let group: CaptureGroup
    let isSelected: Bool
    @State private var previewState: PreviewState = .idle
    
    init(group: CaptureGroup, isSelected: Bool) {
        self.group = group
        self.isSelected = isSelected
    }
    
    init(file: IngestedFile, isSelected: Bool) {
        if let asset = file.mediaAsset {
            self.group = CaptureGroup(asset: asset)
        } else {
            let asset = MediaAsset(
                sessionID: UUID(),
                filename: file.filename,
                fileURL: file.fileURL,
                format: MediaFormat(fileExtension: file.fileURL.pathExtension),
                fileSize: file.fileSize,
                receivedAt: file.receivedAt,
                transferDuration: file.transferDuration
            )
            self.group = CaptureGroup(asset: asset)
        }
        self.isSelected = isSelected
    }
    
    private var primaryURL: URL? {
        group.primaryAsset?.fileURL
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if case .success(let img) = previewState {
                #if canImport(UIKit)
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
                #elseif canImport(AppKit)
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
                #endif
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 64, height: 64)
                    .overlay(ProgressView().scaleEffect(0.6))
            }
            
            // Верхний левый угол: флаг отбора
            if group.pickStatus == .picked {
                VStack {
                    HStack {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.green)
                            .clipShape(Circle())
                            .padding(2)
                        Spacer()
                    }
                    Spacer()
                }
            } else if group.pickStatus == .rejected {
                VStack {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.red)
                            .clipShape(Circle())
                            .padding(2)
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            // Нижний левый угол: звёздочки
            if group.rating > 0 {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.yellow)
                            Text("\(group.rating)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(2)
                        Spacer()
                    }
                }
            }
            
            Text(group.formatBadge)
                .font(.system(size: 7, weight: .bold))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(group.hasBothRawAndJpeg ? Color.green : (group.rawAsset != nil ? Color.orange : Color.blue))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(2)
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
        )
        .task(id: group.id) {
            loadThumbnail()
        }
        .onDisappear {
            if let url = primaryURL {
                Task {
                    await PreviewPipeline.shared.cancelLoading(for: url, maxPixelSize: 180)
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let url = primaryURL else { return }
        previewState = .loading
        Task {
            let result = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 180)
            if Task.isCancelled { return }
            switch result {
            case .success(let img):
                previewState = .success(img)
            case .failure(let err):
                if err != .cancelled {
                    previewState = .failure(err)
                }
            }
        }
    }
}
