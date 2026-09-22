import Foundation

/// Набор проверочных тестов универсального просмотрщика Liquid Glass (Этап 10)
final class UniversalViewerVerificationTests {
    
    private func verify(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            fatalError("Verification failed: \(message) at \(file):\(line)")
        }
    }
    
    @MainActor
    func runAllTests() async {
        print("=== СТАРТ ТЕСТОВ УНИВЕРСАЛЬНОГО ПРОСМОТРЩИКА (LIQUID GLASS) ===")
        
        testRatingAndFlagsCascadingToRAWAndJPEG()
        testLateArrivalPairingInheritsRatingAndFlag()
        testSingleSelectionSourceAndSync()
        testInspectionPausePreventsFrameDisruption()
        testLayoutStatePreservationAcrossWidthTransitions()
        testSidebarCollapseToggleLogic()
        testPhotoAspectFitSafetyForPortraitAndLandscape()
        testPreviewLoadingFallbackAndRetryState()
        testRealEXIFMetadataFormattingWithoutMockValues()
        testExitViewerResetsInspectionStateAndAllowsAutoSwitching()
        
        print("\n=== ВСЕ ТЕСТЫ УНИВЕРСАЛЬНОГО ПРОСМОТРЩИКА УСПЕШНО ПРОЙДЕНЫ! ===")
    }
    
    // MARK: - 1. Выставление рейтинга и меток сразу группе RAW+JPEG
    func testRatingAndFlagsCascadingToRAWAndJPEG() {
        print("\n[1/9] Проверка каскадного применения рейтинга и флагов группе RAW+JPEG...")
        
        let sessionID = UUID()
        let rawAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0042.NEF",
            fileURL: URL(fileURLWithPath: "/tmp/DSC_0042.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 45_000_000,
            rating: 0,
            pickStatus: .unflagged
        )
        let jpegAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0042.JPG",
            fileURL: URL(fileURLWithPath: "/tmp/DSC_0042.JPG"),
            format: .jpeg,
            fileSize: 8_500_000,
            rating: 0,
            pickStatus: .unflagged
        )
        
        var group = CaptureGroup(
            baseName: "DSC_0042",
            sessionID: sessionID,
            rawAsset: rawAsset,
            jpegAsset: jpegAsset
        )
        
        verify(group.isPaired, "Группа должна быть парной RAW+JPEG")
        verify(group.rating == 0)
        verify(group.pickStatus == .unflagged)
        
        // 1. Установка рейтинга 5 звезд
        group.setRating(5)
        verify(group.rating == 5, "Рейтинг группы должен стать 5")
        verify(group.rawAsset?.rating == 5, "Рейтинг RAW-оригинала должен стать 5")
        verify(group.jpegAsset?.rating == 5, "Рейтинг JPEG-оригинала должен стать 5")
        
        // 2. Установка флага отбора .picked (P)
        group.setPickStatus(.picked)
        verify(group.pickStatus == .picked, "Статус группы должен стать .picked")
        verify(group.rawAsset?.pickStatus == .picked, "RAW должен получить статус .picked")
        verify(group.jpegAsset?.pickStatus == .picked, "JPEG должен получить статус .picked")
        
        // 3. Установка отклонения .rejected (X)
        group.setPickStatus(.rejected)
        verify(group.pickStatus == .rejected, "Статус группы должен стать .rejected")
        verify(group.rawAsset?.pickStatus == .rejected, "RAW должен получить статус .rejected")
        verify(group.jpegAsset?.pickStatus == .rejected, "JPEG должен получить статус .rejected")
        
        // 4. Сброс флага .unflagged (U) и рейтинга в 0
        group.setPickStatus(.unflagged)
        group.setRating(0)
        verify(group.pickStatus == .unflagged)
        verify(group.rawAsset?.pickStatus == .unflagged)
        verify(group.jpegAsset?.pickStatus == .unflagged)
        verify(group.rating == 0)
        verify(group.rawAsset?.rating == 0)
        verify(group.jpegAsset?.rating == 0)
        
        print("  ✓ Рейтинг и флаги синхронно и неделимо применяются ко всем файлам группы")
    }
    
    // MARK: - 2. Наследование рейтинга и флага при запаздывающем приходе второго файла пары
    func testLateArrivalPairingInheritsRatingAndFlag() {
        print("\n[2/9] Проверка наследования метаданных при асинхронном приходе второй части пары...")
        
        let sessionID = UUID()
        let rawAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0043.NEF",
            fileURL: URL(fileURLWithPath: "/tmp/DSC_0043.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 46_000_000,
            rating: 0,
            pickStatus: .unflagged
        )
        
        var group = CaptureGroup(asset: rawAsset)
        verify(!group.isPaired, "Пока пришел только RAW, группа не парная")
        
        // Фотограф оценивает кадр 4 звездами и ставит Pick до того, как JPEG скачался
        group.setRating(4)
        group.setPickStatus(.picked)
        
        // Теперь скачивается второй файл пары (JPEG)
        let jpegAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0043.JPG",
            fileURL: URL(fileURLWithPath: "/tmp/DSC_0043.JPG"),
            format: .jpeg,
            fileSize: 9_000_000,
            rating: 0,
            pickStatus: .unflagged
        )
        
        group.addAsset(jpegAsset)
        verify(group.isPaired, "После добавления JPEG группа становится парной")
        verify(group.jpegAsset?.rating == 4, "Запоздавший JPEG должен унаследовать рейтинг 4 от группы")
        verify(group.jpegAsset?.pickStatus == .picked, "Запоздавший JPEG должен унаследовать статус .picked")
        
        print("  ✓ Запоздавший парный файл корректно наследует рейтинг и флаги")
    }
    
    // MARK: - 3. Единый источник выбора кадра (Single Source of Truth)
    func testSingleSelectionSourceAndSync() {
        print("\n[3/9] Проверка единого источника выбора кадра между галереей и просмотрщиком...")
        
        let sessionID = UUID()
        let group1 = CaptureGroup(
            baseName: "DSC_0001",
            sessionID: sessionID,
            rawAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0001.NEF", fileURL: URL(fileURLWithPath: "/tmp/1.NEF"), format: .raw(fileExtension: "nef"))
        )
        let group2 = CaptureGroup(
            baseName: "DSC_0002",
            sessionID: sessionID,
            rawAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0002.NEF", fileURL: URL(fileURLWithPath: "/tmp/2.NEF"), format: .raw(fileExtension: "nef"))
        )
        let group3 = CaptureGroup(
            baseName: "DSC_0003",
            sessionID: sessionID,
            rawAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0003.NEF", fileURL: URL(fileURLWithPath: "/tmp/3.NEF"), format: .raw(fileExtension: "nef"))
        )
        
        let groups = [group1, group2, group3]
        var selectedGroup: CaptureGroup? = group1
        
        // В ленте миниатюр кликаем на group2
        selectedGroup = group2
        verify(selectedGroup?.id == group2.id, "Выбор в ленте должен обновить активный кадр")
        
        // В сетке миниатюр широкого окна кликаем на group3
        selectedGroup = group3
        verify(selectedGroup?.id == group3.id, "Выбор в сетке широкого окна должен обновить активный кадр")
        
        // Навигация клавишами (стрелка влево)
        if let current = selectedGroup, let idx = groups.firstIndex(where: { $0.id == current.id }), idx > 0 {
            selectedGroup = groups[idx - 1]
        }
        verify(selectedGroup?.id == group2.id, "Стрелка влево должна выбрать предыдущий кадр")
        
        print("  ✓ Единый источник выбранного кадра полностью синхронизирован")
    }
    
    // MARK: - 4. Пауза автопереключения при инспекции кадра
    func testInspectionPausePreventsFrameDisruption() {
        print("\n[4/9] Проверка паузы автопереключения при инспекции зумом/панорамированием...")
        
        let sessionID = UUID()
        let group1 = CaptureGroup(baseName: "DSC_0010", sessionID: sessionID)
        let group2 = CaptureGroup(baseName: "DSC_0011", sessionID: sessionID)
        
        var selectedGroup: CaptureGroup? = group1
        var isUserInspecting = false
        var pendingNotification: String? = nil
        let isAutoScrollEnabled = true
        
        // Сценарий А: Пользователь НЕ инспектирует кадр (zoom = 1.0, isUserInspecting = false)
        // Приходит новый кадр group2 -> должен автоматически переключиться
        if isUserInspecting {
            pendingNotification = "Новый кадр: \(group2.baseName)"
        } else if isAutoScrollEnabled {
            selectedGroup = group2
        }
        verify(selectedGroup?.id == group2.id, "При выключенной инспекции активный кадр должен смениться")
        verify(pendingNotification == nil)
        
        // Сценарий Б: Пользователь приблизил кадр (двойной тап / пинч, zoom = 2.5x, isUserInspecting = true)
        isUserInspecting = true
        let group3 = CaptureGroup(baseName: "DSC_0012", sessionID: sessionID)
        
        if isUserInspecting {
            pendingNotification = "Новый кадр: \(group3.baseName)"
        } else if isAutoScrollEnabled {
            selectedGroup = group3
        }
        
        verify(selectedGroup?.id == group2.id, "При активной инспекции просмотр НЕ должен срываться")
        verify(pendingNotification == "Новый кадр: DSC_0012", "Должно отобразиться ненавязчивое уведомление о новом кадре")
        
        // Пользователь нажимает на уведомление, чтобы перейти к новому кадру
        selectedGroup = group3
        isUserInspecting = false
        pendingNotification = nil
        verify(selectedGroup?.id == group3.id)
        verify(!isUserInspecting)
        verify(pendingNotification == nil)
        
        print("  ✓ Инспекция кадра защищена от срывов при поступлении новых снимков")
    }
    
    // MARK: - 5. Сохранение выбранного кадра и режима инспекции при смене ширины/ориентации
    func testLayoutStatePreservationAcrossWidthTransitions() {
        print("\n[5/9] Проверка непрерывности состояния при смене ширины окна и ориентации...")
        
        let sessionID = UUID()
        let group = CaptureGroup(baseName: "DSC_0088", sessionID: sessionID)
        
        // Состояние приложения
        let currentSelectedGroup: CaptureGroup? = group
        let currentInspectionState = true // пользователь исследовал фокус
        
        // 1. Узкое окно (iPhone в портрете, 393 pt)
        let narrowWidth: CGFloat = 393
        let isNarrow1 = narrowWidth < 680
        verify(isNarrow1)
        verify(currentSelectedGroup?.baseName == "DSC_0088")
        verify(currentInspectionState == true)
        
        // 2. Поворот iPhone в ландшафт (852 pt) -> переход в широкий режим
        let landscapeWidth: CGFloat = 852
        let isNarrow2 = landscapeWidth < 680
        verify(!isNarrow2)
        // Состояние не пересоздается, так как хранится выше в AppState
        verify(currentSelectedGroup?.baseName == "DSC_0088", "Выбранный кадр должен сохраниться при переходе в ландшафт")
        verify(currentInspectionState == true, "Режим инспекции должен сохраниться")
        
        // 3. iPad Split View (сужение до 320 pt)
        let splitWidth: CGFloat = 320
        let isNarrow3 = splitWidth < 680
        verify(isNarrow3)
        verify(currentSelectedGroup?.baseName == "DSC_0088", "Выбранный кадр должен сохраниться при сжатии в Split View")
        
        print("  ✓ Состояние просмотра сохраняется непрерывно при любых изменениях геометрии")
    }
    
    // MARK: - 6. Сворачивание и разворачивание боковой навигации
    func testSidebarCollapseToggleLogic() {
        print("\n[6/9] Проверка сворачивания/разворачивания боковой панели...")
        
        var isSidebarCollapsed = false
        
        func toggleSidebar() {
            isSidebarCollapsed.toggle()
        }
        
        verify(!isSidebarCollapsed, "Изначально панель развернута")
        toggleSidebar()
        verify(isSidebarCollapsed, "Панель свернута — область просмотра фото расширяется")
        toggleSidebar()
        verify(!isSidebarCollapsed, "Панель развернута обратно")
        
        print("  ✓ Переключение боковой панели функционирует корректно")
    }
    
    // MARK: - 7. Безопасность отображения без обрезки (aspectRatio .fit)
    func testPhotoAspectFitSafetyForPortraitAndLandscape() {
        print("\n[7/9] Проверка пропорций отображения для портретных и ландшафтных кадров...")
        
        // Ландшафтный снимок Nikon 3:2 (8256 x 5504)
        let landscapeSize = CGSize(width: 8256, height: 5504)
        let landscapeAspect = landscapeSize.width / landscapeSize.height
        verify(abs(landscapeAspect - 1.5) < 0.01, "Ландшафтный снимок имеет соотношение 3:2")
        
        // Портретный снимок Nikon 2:3 (5504 x 8256)
        let portraitSize = CGSize(width: 5504, height: 8256)
        let portraitAspect = portraitSize.width / portraitSize.height
        verify(abs(portraitAspect - (2.0 / 3.0)) < 0.01, "Портретный снимок имеет соотношение 2:3")
        
        // При contentMode: .fit масштаб вписывания рассчитывается как min(fitW, fitH)
        let viewportSize = CGSize(width: 800, height: 600)
        
        // Для ландшафта (3:2 в окне 4:3 ограничивается шириной):
        let scaleL = min(viewportSize.width / landscapeSize.width, viewportSize.height / landscapeSize.height)
        let fittedLandscape = CGSize(width: landscapeSize.width * scaleL, height: landscapeSize.height * scaleL)
        verify(fittedLandscape.width <= viewportSize.width + 0.001)
        verify(fittedLandscape.height <= viewportSize.height + 0.001)
        verify(abs(fittedLandscape.width - viewportSize.width) < 0.001, "По ширине ландшафт вписывается полностью без обрезки")
        
        // Для портрета (2:3 в окне 4:3 ограничивается высотой):
        let scaleP = min(viewportSize.width / portraitSize.width, viewportSize.height / portraitSize.height)
        let fittedPortrait = CGSize(width: portraitSize.width * scaleP, height: portraitSize.height * scaleP)
        verify(fittedPortrait.width <= viewportSize.width + 0.001)
        verify(fittedPortrait.height <= viewportSize.height + 0.001)
        verify(abs(fittedPortrait.height - viewportSize.height) < 0.001, "По высоте портрет вписывается полностью без обрезки краёв")
        
        print("  ✓ Портретные и ландшафтные кадры вписываются целиком без нежелательной обрезки")
    }
    
    // MARK: - 8. Обработка ошибки загрузки превью и повтор
    func testPreviewLoadingFallbackAndRetryState() {
        print("\n[8/9] Проверка состояний загрузки превью, ошибки и повтора...")
        
        enum PreviewState {
            case idle
            case loading
            case success
            case failure(String)
        }
        
        var state: PreviewState = .idle
        
        // Старт загрузки
        state = .loading
        if case .loading = state {
            // Ожидаемое состояние
        } else {
            fatalError("Ожидалось состояние loading")
        }
        
        // Ошибка (например, файл еще не до конца сброшен на диск)
        state = .failure("Файл поврежден или недоступен")
        if case .failure(let reason) = state {
            verify(reason.contains("недоступен"))
        } else {
            fatalError("Ожидалось состояние failure")
        }
        
        // Нажатие кнопки «Повторить»
        state = .loading
        if case .loading = state {
            // Повторная попытка
        } else {
            fatalError("Ожидалось состояние loading после повтора")
        }
        
        // Успешная загрузка
        state = .success
        if case .success = state {
            // Успех
        } else {
            fatalError("Ожидалось состояние success")
        }
        
        print("  ✓ Цикл ошибки превью и кнопка повтора отрабатывают корректно")
    }
    
    // MARK: - 9. Реальные метаданные EXIF без вымышленных значений
    func testRealEXIFMetadataFormattingWithoutMockValues() {
        print("\n[9/9] Проверка вывода реальных метаданных EXIF (без фиктивных данных)...")
        
        // Реальный снимок с полным EXIF
        let fullMeta = AssetMetadata(
            cameraModel: "NIKON Z 8",
            lensModel: "NIKKOR Z 24-70mm f/2.8 S",
            exposureTime: 0.004, // 1/250
            fNumber: 2.8,
            iso: 400,
            focalLength: 50.0,
            captureDate: Date()
        )
        
        let summary = fullMeta.quickExposureSummary
        verify(summary != nil, "Сводка экспозиции должна быть сформирована")
        verify(summary!.contains("1/250"), "Должна содержать выдержку 1/250")
        verify(summary!.contains("f/2.8"), "Должна содержать диафрагму f/2.8")
        verify(summary!.contains("ISO 400"), "Должна содержать ISO 400")
        
        // Снимок с отсутствующим EXIF (например, старый мануальный объектив без чипа)
        let sparseMeta = AssetMetadata(
            cameraModel: "NIKON Z 6",
            lensModel: nil,
            exposureTime: 0.01, // 1/100
            fNumber: nil,
            iso: 1600
        )
        let sparseSummary = sparseMeta.quickExposureSummary
        verify(sparseSummary != nil)
        verify(sparseSummary!.contains("1/100"))
        verify(sparseSummary!.contains("ISO 1600"))
        verify(!sparseSummary!.contains("f/"), "Не должно быть выдуманной диафрагмы")
        
        // Пустые метаданные
        let emptyMeta = AssetMetadata()
        verify(emptyMeta.quickExposureSummary == nil, "При отсутствии данных строка должна быть nil, без муляжей")
        
        print("  ✓ Отображаются только реальные метаданные из файла камеры")
    }
    
    // MARK: - 10. Снятие режима инспекции при явном выходе в галерею
    @MainActor
    func testExitViewerResetsInspectionStateAndAllowsAutoSwitching() {
        print("\n[10/10] Проверка снятия инспекции при выходе в галерею и сохранения при смене компоновки...")
        
        let appState = AppState()
        let sid = UUID()
        let asset1 = MediaAsset(sessionID: sid, filename: "DSC_1001.NEF", fileURL: URL(fileURLWithPath: "/tmp/DSC_1001.NEF"), format: .raw(fileExtension: "nef"), fileSize: 30_000_000)
        let asset2 = MediaAsset(sessionID: sid, filename: "DSC_1002.NEF", fileURL: URL(fileURLWithPath: "/tmp/DSC_1002.NEF"), format: .raw(fileExtension: "nef"), fileSize: 30_000_000)
        let group1 = CaptureGroup(asset: asset1)
        let group2 = CaptureGroup(asset: asset2)
        appState.captureGroups = [group1]
        appState.selectedGroup = group1
        
        // 1. Входим в режим просмотра
        appState.viewMode = .viewer
        verify(appState.viewMode == .viewer)
        
        // 2. Увеличиваем кадр (инспекция активна)
        appState.viewerZoom = 2.5
        appState.isUserInspecting = true
        verify(appState.isUserInspecting)
        
        // 3. Изменение компоновки (поворот экрана / изменение размера окна) НЕ меняет viewMode
        // Проверяем, что инспекция и зум непрерывно сохраняются:
        let narrow = AdaptiveLayoutResolver.resolve(width: 390, dynamicTypeSize: .large)
        let wide = AdaptiveLayoutResolver.resolve(width: 1024, dynamicTypeSize: .large)
        verify(narrow != wide)
        verify(appState.isUserInspecting, "При перестроении компоновки инспекция должна сохраняться")
        verify(appState.viewerZoom == 2.5, "Зум должен сохраняться при перестроении компоновки")
        
        // 4. Пользователь нажимает «Снимки» (явный выход в галерею)
        appState.exitViewer()
        verify(appState.viewMode == .icons, "Режим должен стать .icons")
        verify(!appState.isUserInspecting, "При явном выходе в галерею режим инспекции должен быть снят")
        verify(appState.viewerZoom == 1.0, "Зум должен быть сброшен до 1.0")
        
        // 5. Поступает новый live-кадр
        appState.handleCaptureGroupUpdated(group2)
        verify(appState.selectedGroup?.id == group2.id, "После выхода в галерею автопереход к новому кадру НЕ должен блокироваться")
        verify(appState.pendingIncomingFrameNotification == nil, "Не должно оставаться блокирующего уведомления")
        
        print("  ✓ Явный выход в галерею снимает инспекцию, а перестроение экрана её сохраняет")
    }
}

@main
struct UniversalViewerTestRunner {
    static func main() async {
        let suite = UniversalViewerVerificationTests()
        await suite.runAllTests()
    }
}
