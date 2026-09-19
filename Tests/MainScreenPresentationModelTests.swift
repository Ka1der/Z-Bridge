import Foundation
import SwiftUI

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct MainScreenPresentationModelTestsMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ МОДЕЛИ ПРЕДСТАВЛЕНИЯ ГЛАВНОГО ЭКРАНА ===")
        
        let suite = MainScreenPresentationModelTestSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ МОДЕЛИ ПРЕДСТАВЛЕНИЯ УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class MainScreenPresentationModelTestSuite {
    
    func runAllTests() async throws {
        testCameraDisconnectedEmptyState()
        testConnectingStageDescriptions()
        testReadingCardRealFileCount()
        testCardReadyEmptyGalleryActions()
        testCardEmptyOrNoMatchingFilesExplanationAndRefresh()
        testTransferringProgressAndQueueAction()
        testErrorStatesAndApplicableActions()
        testFTPWaitingPushOnlyWithoutCardBrowsing()
        testAllFilteredOutAndResetFiltersAction()
        testNonEmptyGalleryRetainsViewsAndShowsCompactStatusOnDisconnect()
        testNonEmptyGalleryShowsCompactStatusDuringTransferAndCardReady()
        testAppStateResetFiltersIntegration()
        testAppStateMainScreenActionDispatch()
    }
    
    // MARK: - 1. Камера не подключена → «Подключить камеру»
    func testCameraDisconnectedEmptyState() {
        print("\n[1/13] Тест состояния «Камера не подключена»...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .disconnected,
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        verify(!state.hasPhotos, "hasPhotos должен быть false")
        verify(!state.areAllPhotosFilteredOut, "areAllPhotosFilteredOut должен быть false")
        verify(state.compactBanner == nil, "При пустой галерее компактный баннер отсутствует")
        
        guard let empty = state.emptyState else {
            fatalError("emptyState должен присутствовать при пустой галерее")
        }
        verify(empty.kind == .disconnected)
        verify(empty.title == "Камера не подключена")
        verify(empty.description.contains("USB-C") || empty.description.contains("Wi-Fi"))
        verify(empty.primaryAction?.type == .connectCamera)
        verify(empty.primaryAction?.title == "Подключить камеру")
        verify(empty.secondaryAction?.type == .openConnectionGuide)
        
        print("  ✓ Текст, кнопки и иконки для отключенной камеры подтверждены")
    }
    
    // MARK: - 2. Подключение устанавливается → описание текущего этапа
    func testConnectingStageDescriptions() {
        print("\n[2/13] Тест этапов установки подключения к камере...")
        
        // Этап 1: discovered
        let stateDiscovered = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .discovered(name: "Nikon Z 8"),
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateDiscovered.emptyState?.kind == .connecting)
        verify(stateDiscovered.emptyState?.showsProgress == true)
        verify(stateDiscovered.emptyState?.description.contains("Nikon Z 8") == true)
        
        // Этап 2: openingSession
        let stateOpening = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .openingSession(name: "Nikon Z 8"),
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateOpening.emptyState?.kind == .connecting)
        verify(stateOpening.emptyState?.title == "Открытие сессии")
        verify(stateOpening.emptyState?.description.contains("PTP-сессии") == true)
        
        // Этап 3: sessionOpened
        let stateOpened = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .sessionOpened(name: "Nikon Z 8"),
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateOpened.emptyState?.kind == .connecting)
        verify(stateOpened.emptyState?.title == "Сессия открыта")
        verify(stateOpened.emptyState?.description.contains("оглавления") == true)
        
        print("  ✓ Все промежуточные фазы открытия USB-сессии корректно описаны с индикатором")
    }
    
    // MARK: - 3. Читается карта → индикатор и реальное число найденных файлов
    func testReadingCardRealFileCount() {
        print("\n[3/13] Тест индикации чтения оглавления карты с реальным числом файлов...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .enumeratingCatalog(name: "Nikon Z 8", itemsFound: 142),
            isCatalogReady: false,
            catalogTotalCount: 142,
            catalogUnimportedCount: 142,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        verify(state.emptyState?.kind == .readingCard)
        verify(state.emptyState?.title == "Чтение карты памяти")
        verify(state.emptyState?.showsProgress == true)
        verify(state.emptyState?.description.contains("142") == true, "Описание должно содержать реальное число найденных файлов (142)")
        
        print("  ✓ Чтение карты отображает прогресс и точное количество найденных файлов")
    }
    
    // MARK: - 4. Карта готова, галерея пуста → «Загрузить с камеры» и «Выбрать снимки»
    func testCardReadyEmptyGalleryActions() {
        print("\n[4/13] Тест состояния готовой карты при пустой галерее...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .ready(name: "Nikon Z 8", totalItems: 350),
            isCatalogReady: true,
            catalogTotalCount: 350,
            catalogUnimportedCount: 42,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        verify(state.emptyState?.kind == .cardReady)
        verify(state.emptyState?.title == "Карта памяти готова к импорту")
        verify(state.emptyState?.description.contains("350") == true)
        verify(state.emptyState?.description.contains("42") == true)
        
        // Первичное действие: «Загрузить с камеры»
        verify(state.emptyState?.primaryAction?.type == .importAllFromCard)
        verify(state.emptyState?.primaryAction?.title == "Загрузить с камеры")
        
        // Вторичное действие: «Выбрать снимки»
        verify(state.emptyState?.secondaryAction?.type == .selectCardFiles)
        verify(state.emptyState?.secondaryAction?.title == "Выбрать снимки")
        
        print("  ✓ Готовая карта предлагает явные действия импорта всех и выбора файлов")
    }
    
    // MARK: - 5. На карте нет подходящих файлов → объяснение и возможность обновления
    func testCardEmptyOrNoMatchingFilesExplanationAndRefresh() {
        print("\n[5/13] Тест оглавления без подходящих файлов и команды обновления...")
        
        // Ситуация A: карта физически пуста
        let stateEmptyCard = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .ready(name: "Nikon Z 8", totalItems: 0),
            isCatalogReady: true,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateEmptyCard.emptyState?.kind == .cardEmptyOrNoMatchingFiles)
        verify(stateEmptyCard.emptyState?.title == "На карте нет подходящих файлов")
        verify(stateEmptyCard.emptyState?.description.contains("нет файлов") == true)
        verify(stateEmptyCard.emptyState?.primaryAction?.type == .refreshCard)
        verify(stateEmptyCard.emptyState?.primaryAction?.title == "Обновить оглавление")
        
        // Ситуация B: на карте 100 файлов, но все 100 уже импортированы в сессию
        let stateAllImported = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .ready(name: "Nikon Z 8", totalItems: 100),
            isCatalogReady: true,
            catalogTotalCount: 100,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateAllImported.emptyState?.kind == .cardEmptyOrNoMatchingFiles)
        verify(stateAllImported.emptyState?.description.contains("уже импортированы") == true)
        verify(stateAllImported.emptyState?.primaryAction?.type == .refreshCard)
        
        print("  ✓ Пустая карта и отсутствие неимпортированных кадров объясняются фотографу с кнопкой обновления")
    }
    
    // MARK: - 6. Идёт загрузка → прогресс и переход к очереди
    func testTransferringProgressAndQueueAction() {
        print("\n[6/13] Тест состояния активной загрузки...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .transferring(activeCount: 1, pendingCount: 5),
            isCatalogReady: true,
            catalogTotalCount: 100,
            catalogUnimportedCount: 6,
            isDownloading: true,
            activeTransferCount: 1,
            pendingQueueCount: 5,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        verify(state.emptyState?.kind == .transferring)
        verify(state.emptyState?.title == "Идёт передача снимков")
        verify(state.emptyState?.showsProgress == true)
        verify(state.emptyState?.description.contains("1") == true)
        verify(state.emptyState?.description.contains("5") == true)
        verify(state.emptyState?.primaryAction?.type == .viewTransferQueue)
        verify(state.emptyState?.primaryAction?.title == "Перейти к очереди")
        
        print("  ✓ Загрузка отображает точные счетчики и действие перехода к очереди")
    }
    
    // MARK: - 7. Ошибка → понятное описание и применимое действие
    func testErrorStatesAndApplicableActions() {
        print("\n[7/13] Тест состояний ошибок USB...")
        
        // Ошибка сбоя протокола
        let stateError = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .error(message: "Таймаут передачи PTP пакета"),
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateError.emptyState?.kind == .error)
        verify(stateError.emptyState?.description.contains("Таймаут") == true)
        verify(stateError.emptyState?.primaryAction?.type == .retryConnection)
        verify(stateError.emptyState?.primaryAction?.title == "Повторить подключение")
        verify(stateError.emptyState?.secondaryAction?.type == .connectCamera)
        
        // Ограничение доступа системы
        let stateDenied = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .accessDenied(reason: "Камера заблокирована пин-кодом"),
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateDenied.emptyState?.kind == .error)
        verify(stateDenied.emptyState?.title == "Доступ к камере ограничен")
        verify(stateDenied.emptyState?.description.contains("пин-кодом") == true)
        verify(stateDenied.emptyState?.primaryAction?.type == .openConnectionGuide)
        
        print("  ✓ Ошибки и ограничения доступа понятны и предлагают целевые действия")
    }
    
    // MARK: - 8. Для FTP показывать ожидание передачи с камеры, без предложений чтения карты
    func testFTPWaitingPushOnlyWithoutCardBrowsing() {
        print("\n[8/13] Тест FTP режима: ожидание push-передачи без чтения карты...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .disconnected,
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: true,
            ftpClientCount: 1,
            ftpServerIP: "192.168.1.50",
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        verify(state.emptyState?.kind == .ftpWaiting)
        verify(state.emptyState?.title == "Ожидание передачи с камеры")
        verify(state.emptyState?.description.contains("192.168.1.50:2121") == true)
        verify(state.emptyState?.description.contains("Сделайте снимок на камеру") == true)
        
        // КЛЮЧЕВОЕ ТРЕБОВАНИЕ: Для FTP НЕ должно предлагаться чтение карты!
        verify(state.emptyState?.primaryAction?.type != .importAllFromCard, "Для FTP нельзя предлагать импорт с карты")
        verify(state.emptyState?.primaryAction?.type != .selectCardFiles, "Для FTP нельзя предлагать выбор снимков с карты")
        verify(state.emptyState?.primaryAction?.type == .openConnectionGuide, "Для FTP предлагается инструкция настройки камеры")
        
        print("  ✓ FTP режим строго ориентирован на прием снимков (Push) и не предлагает чтение флешки")
    }
    
    // MARK: - 9. Фильтры скрыли все кадры → «Сбросить фильтры»
    func testAllFilteredOutAndResetFiltersAction() {
        print("\n[9/13] Тест скрытия всех кадров фильтрами...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 50,
            filteredGalleryCount: 0, // Все 50 кадров отфильтрованы!
            hasActiveFilters: true,
            usbConnectionState: .ready(name: "Nikon Z 8", totalItems: 100),
            isCatalogReady: true,
            catalogTotalCount: 100,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        verify(state.hasPhotos == true, "Фотографии в сессии есть")
        verify(state.areAllPhotosFilteredOut == true, "Все кадры скрыты фильтрами")
        verify(state.emptyState?.kind == .allFilteredOut)
        verify(state.emptyState?.title == "Снимки скрыты фильтрами")
        verify(state.emptyState?.description.contains("50 кадр") == true)
        verify(state.emptyState?.primaryAction?.type == .resetFilters)
        verify(state.emptyState?.primaryAction?.title == "Сбросить фильтры")
        
        print("  ✓ Экран фильтрации объясняет, что в сессии есть кадры, и предлагает сбросить фильтры")
    }
    
    // MARK: - 10. Если фотографии уже есть, не заменять галерею полноэкранным экраном обрыва связи
    func testNonEmptyGalleryRetainsViewsAndShowsCompactStatusOnDisconnect() {
        print("\n[10/13] Тест сохранения галереи и показа компактного баннера при потере связи...")
        
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 25,
            filteredGalleryCount: 25, // Кадры видны
            hasActiveFilters: false,
            usbConnectionState: .disconnected, // Кабель случайно выдернут во время просмотра
            isCatalogReady: false,
            catalogTotalCount: 0,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        
        // КЛЮЧЕВОЕ ТРЕБОВАНИЕ: Галерея НЕ должна замещаться полноэкранным экраном!
        verify(state.hasPhotos == true)
        verify(state.emptyState == nil, "emptyState должен быть nil, чтобы галерея оставалась на экране!")
        
        // Вместо этого должен присутствовать компактный статус поверх интерфейса
        guard let banner = state.compactBanner else {
            fatalError("compactBanner должен присутствовать при потере связи с фото в галерее")
        }
        verify(banner.style == .warning)
        verify(banner.title == "Камера отключена")
        verify(banner.systemImage == "cable.connector.slash")
        verify(banner.action?.type == .connectCamera)
        verify(banner.action?.title == "Подключить")
        
        print("  ✓ Галерея осталась видимой, выведен компактный статус отключения с кнопкой переподключения")
    }
    
    // MARK: - 11. Фотографии есть + идёт передача или карта готова
    func testNonEmptyGalleryShowsCompactStatusDuringTransferAndCardReady() {
        print("\n[11/13] Тест компактных баннеров при активной галерее (загрузка и новые файлы)...")
        
        // Ситуация A: идёт фоновая передача при открытой галерее
        let stateTransferring = MainScreenPresentationModel.resolve(
            totalGalleryCount: 10,
            filteredGalleryCount: 10,
            hasActiveFilters: false,
            usbConnectionState: .transferring(activeCount: 1, pendingCount: 3),
            isCatalogReady: true,
            catalogTotalCount: 50,
            catalogUnimportedCount: 4,
            isDownloading: true,
            activeTransferCount: 1,
            pendingQueueCount: 3,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateTransferring.emptyState == nil)
        verify(stateTransferring.compactBanner != nil)
        verify(stateTransferring.compactBanner?.showsProgress == true)
        verify(stateTransferring.compactBanner?.title.contains("1 акт., 3 в очереди") == true)
        verify(stateTransferring.compactBanner?.action?.type == .viewTransferQueue)
        
        // Ситуация B: на карте найдены новые неимпортированные файлы
        let stateNewFiles = MainScreenPresentationModel.resolve(
            totalGalleryCount: 10,
            filteredGalleryCount: 10,
            hasActiveFilters: false,
            usbConnectionState: .ready(name: "Nikon Z 8", totalItems: 50),
            isCatalogReady: true,
            catalogTotalCount: 50,
            catalogUnimportedCount: 12,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: true
        )
        verify(stateNewFiles.emptyState == nil)
        verify(stateNewFiles.compactBanner?.title.contains("12 новых файлов") == true)
        verify(stateNewFiles.compactBanner?.action?.type == .importAllFromCard)
        verify(stateNewFiles.compactBanner?.action?.title == "Загрузить все")
        
        print("  ✓ Компактные баннеры отображают прогресс загрузки и наличие новых файлов карты поверх галереи")
    }
    
    // MARK: - 12. Интеграция с AppState: проверка hasActiveFilters и resetFilters()
    func testAppStateResetFiltersIntegration() {
        print("\n[12/13] Тест интеграции с AppState: фильтры и сброс...")
        
        let appState = AppState()
        
        // По умолчанию все фильтры выключены (все форматы разрешены)
        verify(!appState.hasActiveFilters, "По умолчанию фильтры не активны")
        
        // Включаем фильтрацию (например, скрываем RAW и ставим 5 звезд)
        appState.showRAW = false
        appState.ratingFilter = .stars5Only
        verify(appState.hasActiveFilters, "После изменения параметров hasActiveFilters должен стать true")
        
        // Вызываем resetFilters()
        appState.resetFilters()
        verify(!appState.hasActiveFilters, "После resetFilters() hasActiveFilters должен быть false")
        verify(appState.showRAW == true)
        verify(appState.showJPG == true)
        verify(appState.showHEIF == true)
        verify(appState.ratingFilter == .all)
        verify(appState.pickFilter == .all)
        
        print("  ✓ hasActiveFilters и resetFilters() в AppState работают корректно")
    }
    
    // MARK: - 13. Интеграция с AppState: диспетчер handleMainScreenAction
    func testAppStateMainScreenActionDispatch() {
        print("\n[13/13] Тест диспетчера handleMainScreenAction...")
        
        let appState = AppState()
        
        // Проверяем сброс фильтров через экшен
        appState.showRAW = false
        appState.handleMainScreenAction(.resetFilters)
        verify(appState.showRAW == true)
        
        // Проверяем открытие очереди
        appState.isQueuePresented = false
        appState.handleMainScreenAction(.viewTransferQueue)
        verify(appState.isQueuePresented == true)
        
        // Проверяем открытие браузера карты
        appState.isUSBBrowserPresented = false
        appState.handleMainScreenAction(.selectCardFiles)
        verify(appState.isUSBBrowserPresented == true)
        
        // Проверяем открытие мастера подключения
        appState.isWizardPresented = false
        appState.handleMainScreenAction(.connectCamera)
        verify(appState.isWizardPresented == true)
        
        print("  ✓ handleMainScreenAction корректно переключает представления и выполняет действия")
    }
}
