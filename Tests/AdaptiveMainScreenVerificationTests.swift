import Foundation
import SwiftUI

@MainActor
final class AdaptiveMainScreenVerificationTests {
    
    private func verify(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            fatalError("Verification failed: \(message) at \(file):\(line)")
        }
    }
    
    func runAllTests() async {
        print("=== СТАРТ ТЕСТОВ МИНИМАЛИСТИЧНОГО АДАПТИВНОГО ГЛАВНОГО ЭКРАНА ===")
        
        testDefaultViewModeIsIconsGrid()
        testActiveFilterCountAndReset()
        testCompareAvailableStrictlyForTwoSelectedFrames()
        testSelectionModeAndBatchActions()
        testConnectionStatusInformativeTitles()
        testEmptyStateHidesGalleryControls()
        
        print("\n=== ВСЕ ТЕСТЫ АДАПТИВНОГО ГЛАВНОГО ЭКРАНА УСПЕШНО ПРОЙДЕНЫ! ===")
    }
    
    // MARK: - 1. Сетка фотографий по умолчанию
    func testDefaultViewModeIsIconsGrid() {
        print("\n[1/6] Тест: по умолчанию выбрана сетка фотографий (.icons)...")
        let appState = AppState()
        verify(appState.viewMode == .icons, "Режим отображения по умолчанию должен быть .icons (сетка)")
        verify(ViewMode.icons.rawValue == "Иконки" || ViewMode.icons.rawValue == "Сетка" || ViewMode.icons.iconName == "square.grid.2x2")
        print("  ✓ Сетка фотографий установлена по умолчанию")
    }
    
    // MARK: - 2. Подсчет активных фильтров и сброс
    func testActiveFilterCountAndReset() {
        print("\n[2/6] Тест: подсчет количества активных фильтров и действие сброса...")
        let appState = AppState()
        
        // Начальное состояние: все фильтры выключены (все форматы включены)
        verify(appState.activeFilterCount == 0, "Изначально количество активных фильтров должно быть 0")
        verify(!appState.hasActiveFilters, "hasActiveFilters должно быть false")
        
        // Отключаем RAW -> форматный фильтр активен (+1)
        appState.showRAW = false
        verify(appState.activeFilterCount == 1, "При отключении RAW activeFilterCount должен быть 1")
        verify(appState.hasActiveFilters)
        
        // Включаем «только пары» (+1)
        appState.onlyPaired = true
        verify(appState.activeFilterCount == 2, "RAW + onlyPaired дают 2 фильтра")
        
        // Включаем фильтр по рейтингу (+1)
        appState.setRatingFilter(.stars4Plus)
        verify(appState.activeFilterCount == 3, "Добавление рейтинга дает 3 фильтра")
        
        // Включаем фильтр по отбору (+1)
        appState.setPickFilter(.picked)
        verify(appState.activeFilterCount == 4, "Добавление флага отбора дает 4 фильтра")
        
        // Сбрасываем все фильтры
        appState.resetFilters()
        verify(appState.activeFilterCount == 0, "После resetFilters() счетчик активных фильтров должен быть 0")
        verify(!appState.hasActiveFilters, "После resetFilters() hasActiveFilters должно быть false")
        verify(appState.showRAW == true)
        verify(appState.showJPG == true)
        verify(appState.showHEIF == true)
        verify(appState.onlyPaired == false)
        verify(appState.ratingFilter == .all)
        verify(appState.pickFilter == .all)
        print("  ✓ Подсчет количества активных фильтров и сброс работают корректно")
    }
    
    private func createGroup(name: String, sessionID: UUID) -> CaptureGroup {
        let asset = MediaAsset(
            sessionID: sessionID,
            filename: "\(name).JPG",
            fileURL: URL(fileURLWithPath: "/tmp/\(name).JPG"),
            format: .jpeg,
            fileSize: 1024
        )
        return CaptureGroup(asset: asset)
    }
    
    // MARK: - 3. Сравнение доступно строго для 2 выбранных кадров
    func testCompareAvailableStrictlyForTwoSelectedFrames() {
        print("\n[3/6] Тест: сравнение доступно строго для двух выбранных кадров...")
        let appState = AppState()
        
        let sessionID = UUID()
        let g1 = createGroup(name: "DSC_0001", sessionID: sessionID)
        let g2 = createGroup(name: "DSC_0002", sessionID: sessionID)
        let g3 = createGroup(name: "DSC_0003", sessionID: sessionID)
        appState.captureGroups = [g1, g2, g3]
        
        // 0 выбранных
        verify(!appState.canCompareSelected, "При 0 выбранных сравнение должно быть недоступно")
        
        // 1 выбранный
        appState.toggleSelectGroup(g1)
        verify(appState.selectedGroupIDs.count == 1)
        verify(!appState.canCompareSelected, "При 1 выбранном кадре сравнение должно быть недоступно")
        
        // 2 выбранных
        appState.toggleSelectGroup(g2)
        verify(appState.selectedGroupIDs.count == 2)
        verify(appState.canCompareSelected, "При ровно 2 выбранных кадрах сравнение ДОЛЖНО быть доступно")
        
        // Запуск сравнения для 2 выбранных
        appState.presentCompareForSelected()
        verify(appState.isComparePresented, "isComparePresented должен стать true")
        verify(appState.selectedGroup?.id == g1.id || appState.selectedGroup?.id == g2.id)
        verify(appState.compareCandidateGroup?.id == g1.id || appState.compareCandidateGroup?.id == g2.id)
        verify(appState.selectedGroup?.id != appState.compareCandidateGroup?.id, "Сравниваемые кадры должны отличаться")
        
        // 3 выбранных -> сравнение снова недоступно
        appState.toggleSelectGroup(g3)
        verify(appState.selectedGroupIDs.count == 3)
        verify(!appState.canCompareSelected, "При 3 выбранных кадрах сравнение должно блокироваться")
        print("  ✓ Сравнение строго заблокировано, кроме случая выбора ровно двух кадров")
    }
    
    // MARK: - 4. Режим выбора и групповые действия
    func testSelectionModeAndBatchActions() {
        print("\n[4/6] Тест: режим выбора и групповые действия...")
        let appState = AppState()
        let sessionID = UUID()
        let g1 = createGroup(name: "DSC_1001", sessionID: sessionID)
        let g2 = createGroup(name: "DSC_1002", sessionID: sessionID)
        appState.captureGroups = [g1, g2]
        
        // Изначально выбор отключен
        verify(!appState.isSelectionMode)
        verify(appState.selectedGroupIDs.isEmpty)
        
        // Включаем режим выбора
        appState.isSelectionMode = true
        appState.selectAll()
        verify(appState.selectedGroupIDs.count == 2)
        
        // Массовый рейтинг
        appState.batchSetRating(5)
        verify(appState.captureGroups.allSatisfy { $0.rating == 5 })
        
        // Массовый флаг
        appState.batchSetPickStatus(.picked)
        verify(appState.captureGroups.allSatisfy { $0.pickStatus == .picked })
        
        // Снятие выбора
        appState.clearSelection()
        verify(appState.selectedGroupIDs.isEmpty)
        print("  ✓ Групповые действия и режим выбора функционируют штатно")
    }
    
    // MARK: - 5. Информативные статусы подключения (не только цветом)
    func testConnectionStatusInformativeTitles() {
        print("\n[5/6] Тест: статус подключения не зависит только от цвета...")
        let appState = AppState()
        
        // Отключено
        verify(!appState.connectionStatusTitle.isEmpty)
        verify(!appState.shortConnectionStatusTitle.isEmpty)
        verify(appState.shortConnectionStatusTitle == "Откл.")
        
        // USB подключен
        appState.usbConnected = true
        appState.usbCameraName = "Nikon Z 8"
        verify(appState.connectionStatusTitle.contains("Z 8") || appState.connectionStatusTitle.contains("USB"))
        verify(appState.shortConnectionStatusTitle == "USB")
        print("  ✓ Текстовые статусы подключения содержат полные и краткие информативные метки")
    }
    
    // MARK: - 6. Скрытие инструментов отбора при пустой галерее
    func testEmptyStateHidesGalleryControls() {
        print("\n[6/6] Тест: скрытие инструментов отбора при пустой галерее...")
        let appState = AppState()
        appState.captureGroups = []
        
        let state = appState.mainScreenState
        verify(!state.hasPhotos, "При пустой сессии hasPhotos должен быть false")
        verify(state.emptyState != nil, "При пустой сессии emptyState должен быть активен")
        
        // Добавляем кадр -> инструменты становятся доступны, пустой экран исчезает
        let g = createGroup(name: "DSC_9999", sessionID: UUID())
        appState.captureGroups = [g]
        
        let stateWithPhoto = appState.mainScreenState
        verify(stateWithPhoto.hasPhotos, "После добавления кадра hasPhotos становится true")
        verify(stateWithPhoto.emptyState == nil, "После добавления кадра emptyState становится nil")
        print("  ✓ Инструменты отбора активны только при наличии фотографий в сессии")
    }
}

// Точка входа для отдельного бинарного запуска тестов
@main
struct TestRunner {
    static func main() async {
        let suite = await AdaptiveMainScreenVerificationTests()
        await suite.runAllTests()
    }
}
