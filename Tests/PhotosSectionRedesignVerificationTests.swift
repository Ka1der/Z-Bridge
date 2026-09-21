import Foundation
import SwiftUI
#if canImport(NikonZbridge)
@testable import NikonZbridge
#endif

@MainActor
final class PhotosSectionRedesignVerificationTests {
    
    private func verify(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            fatalError("Verification failed: \(message) at \(file):\(line)")
        }
    }
    
    func runAllTests() async {
        print("=== СТАРТ ТЕСТОВ ПЕРЕРАБОТКИ РАЗДЕЛА «СНИМКИ» (LIQUID GLASS) ===")
        
        testAll7EmptyStatesResolution()
        testGalleryPreservedWhenConnectionLostWithPhotos()
        testAdaptiveColumnCountCalculation()
        testStrictBatchComparisonCondition()
        testSortingAndFilterOptions()
        testSessionNameLayoutSafety()
        
        print("\n=== ВСЕ ТЕСТЫ РАЗДЕЛА «СНИМКИ» УСПЕШНО ПРОЙДЕНЫ! ===")
    }
    
    // MARK: - 1. Проверка разрешения всех 7 пустых состояний
    func testAll7EmptyStatesResolution() {
        print("\n[1/6] Проверка разрешения 7 пустых состояний на реальной модели...")
        
        // 1. Нет камеры (отключена)
        let state1 = MainScreenPresentationModel.resolve(
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
            isFTPReceivingEnabled: false
        )
        verify(state1.emptyState?.kind == .disconnected, "Состояние 1: ожидается .disconnected")
        verify(state1.emptyState?.title == "Камера не подключена")
        
        // 2. Подключение камеры (.connecting)
        let state2 = MainScreenPresentationModel.resolve(
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
            isFTPReceivingEnabled: false
        )
        verify(state2.emptyState?.kind == .connecting, "Состояние 2: ожидается .connecting")
        verify(state2.emptyState?.showsProgress == true)
        
        // 3. Чтение карты памяти (.readingCard)
        let state3 = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .enumeratingCatalog(name: "Nikon Z 8", itemsFound: 15),
            isCatalogReady: false,
            catalogTotalCount: 15,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(state3.emptyState?.kind == .readingCard, "Состояние 3: ожидается .readingCard")
        
        // 4. Готовность карты к импорту (.cardReady)
        let state4 = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .connected(name: "Nikon Z 8"),
            isCatalogReady: true,
            catalogTotalCount: 50,
            catalogUnimportedCount: 30,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(state4.emptyState?.kind == .cardReady, "Состояние 4: ожидается .cardReady")
        verify(state4.emptyState?.primaryAction?.type == .importAllFromCard)
        
        // 5. Пустая карта или все уже импортированы (.cardEmptyOrNoMatchingFiles)
        let state5 = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .connected(name: "Nikon Z 8"),
            isCatalogReady: true,
            catalogTotalCount: 50,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(state5.emptyState?.kind == .cardEmptyOrNoMatchingFiles, "Состояние 5: ожидается .cardEmptyOrNoMatchingFiles")
        
        // 6. Ошибка подключения (.error)
        let state6 = MainScreenPresentationModel.resolve(
            totalGalleryCount: 0,
            filteredGalleryCount: 0,
            hasActiveFilters: false,
            usbConnectionState: .error(message: "Сбой USB-кабеля"),
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
            isFTPReceivingEnabled: false
        )
        verify(state6.emptyState?.kind == .error, "Состояние 6: ожидается .error")
        verify(state6.emptyState?.title == "Ошибка USB подключения")
        
        // 7. Все фотографии скрыты фильтрами (.allFilteredOut)
        let state7 = MainScreenPresentationModel.resolve(
            totalGalleryCount: 10,
            filteredGalleryCount: 0,
            hasActiveFilters: true,
            usbConnectionState: .connected(name: "Nikon Z 8"),
            isCatalogReady: true,
            catalogTotalCount: 10,
            catalogUnimportedCount: 0,
            isDownloading: false,
            activeTransferCount: 0,
            pendingQueueCount: 0,
            isFTPServerRunning: false,
            ftpClientCount: 0,
            ftpServerIP: nil,
            ftpServerPort: 2121,
            isFTPReceivingEnabled: false
        )
        verify(state7.emptyState?.kind == .allFilteredOut, "Состояние 7: ожидается .allFilteredOut")
        verify(state7.emptyState?.title == "Снимки скрыты фильтрами")
        verify(state7.emptyState?.primaryAction?.type == .resetFilters)
        
        print("  ✓ Все 7 пустых состояний корректно разрешаются на реальной модели")
    }
    
    // MARK: - 2. Защита галереи от скрытия при потере связи, когда фото уже есть
    func testGalleryPreservedWhenConnectionLostWithPhotos() {
        print("\n[2/6] Проверка: потеря связи не скрывает существующие фотографии галереи...")
        
        // В сессии 25 фотографий, но связь внезапно оборвалась (.disconnected)
        let state = MainScreenPresentationModel.resolve(
            totalGalleryCount: 25,
            filteredGalleryCount: 25,
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
            isFTPReceivingEnabled: false
        )
        
        verify(state.hasPhotos == true, "В сессии есть фото")
        verify(state.emptyState == nil, "Полноэкранное пустое состояние НЕ должно скрывать галерею")
        verify(state.areAllPhotosFilteredOut == false)
        
        print("  ✓ При наличии снимков обрыв связи не скрывает галерею")
    }
    
    // MARK: - 3. Адаптивный расчет числа колонок
    func testAdaptiveColumnCountCalculation() {
        print("\n[3/6] Проверка адаптивного расчета колонок сетки IconsGridView...")
        
        // iPhone в портрете (~393 pt)
        let iphonePortraitCols = IconsGridView.calculateColumnCount(for: 393)
        verify(iphonePortraitCols == 2, "iPhone в портрете должен иметь 2 колонки")
        
        // Узкий iPad Split View (~320 pt)
        let narrowSplitCols = IconsGridView.calculateColumnCount(for: 320)
        verify(narrowSplitCols == 2, "Узкий сплит-вью должен иметь 2 колонки")
        
        // Ландшафтный iPhone / 1/2 Split View (~700 pt)
        let landscapePhoneCols = IconsGridView.calculateColumnCount(for: 700)
        verify(landscapePhoneCols == 3, "Ландшафтный экран должен иметь 3 колонки")
        
        // Полноэкранный iPad (~1024 pt)
        let ipadCols = IconsGridView.calculateColumnCount(for: 1024)
        verify(ipadCols == 4, "Полноэкранный iPad должен иметь 4 колонки")
        
        // iPad Pro 12.9 (~1366 pt)
        let ipadProCols = IconsGridView.calculateColumnCount(for: 1366)
        verify(ipadProCols == 5, "iPad Pro должен иметь 5 колонок")
        
        print("  ✓ Число колонок динамически масштабируется по доступной ширине")
    }
    
    // MARK: - 4. Строгое правило доступности сравнения (ровно 2 кадра)
    func testStrictBatchComparisonCondition() {
        print("\n[4/6] Проверка строгого правила сравнения (доступно строго для 2 кадров)...")
        
        let appState = AppState()
        
        // 0 выбранных
        appState.selectedGroupIDs = []
        verify(!appState.canCompareSelected, "Сравнение недоступно при 0 выбранных")
        
        // 1 выбранный
        appState.selectedGroupIDs = ["photo-1"]
        verify(!appState.canCompareSelected, "Сравнение недоступно при 1 выбранном")
        
        // 2 выбранных
        appState.selectedGroupIDs = ["photo-1", "photo-2"]
        verify(appState.canCompareSelected, "Сравнение доступно СТРОГО для 2 выбранных кадров")
        
        // 3 выбранных
        appState.selectedGroupIDs = ["photo-1", "photo-2", "photo-3"]
        verify(!appState.canCompareSelected, "Сравнение недоступно при 3 выбранных")
        
        print("  ✓ Сравнение строго заблокировано, если выбрано не 2 кадра")
    }
    
    // MARK: - 5. Фильтрация и сортировка
    func testSortingAndFilterOptions() {
        print("\n[5/6] Проверка фильтров, счетчика и сброса...")
        
        let appState = AppState()
        verify(appState.activeFilterCount == 0, "Изначально активных фильтров нет")
        verify(!appState.hasActiveFilters)
        
        // Включаем фильтры
        appState.setRatingFilter(.stars4Plus)
        appState.setPickFilter(.picked)
        appState.toggleOnlyPaired()
        
        verify(appState.activeFilterCount == 3, "Должно быть 3 активных фильтра")
        verify(appState.hasActiveFilters)
        
        // Сброс фильтров
        appState.resetFilters()
        verify(appState.activeFilterCount == 0, "После сброса счетчик равен 0")
        verify(!appState.hasActiveFilters)
        verify(appState.ratingFilter == .all)
        verify(appState.pickFilter == .all)
        verify(!appState.onlyPaired)
        
        // Сортировка
        appState.setSortOrder(.nameAsc)
        verify(appState.sortOrder == .nameAsc)
        appState.setSortOrder(.ratingDesc)
        verify(appState.sortOrder == .ratingDesc)
        
        print("  ✓ Фильтры, счетчик, сброс и сортировка работают корректно")
    }
    
    // MARK: - 6. Безопасность названий сессий
    func testSessionNameLayoutSafety() {
        print("\n[6/6] Проверка безопасности коротких и длинных названий сессий...")
        
        let appState = AppState()
        
        // Короткое имя
        appState.startNewSession(named: "Студия")
        verify(appState.currentSession?.name == "Студия")
        
        // Длинное имя
        let longName = "Очень длинное название коммерческой фотосессии для каталога осенней одежды 2026/2027"
        appState.startNewSession(named: longName)
        verify(appState.currentSession?.name == longName)
        
        print("  ✓ Названия сессий поддерживают любую длину")
    }
}

@main
struct PhotosSectionRedesignTestRunner {
    static func main() async {
        let suite = await PhotosSectionRedesignVerificationTests()
        await suite.runAllTests()
    }
}
