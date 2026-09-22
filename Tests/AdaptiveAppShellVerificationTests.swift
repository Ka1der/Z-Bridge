import Foundation
import SwiftUI
#if canImport(NikonZbridge)
@testable import NikonZbridge
#endif

@MainActor
final class AdaptiveAppShellVerificationTests {
    
    private func verify(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            fatalError("Verification failed: \(message) at \(file):\(line)")
        }
    }
    
    func runAllTests() async {
        print("=== СТАРТ ТЕСТОВ АДАПТИВНОГО КАРКАСА ПРИЛОЖЕНИЯ ===")
        
        testLayoutResolverWidthAndDynamicType()
        testSectionsEnumAndDefaultSelection()
        testStatePreservationAcrossSectionSwitches()
        testActiveTransferPreservationAcrossSectionSwitches()
        testSettingsAvailabilityFlag()
        
        print("\n=== ВСЕ ТЕСТЫ АДАПТИВНОГО КАРКАСА УСПЕШНО ПРОЙДЕНЫ! ===")
    }
    
    // MARK: - 1. Тест расчета компоновки (ширина + Dynamic Type, без UIDevice)
    func testLayoutResolverWidthAndDynamicType() {
        print("\n[1/5] Проверка резолвера компоновки (AdaptiveLayoutResolver)...")
        
        // Стандартный размер шрифта (Large)
        // 1. Узкое окно: iPhone в портрете (393 pt)
        let iphonePortrait = AdaptiveLayoutResolver.resolve(width: 393, dynamicTypeSize: .large)
        verify(iphonePortrait == .narrow, "iPhone в портрете должен использовать узкую компоновку (.narrow)")
        
        // 2. Узкое окно: iPad в Split View 1/3 (320 pt)
        let ipadSplitView1_3 = AdaptiveLayoutResolver.resolve(width: 320, dynamicTypeSize: .large)
        verify(ipadSplitView1_3 == .narrow, "iPad в 1/3 Split View должен использовать узкую компоновку (.narrow)")
        
        // 3. Широкое окно: iPad в полноэкранном режиме (1024 pt)
        let ipadFullScreen = AdaptiveLayoutResolver.resolve(width: 1024, dynamicTypeSize: .large)
        verify(ipadFullScreen == .wide, "iPad в полноэкранном режиме должен использовать широкую компоновку (.wide)")
        
        // 4. Поворот iPhone в ландшафт: ширина 852 pt
        let iphoneLandscape = AdaptiveLayoutResolver.resolve(width: 852, dynamicTypeSize: .large)
        verify(iphoneLandscape == .wide, "Широкий экран ландшафтного iPhone должен поддерживать боковую панель (.wide)")
        
        // 5. Учет размера текста: при экстремально крупном шрифте (.accessibility5)
        // порог динамически повышается (680 * 1.9 = 1292 pt) -> окно 852 pt переключается на узкую компоновку (.narrow)
        let iphoneLandscapeLargeText = AdaptiveLayoutResolver.resolve(width: 852, dynamicTypeSize: .accessibility5)
        verify(iphoneLandscapeLargeText == .narrow, "При экстремальном размере текста экран должен переключиться на .narrow для предотвращения сжатия интерфейса")
        
        print("  ✓ Компоновка корректно вычисляется по ширине и Dynamic Type без привязки к UIDevice")
    }
    
    // MARK: - 2. Перечисление разделов и начальное состояние
    func testSectionsEnumAndDefaultSelection() {
        print("\n[2/5] Проверка перечисления разделов AppSection...")
        
        let sections = AppSection.allCases
        verify(sections.count == 3, "Должно быть ровно 3 раздела: Снимки, Камера, Сессии")
        verify(sections.contains(.photos))
        verify(sections.contains(.camera))
        verify(sections.contains(.sessions))
        
        verify(AppSection.photos.rawValue == "Снимки")
        verify(AppSection.camera.rawValue == "Камера")
        verify(AppSection.sessions.rawValue == "Сессии")
        
        verify(!AppSection.photos.iconName.isEmpty)
        verify(!AppSection.camera.iconName.isEmpty)
        verify(!AppSection.sessions.iconName.isEmpty)
        
        let appState = AppState()
        verify(appState.selectedSection == .photos, "По умолчанию выбран раздел «Снимки»")
        
        print("  ✓ Разделы определены, иконки заданы, выбор по умолчанию .photos")
    }
    
    // MARK: - 3. Сохранение состояния при переключении разделов
    func testStatePreservationAcrossSectionSwitches() {
        print("\n[3/5] Проверка сохранения состояния выше адаптивных представлений...")
        
        let appState = AppState()
        
        // 1. Устанавливаем специфическое состояние галереи:
        // Режим просмотра .table, фильтры, выделение
        appState.viewMode = .table
        appState.showRAW = false
        appState.onlyPaired = true
        appState.setRatingFilter(.stars4Plus)
        appState.setPickFilter(.picked)
        appState.isSelectionMode = true
        let mockID = UUID().uuidString
        appState.selectedGroupIDs = [mockID]
        
        // 2. Переключаемся в раздел «Камера»
        appState.selectedSection = .camera
        verify(appState.selectedSection == .camera)
        
        // Проверяем, что все свойства галереи сохранились без изменений
        verify(appState.viewMode == .table, "viewMode не должен сбрасываться")
        verify(!appState.showRAW, "showRAW не должен сбрасываться")
        verify(appState.onlyPaired, "onlyPaired не должен сбрасываться")
        verify(appState.ratingFilter == .stars4Plus, "Рейтинг-фильтр должен сохраниться")
        verify(appState.pickFilter == .picked, "Флаг отбора должен сохраниться")
        verify(appState.isSelectionMode, "Режим выбора должен сохраниться")
        verify(appState.selectedGroupIDs.contains(mockID), "Выделенные кадры должны сохраниться")
        
        // 3. Переключаемся в раздел «Сессии»
        appState.selectedSection = .sessions
        verify(appState.selectedSection == .sessions)
        verify(appState.viewMode == .table)
        
        // 4. Возвращаемся в раздел «Снимки»
        appState.selectedSection = .photos
        verify(appState.selectedSection == .photos)
        verify(appState.viewMode == .table)
        verify(appState.selectedGroupIDs.contains(mockID))
        
        print("  ✓ Состояние (раздел, режим просмотра, фильтры, выделение) полностью сохраняется")
    }
    
    // MARK: - 4. Сохранение активной очереди и передачи при смене разделов
    func testActiveTransferPreservationAcrossSectionSwitches() {
        print("\n[4/5] Проверка непрерывности передачи при смене разделов...")
        
        let appState = AppState()
        
        // Создаем мок задания передачи
        let job = TransferJob(
            id: UUID(),
            source: CameraSource(id: "cam-test", model: "Nikon Z 8", transportType: .usb),
            sourceFileID: "DSC_9999.NEF",
            destinationURL: URL(fileURLWithPath: "/tmp/DSC_9999.NEF"),
            stagingURL: URL(fileURLWithPath: "/tmp/DSC_9999.tmp"),
            sessionID: UUID(),
            state: .inProgress(progress: 0.5, bytesTransferred: 10_000_000, totalBytes: 20_000_000),
            totalBytes: 20_000_000
        )
        
        appState.activeJobs = [job]
        verify(appState.activeTransferJob?.id == job.id, "Активное задание зарегистрировано")
        verify(appState.activeQueueCount == 1)
        
        // Переключаем раздел: Снимки -> Камера -> Сессии -> Снимки
        appState.selectedSection = .camera
        verify(appState.activeTransferJob?.id == job.id, "Задание активно в разделе «Камера»")
        
        appState.selectedSection = .sessions
        verify(appState.activeTransferJob?.id == job.id, "Задание активно в разделе «Сессии»")
        
        appState.selectedSection = .photos
        verify(appState.activeTransferJob?.id == job.id, "Задание активно при возврате в «Снимки»")
        
        print("  ✓ Активная передача и очередь непрерывны при переходах между разделами")
    }
    
    // MARK: - 5. Доступность настроек
    func testSettingsAvailabilityFlag() {
        print("\n[5/5] Проверка флага доступности настроек...")
        
        let appState = AppState()
        verify(!appState.isSettingsPresented, "Изначально настройки закрыты")
        
        appState.isSettingsPresented = true
        verify(appState.isSettingsPresented, "Настройки открываются централизованным флагом каркаса")
        
        appState.isSettingsPresented = false
        verify(!appState.isSettingsPresented)
        
        print("  ✓ Флаг настроек isSettingsPresented работает корректно")
    }
}

@main
struct AdaptiveAppShellTestRunner {
    static func main() async {
        let suite = AdaptiveAppShellVerificationTests()
        await suite.runAllTests()
    }
}
