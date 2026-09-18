import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct Stage11VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 11: РЕЖИМ КЛИЕНТСКОГО МОНИТОРА ===")
        
        let suite = Stage11VerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 11 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage11VerificationSuite {
    let tempDir: URL
    
    init() {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage11Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.tempDir = baseDir
    }
    
    func runAllTests() async throws {
        try await testConfigAndFilterModes()
        try await testAutomaticSwitchingToLatestFrame()
        try await testSwitchDelayAndBurstDebounce()
        try await testHoldPinningMode()
        try await testHoldReleaseAndSyncWithLatest()
        try await testCuratedClientViewWithPicksAndRatings()
        try await testExternalDisplayConnectionAndDisconnectionResilience()
        try await testAppStateIntegrationAndShortcuts()
    }
    
    // MARK: - Вспомогательные методы
    
    private func createDummyGroup(name: String, rating: Int = 0, isPicked: Bool = false, isRejected: Bool = false) -> CaptureGroup {
        let fileURL = tempDir.appendingPathComponent("\(name).JPG")
        try? Data(repeating: 0xFF, count: 512).write(to: fileURL)
        
        let sessionID = UUID()
        let status: PickStatus = isPicked ? .picked : (isRejected ? .rejected : .unflagged)
        let asset = MediaAsset(
            sessionID: sessionID,
            filename: "\(name).JPG",
            fileURL: fileURL,
            format: .jpeg,
            fileSize: 512,
            rating: rating,
            pickStatus: status
        )
        
        var group = CaptureGroup(baseName: name, sessionID: sessionID)
        group.addAsset(asset)
        group.rating = rating
        group.pickStatus = status
        return group
    }
    
    // MARK: - [1/8] Тест конфигурации, задержек переключения и режимов фильтрации
    
    func testConfigAndFilterModes() async throws {
        print("\n[1/8] Тест конфигурации, задержек переключения и режимов фильтрации...")
        
        // 1. Проверка вариантов задержек
        assert(SwitchDelayOption.instant.seconds == 0.0, "instant delay должен быть 0.0s")
        assert(SwitchDelayOption.halfSecond.seconds == 0.5, "halfSecond delay должен быть 0.5s")
        assert(SwitchDelayOption.oneSecond.seconds == 1.0, "oneSecond delay должен быть 1.0s")
        assert(SwitchDelayOption.twoSeconds.seconds == 2.0, "twoSeconds delay должен быть 2.0s")
        assert(SwitchDelayOption.threeSeconds.seconds == 3.0, "threeSeconds delay должен быть 3.0s")
        assert(SwitchDelayOption.fiveSeconds.seconds == 5.0, "fiveSeconds delay должен быть 5.0s")
        
        // 2. Проверка соответствия фильтров
        let normalGroup = createDummyGroup(name: "DSC_0001", rating: 0, isPicked: false)
        let pickedGroup = createDummyGroup(name: "DSC_0002", rating: 0, isPicked: true)
        let rated3Group = createDummyGroup(name: "DSC_0003", rating: 3, isPicked: false)
        let rated5Group = createDummyGroup(name: "DSC_0004", rating: 5, isPicked: true)
        
        // Режим .all
        assert(ClientMonitorFilterMode.all.matches(group: normalGroup), ".all должен пропускать обычные кадры")
        assert(ClientMonitorFilterMode.all.matches(group: pickedGroup), ".all должен пропускать выбранные кадры")
        
        // Режим .onlyPicked
        assert(!ClientMonitorFilterMode.onlyPicked.matches(group: normalGroup), ".onlyPicked не должен пропускать обычные кадры")
        assert(ClientMonitorFilterMode.onlyPicked.matches(group: pickedGroup), ".onlyPicked должен пропускать флагированные кадры")
        assert(ClientMonitorFilterMode.onlyPicked.matches(group: rated5Group), ".onlyPicked должен пропускать флагированные кадры")
        
        // Режимы рейтинга
        assert(!ClientMonitorFilterMode.rated1Plus.matches(group: normalGroup), ".rated1Plus не должен пропускать кадры с рейтингом 0")
        assert(ClientMonitorFilterMode.rated1Plus.matches(group: rated3Group), ".rated1Plus должен пропускать кадры с рейтингом 3")
        assert(!ClientMonitorFilterMode.rated4Plus.matches(group: rated3Group), ".rated4Plus не должен пропускать кадры с рейтингом 3")
        assert(ClientMonitorFilterMode.rated4Plus.matches(group: rated5Group), ".rated4Plus должен пропускать кадры с рейтингом 5")
        assert(ClientMonitorFilterMode.rated5Only.matches(group: rated5Group), ".rated5Only должен пропускать только 5 звёзд")
        assert(!ClientMonitorFilterMode.rated5Only.matches(group: rated3Group), ".rated5Only не должен пропускать 3 звезды")
        
        print("✓ Конфигурация и правила фильтрации клиентского монитора работают корректно.")
    }
    
    // MARK: - [2/8] Автоматическое переключение на последний поступивший кадр
    
    func testAutomaticSwitchingToLatestFrame() async throws {
        print("\n[2/8] Тест автоматического переключения на последний поступивший кадр...")
        
        let manager = ClientMonitorManager()
        manager.config.switchDelay = .instant
        manager.config.filterMode = .all
        
        let frame1 = createDummyGroup(name: "NIKON_001")
        let frame2 = createDummyGroup(name: "NIKON_002")
        let frame3 = createDummyGroup(name: "NIKON_003")
        
        manager.handleIncomingGroup(frame1)
        assert(manager.displayedGroup?.id == frame1.id, "Клиентский монитор должен сразу отобразить первый кадр")
        
        manager.handleIncomingGroup(frame2)
        assert(manager.displayedGroup?.id == frame2.id, "Клиентский монитор должен автоматически переключиться на NIKON_002")
        
        manager.handleIncomingGroup(frame3)
        assert(manager.displayedGroup?.id == frame3.id, "Клиентский монитор должен автоматически переключиться на NIKON_003")
        
        print("✓ Автоматическое отображение последнего кадра при instant-задержке работает безупречно.")
    }
    
    // MARK: - [3/8] Задержка переключения и устранение стробирования (дебаунс серии)
    
    func testSwitchDelayAndBurstDebounce() async throws {
        print("\n[3/8] Тест задержки переключения и дебаунса серийной съёмки...")
        
        let manager = ClientMonitorManager()
        manager.config.switchDelay = .halfSecond // 0.5s
        manager.config.filterMode = .all
        
        let initialFrame = createDummyGroup(name: "BURST_BASE")
        manager.displayedGroup = initialFrame
        
        // Симулируем быструю серию кадров (10 к/с)
        let b1 = createDummyGroup(name: "BURST_001")
        let b2 = createDummyGroup(name: "BURST_002")
        let b3 = createDummyGroup(name: "BURST_003")
        let b4 = createDummyGroup(name: "BURST_FINAL")
        
        manager.handleIncomingGroup(b1)
        manager.handleIncomingGroup(b2)
        manager.handleIncomingGroup(b3)
        manager.handleIncomingGroup(b4)
        
        // Сразу после вызова displayedGroup ещё не должен смениться из-за задержки 0.5с (предотвращение стробирования)
        assert(manager.displayedGroup?.id == initialFrame.id, "При активной задержке переключение не должно быть мгновенным во время серии")
        
        // Ожидаем завершения времени дебаунса (0.5 сек + небольшой запас)
        try await Task.sleep(nanoseconds: 600_000_000)
        
        // Теперь должен отобразиться финальный кадр серии
        assert(manager.displayedGroup?.id == b4.id, "После завершения задержки дебаунса должен отобразиться финальный кадр серии")
        
        print("✓ Дебаунс серийной съемки эффективно предотвращает стробирование и мерцание монитора.")
    }
    
    // MARK: - [4/8] Режим удержания кадра (Hold / Pin / Freeze)
    
    func testHoldPinningMode() async throws {
        print("\n[4/8] Тест режима удержания кадра (Hold / Pin / Freeze)...")
        
        let manager = ClientMonitorManager()
        manager.config.switchDelay = .instant
        manager.config.filterMode = .all
        
        let heroShot = createDummyGroup(name: "PORTRAIT_HERO")
        manager.handleIncomingGroup(heroShot)
        assert(manager.displayedGroup?.id == heroShot.id, "Hero кадр должен отображаться")
        
        // Фотограф включает Hold на текущем кадре
        manager.toggleHold(for: heroShot)
        assert(manager.config.isHoldEnabled == true, "Hold должен быть активен")
        assert(manager.heldGroup?.id == heroShot.id, "Held кадр должен быть сохранён")
        assert(manager.config.heldGroupID == heroShot.id, "Идентификатор удерживаемого кадра должен быть зафиксирован")
        
        // Во время съёмки поступают новые кадры
        let nextShot1 = createDummyGroup(name: "NEXT_001")
        let nextShot2 = createDummyGroup(name: "NEXT_002")
        let nextShot3 = createDummyGroup(name: "NEXT_003")
        
        manager.handleIncomingGroup(nextShot1)
        manager.handleIncomingGroup(nextShot2)
        manager.handleIncomingGroup(nextShot3)
        
        // Клиент по-прежнему должен видеть heroShot!
        assert(manager.displayedGroup?.id == heroShot.id, "Во время удержания клиентский монитор обязан оставаться на зафиксированном кадре!")
        
        print("✓ Режим удержания (Hold) надёжно фиксирует кадр для клиента при продолжении съёмки фотографом.")
    }
    
    // MARK: - [5/8] Снятие удержания и синхронизация с актуальным кадром
    
    func testHoldReleaseAndSyncWithLatest() async throws {
        print("\n[5/8] Тест снятия удержания и синхронизации с актуальным кадром...")
        
        let manager = ClientMonitorManager()
        manager.config.switchDelay = .instant
        
        let heldFrame = createDummyGroup(name: "HOLD_FRAME")
        manager.handleIncomingGroup(heldFrame)
        manager.setHold(true, for: heldFrame)
        
        let newestFrame = createDummyGroup(name: "NEWEST_SESSION_FRAME")
        
        // Фотограф снимает удержание с передачей последнего кадра сессии
        manager.releaseHold(latestGroup: newestFrame)
        
        assert(!manager.config.isHoldEnabled, "Hold должен быть выключен")
        assert(manager.heldGroup == nil, "heldGroup должен быть сброшен")
        assert(manager.config.heldGroupID == nil, "heldGroupID должен быть очищен")
        assert(manager.displayedGroup?.id == newestFrame.id, "Клиентский монитор должен синхронизироваться с актуальным последним кадром")
        
        // Проверка повторного переключения toggleHold
        manager.toggleHold()
        assert(manager.config.isHoldEnabled, "Повторный toggleHold должен включить удержание")
        manager.toggleHold()
        assert(!manager.config.isHoldEnabled, "Следующий toggleHold должен снять удержание")
        
        print("✓ Снятие удержания и синхронизация сессии работают корректно.")
    }
    
    // MARK: - [6/8] Курируемый просмотр: фильтрация отбора (Pick) и рейтинга (Звёзды)
    
    func testCuratedClientViewWithPicksAndRatings() async throws {
        print("\n[6/8] Тест курируемого показа клиенту только отобранных кадров...")
        
        let manager = ClientMonitorManager()
        manager.config.switchDelay = .instant
        manager.config.filterMode = .onlyPicked // Клиенту показываются ТОЛЬКО кадры с флагом Pick
        
        let initialFrame = createDummyGroup(name: "APPROVED_START", rating: 0, isPicked: true)
        manager.displayedGroup = initialFrame
        
        // 1. Поступает обычный кадр без отметки
        var unapproved = createDummyGroup(name: "CANDID_UNAPPROVED", rating: 0, isPicked: false)
        manager.handleIncomingGroup(unapproved)
        
        assert(manager.displayedGroup?.id == initialFrame.id, "Неодобренный кадр НЕ должен попадать на клиентский монитор")
        
        // 2. Фотограф рассматривает кадр и нажимает флаг Pick 'P'
        unapproved.pickStatus = .picked
        manager.handleGroupUpdated(unapproved)
        
        assert(manager.displayedGroup?.id == unapproved.id, "После отметки Pick кадр должен мгновенно появиться на клиентском экране!")
        
        // 3. Тест фильтрации по рейтингу (например, только 3+ звезды)
        manager.config.filterMode = .rated3Plus
        var testStarFrame = createDummyGroup(name: "STAR_CANDIDATE", rating: 0, isPicked: false)
        manager.handleIncomingGroup(testStarFrame)
        assert(manager.displayedGroup?.id == unapproved.id, "Кадр с 0 звёзд не должен показываться в режиме .rated3Plus")
        
        // Выставляем 4 звезды
        testStarFrame.rating = 4
        manager.handleGroupUpdated(testStarFrame)
        assert(manager.displayedGroup?.id == testStarFrame.id, "После присвоения 4 звёзд кадр удовлетворяет условию и отображается клиенту")
        
        // 4. Принудительный показ (forcePresentGroup) фотографом любого кадра вне зависимости от фильтра
        let unratedSpecial = createDummyGroup(name: "FORCED_SHOW_SPECIAL", rating: 0, isPicked: false)
        manager.forcePresentGroup(unratedSpecial)
        assert(manager.displayedGroup?.id == unratedSpecial.id, "forcePresentGroup должен выводить кадр даже при несоответствии фильтру")
        
        print("✓ Курируемый просмотр (Pick-only и звездный рейтинг) работает безупречно.")
    }
    
    // MARK: - [7/8] Устойчивость к подключению и отключению внешнего монитора (USB-C / HDMI / AirPlay)
    
    func testExternalDisplayConnectionAndDisconnectionResilience() async throws {
        print("\n[7/8] Тест устойчивости к подключению и отключению внешнего экрана...")
        
        let manager = ClientMonitorManager()
        manager.config.switchDelay = .instant
        assert(manager.externalDisplayStatus == .disconnected, "Изначально внешний монитор отключен")
        assert(!manager.isExternalWindowActive, "Окно внешнего монитора не активно")
        
        // Имитируем подключение кабеля HDMI / USB-C
        manager.simulateExternalDisplayConnected(name: "Eizo ColorEdge 4K", resolution: "3840x2160")
        assert(manager.isExternalWindowActive == true, "Внешнее окно должно стать активным")
        if case .connected(let name, let res) = manager.externalDisplayStatus {
            assert(name == "Eizo ColorEdge 4K")
            assert(res == "3840x2160")
        } else {
            assertionFailure("Статус должен быть .connected")
        }
        
        // Добавляем кадр во время активного внешнего монитора
        let testShot = createDummyGroup(name: "EXTERNAL_DISPLAY_TEST")
        manager.handleIncomingGroup(testShot)
        assert(manager.displayedGroup?.id == testShot.id)
        
        // Имитируем внезапное физическое отключение кабеля монитора
        manager.simulateExternalDisplayDisconnected()
        assert(!manager.isExternalWindowActive, "Внешнее окно должно деактивироваться")
        assert(manager.externalDisplayStatus == .disconnected, "Статус должен перейти в .disconnected")
        
        // Проверяем сохранность состояния и продолжение работы сессии
        assert(manager.displayedGroup?.id == testShot.id, "Текущий кадр не должен сбрасываться при отключении экрана")
        
        let postDisconnectShot = createDummyGroup(name: "POST_DISCONNECT_SHOT")
        manager.handleIncomingGroup(postDisconnectShot)
        assert(manager.displayedGroup?.id == postDisconnectShot.id, "Приложение продолжает полноценно принимать кадры после отключения кабеля")
        
        print("✓ Отключение внешнего монитора ни в коем случае не нарушает сессию и продолжается штатная работа.")
    }
    
    // MARK: - [8/8] Интеграция с AppState и горячие клавиши
    
    func testAppStateIntegrationAndShortcuts() async throws {
        print("\n[8/8] Тест интеграции клиентского монитора с AppState и горячими клавишами...")
        
        let appState = AppState()
        appState.clientMonitorManager.config.switchDelay = .instant
        
        let g1 = createDummyGroup(name: "APP_FRAME_1", rating: 0, isPicked: false)
        let g2 = createDummyGroup(name: "APP_FRAME_2", rating: 0, isPicked: false)
        appState.captureGroups = [g1, g2]
        appState.selectedGroup = g1
        
        // Проверка открытия клиентского монитора
        appState.presentClientMonitor()
        assert(appState.isClientMonitorPresented == true, "presentClientMonitor должен открывать полноэкранный режим")
        assert(appState.clientMonitorManager.displayedGroup?.id == g1.id, "Должен отображаться выбранный кадр")
        
        // Проверка переключения удержания горячей клавишей (H)
        appState.toggleClientMonitorHold()
        assert(appState.clientMonitorManager.config.isHoldEnabled == true, "Горячая клавиша 'H' должна включать Hold")
        assert(appState.clientMonitorManager.heldGroup?.id == g1.id, "Удерживаемым должен стать g1")
        
        appState.toggleClientMonitorHold()
        assert(appState.clientMonitorManager.config.isHoldEnabled == false, "Повторное нажатие 'H' должно отпускать Hold")
        
        // Проверка принудительной отправки кадра
        appState.selectedGroup = g2
        appState.pushSelectedToClientMonitor()
        assert(appState.clientMonitorManager.displayedGroup?.id == g2.id, "pushSelectedToClientMonitor должен вывести выбранный кадр")
        
        // Проверка открытия листа управления
        appState.presentClientControlSheet()
        assert(appState.isClientControlSheetPresented == true, "presentClientControlSheet должен открывать лист настроек")
        
        print("✓ Интеграция с AppState и клавиатурными шорткатами работает отлично.")
    }
}
