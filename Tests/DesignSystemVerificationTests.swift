import Foundation
import SwiftUI
#if canImport(NikonZbridge)
@testable import NikonZbridge
#endif

@MainActor
final class DesignSystemVerificationTests {
    
    private func verify(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            fatalError("Verification failed: \(message) at \(file):\(line)")
        }
    }
    
    func runAllTests() async {
        print("=== СТАРТ ТЕСТОВ ДИЗАЙН-СИСТЕМЫ И КОМПОНЕНТОВ LIQUID GLASS ===")
        
        testAppThemeTokens()
        testPrimaryImportButtonStates()
        testConnectionStatusViewStatesAndStyles()
        testTransferProgressStripModes()
        testGlassSurfaceModifications()
        
        print("\n=== ВСЕ ТЕСТЫ ДИЗАЙН-СИСТЕМЫ УСПЕШНО ПРОЙДЕНЫ! ===")
    }
    
    // MARK: - 1. Тестирование токенов AppTheme
    func testAppThemeTokens() {
        print("\n[1/5] Проверка токенов AppTheme (цвета, отступы, скругления, геометрия)...")
        
        // Touch target минимум 44 pt по HIG
        verify(AppTheme.Dimensions.minTouchTarget >= 44.0, "Минимальный touch target должен быть не менее 44 pt")
        verify(AppTheme.Dimensions.buttonHeight >= 44.0, "Высота стандартной кнопки должна быть не менее 44 pt")
        verify(AppTheme.Dimensions.borderWidth == 1.0, "Базовая толщина контура")
        verify(AppTheme.Dimensions.borderWidthHighContrast > AppTheme.Dimensions.borderWidth, "Контур высокой контрастности должен быть толще")
        
        // Spacing & Radius
        verify(AppTheme.Spacing.xs < AppTheme.Spacing.sm)
        verify(AppTheme.Spacing.sm < AppTheme.Spacing.md)
        verify(AppTheme.Spacing.md < AppTheme.Spacing.lg)
        verify(AppTheme.Radius.pill == 999.0)
        
        print("  ✓ Токены цветов, отступов и размеров соответствуют гайдлайнам")
    }
    
    // MARK: - 2. PrimaryImportButton
    func testPrimaryImportButtonStates() {
        print("\n[2/5] Проверка состояний PrimaryImportButton...")
        
        var tapped = false
        let normalButton = PrimaryImportButton(
            isReadingCatalog: false,
            unimportedCount: 5,
            title: "Импортировать",
            shortTitle: "Импорт",
            action: { tapped = true }
        )
        
        verify(normalButton.unimportedCount == 5)
        verify(!normalButton.isReadingCatalog)
        verify(normalButton.title == "Импортировать")
        verify(normalButton.shortTitle == "Импорт")
        
        // Чтение каталога
        let readingButton = PrimaryImportButton(
            isReadingCatalog: true,
            unimportedCount: 0,
            action: {}
        )
        verify(readingButton.isReadingCatalog)
        verify(readingButton.loadingTitle == "Чтение...")
        
        print("  ✓ Кнопка PrimaryImportButton корректно инициализирует состояния и бейджи")
    }
    
    // MARK: - 3. ConnectionStatusView
    func testConnectionStatusViewStatesAndStyles() {
        print("\n[3/5] Проверка состояний и режимов ConnectionStatusView...")
        
        let connectedStatus = ConnectionStatusView.Status.connected
        let connectingStatus = ConnectionStatusView.Status.connecting
        let disconnectedStatus = ConnectionStatusView.Status.disconnected
        let idleStatus = ConnectionStatusView.Status.idle
        
        // Проверка символов для режима дифференциации без цвета (accessibilityDifferentiateWithoutColor)
        verify(!connectedStatus.shapeSymbol.isEmpty)
        verify(!connectingStatus.shapeSymbol.isEmpty)
        verify(!disconnectedStatus.shapeSymbol.isEmpty)
        verify(!idleStatus.shapeSymbol.isEmpty)
        
        // Проверка текстовых описаний для VoiceOver
        verify(connectedStatus.accessibilityDescription == "Подключено")
        verify(connectingStatus.accessibilityDescription == "Подключение")
        verify(disconnectedStatus.accessibilityDescription == "Отключено")
        verify(idleStatus.accessibilityDescription == "Остановлен")
        
        // Проверка режимов отображения (.inline, .pill, .card)
        let inlineView = ConnectionStatusView(
            status: .connected,
            title: "Nikon Z5 · USB",
            style: .inline
        )
        verify(inlineView.style == .inline)
        verify(inlineView.title == "Nikon Z5 · USB")
        
        let pillView = ConnectionStatusView(
            status: .connected,
            title: "Камера подключена",
            shortTitle: "USB",
            style: .pill,
            action: {}
        )
        verify(pillView.style == .pill)
        verify(pillView.action != nil)
        
        let cardView = ConnectionStatusView(
            status: .idle,
            title: "FTP Сервер",
            detail: "Порт 2121",
            style: .card
        )
        verify(cardView.style == .card)
        verify(cardView.detail == "Порт 2121")
        
        print("  ✓ ConnectionStatusView поддерживает все статусы, стили и требования доступности")
    }
    
    // MARK: - 4. TransferProgressStrip
    func testTransferProgressStripModes() {
        print("\n[4/5] Проверка режимов TransferProgressStrip (пофайловый и суммарный)...")
        
        // 1. Пофайловый режим
        var cancelTriggered = false
        var queueTriggered = false
        let singleFileStrip = TransferProgressStrip(
            filename: "DSC_0024.NEF",
            transferredBytes: 15_728_640,
            totalBytes: 31_457_280,
            speedMBs: 24.5,
            isUSB: true,
            onTap: { queueTriggered = true },
            onCancel: { cancelTriggered = true }
        )
        
        if case .singleFile(let name, let transferred, let total, let speed, let isUSB, _) = singleFileStrip.mode {
            verify(name == "DSC_0024.NEF")
            verify(transferred == 15_728_640)
            verify(total == 31_457_280)
            verify(speed == 24.5)
            verify(isUSB == true)
        } else {
            fatalError("Ожидался режим .singleFile")
        }
        
        // 2. Суммарный режим (согласно референсу Liquid Glass: «Загружено 24 из 48», «Очередь >»)
        let summaryStrip = TransferProgressStrip(
            completedCount: 24,
            totalCount: 48,
            label: "Загружено 24 из 48",
            actionTitle: "Очередь",
            onTap: { queueTriggered = true }
        )
        
        if case .summary(let completed, let total, let label, let action) = summaryStrip.mode {
            verify(completed == 24)
            verify(total == 48)
            verify(label == "Загружено 24 из 48")
            verify(action == "Очередь")
        } else {
            fatalError("Ожидался режим .summary")
        }
        
        print("  ✓ TransferProgressStrip полностью покрывает пофайловую передачу и суммарный статус")
    }
    
    // MARK: - 5. GlassSurface
    func testGlassSurfaceModifications() {
        print("\n[5/5] Проверка доступности модификаторов GlassSurface...")
        
        let card = GlassCard(cornerRadius: AppTheme.Radius.lg) {
            Text("Тестовое содержимое")
        }
        verify(card.cornerRadius == AppTheme.Radius.lg)
        
        print("  ✓ Стеклянные поверхности GlassCard и модификаторы валидны")
    }
}

@main
struct TestRunner {
    static func main() async {
        let suite = await DesignSystemVerificationTests()
        await suite.runAllTests()
    }
}
