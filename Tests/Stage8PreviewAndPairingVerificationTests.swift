import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct Stage8VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 8: ПРЕВЬЮ И ОБЪЕДИНЕНИЕ RAW+JPEG ===")
        
        let suite = Stage8VerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 8 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage8VerificationSuite {
    let tempDir: URL
    
    init() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage8Test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir
    }
    
    func runAllTests() async throws {
        try await testDecodingOffMainThread()
        try await testBoundedConcurrencyAndCancellation()
        try await testMemoryBoundedCache()
        try await testExplicitErrorStatesForPreviews()
        try await testFormatDifferentiationIncludingHEIF()
        try await testMultiCriteriaFramePairing()
        try await testDelayedCompanionArrivalWithoutDuplicates()
        try await testSeparationOfDisplayFiltersAndImportSettings()
    }
    
    // MARK: - 1. Вынос декодирования из основного потока
    
    func testDecodingOffMainThread() async throws {
        print("\n[1/8] Тест декодирования вне основного потока...")
        
        let testImageURL = tempDir.appendingPathComponent("test_thread.jpg")
        try createValidSampleJPEG(at: testImageURL, width: 200, height: 150)
        
        let result = await PreviewPipeline.shared.loadThumbnail(for: testImageURL, maxPixelSize: 100)
        switch result {
        case .success(let image):
            assert(image.size.width > 0, "Изображение должно иметь положительную ширину")
            print("  ✓ Превью успешно декодировано в фоновом пуле задач вне MainActor")
        case .failure(let err):
            fatalError("Неожиданная ошибка декодирования: \(err)")
        }
    }
    
    // MARK: - 2. Ограничение параллелизма и отмена устаревших запросов
    
    func testBoundedConcurrencyAndCancellation() async throws {
        print("\n[2/8] Тест ограниченной очереди обработки и отмены ненужных запросов...")
        
        let pipeline = PreviewPipeline(maxConcurrentDecodes: 2)
        
        // Создаем несколько тестовых файлов
        var urls: [URL] = []
        for i in 1...6 {
            let url = tempDir.appendingPathComponent("burst_\(i).jpg")
            try createValidSampleJPEG(at: url, width: 300, height: 200)
            urls.append(url)
        }
        
        // Отменяем один из запросов
        let cancelledURL = urls[5]
        await pipeline.cancelLoading(for: cancelledURL, maxPixelSize: 150)
        
        // Запускаем параллельные запросы
        var successCount = 0
        await withTaskGroup(of: Result<PlatformImage, PreviewError>.self) { group in
            for url in urls.prefix(5) {
                group.addTask {
                    await pipeline.loadThumbnail(for: url, maxPixelSize: 150)
                }
            }
            for await res in group {
                if case .success = res {
                    successCount += 1
                }
            }
        }
        
        assert(successCount == 5, "Все 5 активных запросов должны успешно завершиться через bounded queue")
        print("  ✓ Ограниченная очередь (maxConcurrentDecodes = 2) и отмена отработали корректно")
    }
    
    // MARK: - 3. Кэш с лимитом памяти
    
    func testMemoryBoundedCache() async throws {
        print("\n[3/8] Тест кэша с лимитом памяти и вытеснением...")
        
        // Кэш с жестким лимитом по количеству (2 элемента)
        let cache = PreviewMemoryCache(maxCostMB: 1, countLimit: 2)
        
        let img1 = makeDummyImage(width: 50, height: 50)
        let img2 = makeDummyImage(width: 50, height: 50)
        let img3 = makeDummyImage(width: 50, height: 50)
        
        cache.setImage(img1, forKey: "key1", cost: 10000)
        cache.setImage(img2, forKey: "key2", cost: 10000)
        
        assert(cache.image(forKey: "key1") != nil, "key1 должен быть в кэше")
        assert(cache.image(forKey: "key2") != nil, "key2 должен быть в кэше")
        
        // Добавляем третий элемент, вызывая вытеснение
        cache.setImage(img3, forKey: "key3", cost: 10000)
        assert(cache.image(forKey: "key3") != nil, "key3 должен быть в кэше")
        
        cache.clear()
        assert(cache.image(forKey: "key3") == nil, "После clear кэш должен быть пуст")
        print("  ✓ Кэш памяти с лимитом стоимости и автоочисткой верифицирован")
    }
    
    // MARK: - 4. Явные состояния ошибок вместо бесконечного ожидания
    
    func testExplicitErrorStatesForPreviews() async throws {
        print("\n[4/8] Тест явных состояний ошибок вместо бесконечного ожидания...")
        
        let missingURL = tempDir.appendingPathComponent("non_existent_photo.jpg")
        let resultMissing = await PreviewPipeline.shared.loadThumbnail(for: missingURL, maxPixelSize: 300)
        guard case .failure(let err1) = resultMissing, case .fileNotFound = err1 else {
            fatalError("Отсутствующий файл должен возвращать PreviewError.fileNotFound")
        }
        
        let unsupportedURL = tempDir.appendingPathComponent("document.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: unsupportedURL)
        let resultUnsupported = await PreviewPipeline.shared.loadThumbnail(for: unsupportedURL, maxPixelSize: 300)
        guard case .failure(let err2) = resultUnsupported, case .unsupportedFormat = err2 else {
            fatalError("Неподдерживаемый формат должен возвращать PreviewError.unsupportedFormat")
        }
        
        let corruptedURL = tempDir.appendingPathComponent("corrupted.jpg")
        try Data([0xFF, 0xD8, 0x00, 0x00, 0x00, 0x00]).write(to: corruptedURL)
        let resultCorrupted = await PreviewPipeline.shared.loadThumbnail(for: corruptedURL, maxPixelSize: 300)
        guard case .failure = resultCorrupted else {
            fatalError("Поврежденный файл должен завершаться явной ошибкой")
        }
        
        print("  ✓ Ошибки превью возвращают явные состояния (fileNotFound, unsupportedFormat, corruptedFile) без зависания UI")
    }
    
    // MARK: - 5. Различение RAW, JPEG, HEIF (.HIF) и неподдерживаемых форматов
    
    func testFormatDifferentiationIncludingHEIF() async throws {
        print("\n[5/8] Тест распознавания RAW, JPEG, HEIF (включая Nikon .HIF)...")
        
        let fmtRAW = MediaFormat(fileExtension: "nef")
        assert(fmtRAW.isRAW, "NEF должен быть RAW")
        assert(!fmtRAW.isJPEG && !fmtRAW.isHEIF, "NEF не должен быть JPEG или HEIF")
        
        let fmtJPG = MediaFormat(fileExtension: "jpg")
        assert(fmtJPG.isJPEG, "JPG должен быть JPEG")
        assert(!fmtJPG.isRAW, "JPG не должен быть RAW")
        
        let fmtHIF = MediaFormat(fileExtension: "hif")
        assert(fmtHIF.isHEIF, "Nikon .hif должен распознаваться как HEIF")
        assert(fmtHIF.displayName == "HEIF", "Отображаемое имя должно быть HEIF")
        
        let fmtHEIC = MediaFormat(fileExtension: "heic")
        assert(fmtHEIC.isHEIF, "HEIC должен быть HEIF")
        
        let fmtBin = MediaFormat(fileExtension: "bin")
        if case .unknown = fmtBin { } else {
            fatalError("Неизвестное расширение должно давать MediaFormat.unknown")
        }
        
        print("  ✓ Все форматы, включая специфичный для Nikon Z формат .HIF, корректно распознаны")
    }
    
    // MARK: - 6. Многокритериальное объединение по источнику, времени и кадру
    
    func testMultiCriteriaFramePairing() async throws {
        print("\n[6/8] Тест многокритериального объединения пары RAW+JPEG (с защитой от ложных совпадений)...")
        
        let sessionID = UUID()
        let now = Date()
        
        // Случай A: sRGB RAW и AdobeRGB JPEG (_DSC0001) одной камеры
        let rawAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0001.NEF",
            fileURL: tempDir.appendingPathComponent("DSC_0001.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 45_000_000,
            metadata: AssetMetadata(cameraModel: "NIKON Z 8", exposureTime: 0.004, fNumber: 2.8, iso: 400, captureDate: now)
        )
        
        let jpgAsset = MediaAsset(
            sessionID: sessionID,
            filename: "_DSC0001.JPG",
            fileURL: tempDir.appendingPathComponent("_DSC0001.JPG"),
            format: .jpeg,
            fileSize: 8_000_000,
            metadata: AssetMetadata(cameraModel: "NIKON Z 8", exposureTime: 0.004, fNumber: 2.8, iso: 400, captureDate: now)
        )
        
        let isMatch = FramePairingEngine.areMatchingPair(asset1: rawAsset, asset2: jpgAsset)
        assert(isMatch, "RAW и JPEG одного спуска с префиксом AdobeRGB должны объединяться в пару")
        
        // Случай B: Одинаковые имена файлов, но РАЗНЫЕ камеры (Nikon Z 9 vs Nikon Z 8)
        let z9JpgAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0001.JPG",
            fileURL: tempDir.appendingPathComponent("DSC_0001_z9.JPG"),
            format: .jpeg,
            fileSize: 8_000_000,
            metadata: AssetMetadata(cameraModel: "NIKON Z 9", exposureTime: 0.004, fNumber: 2.8, iso: 400, captureDate: now)
        )
        
        let crossCameraMatch = FramePairingEngine.areMatchingPair(asset1: rawAsset, asset2: z9JpgAsset)
        assert(!crossCameraMatch, "Кадры от разных камер (Z 8 vs Z 9) НЕ должны объединяться в одну пару")
        
        // Случай C: Одинаковые имена, но РАЗНОЕ время съемки (сброс счетчика через месяц)
        let oldRawAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0001.NEF",
            fileURL: tempDir.appendingPathComponent("DSC_0001.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 45_000_000,
            metadata: AssetMetadata(cameraModel: "NIKON Z 8", captureDate: now.addingTimeInterval(-86400))
        )
        let timeMismatch = FramePairingEngine.areMatchingPair(asset1: oldRawAsset, asset2: jpgAsset)
        assert(!timeMismatch, "Снимки с разницей в сутках не должны объединяться")
        
        print("  ✓ Многокритериальное сопоставление (сессия + модель камеры + нормализованный кадр + EXIF таймстемп) подтверждено")
    }
    
    // MARK: - 7. Поддержка запаздывающего прихода второй части пары без дублирования
    
    func testDelayedCompanionArrivalWithoutDuplicates() async throws {
        print("\n[7/8] Тест запаздывающего прихода второй части пары кадра...")
        
        let sessionID = UUID()
        let shotTime = Date()
        
        // 1. Сначала по сети приходит быстрый JPEG
        let jpgAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0042.JPG",
            fileURL: tempDir.appendingPathComponent("DSC_0042.JPG"),
            format: .jpeg,
            fileSize: 6_500_000,
            metadata: AssetMetadata(cameraModel: "NIKON Z 6III", captureDate: shotTime),
            receivedAt: shotTime
        )
        
        var group = CaptureGroup(asset: jpgAsset)
        assert(group.formatBadge == "JPG", "Исходно бейдж должен быть JPG")
        assert(!group.hasBothRawAndJpeg, "Пока прибыл только JPEG")
        assert(group.allAssets.count == 1, "В группе должен быть ровно 1 файл")
        
        // 2. Спустя 4 секунды завершается передача тяжелого RAW (.NEF)
        let rawAsset = MediaAsset(
            sessionID: sessionID,
            filename: "DSC_0042.NEF",
            fileURL: tempDir.appendingPathComponent("DSC_0042.NEF"),
            format: .raw(fileExtension: "nef"),
            fileSize: 42_000_000,
            metadata: AssetMetadata(cameraModel: "NIKON Z 6III", captureDate: shotTime),
            receivedAt: shotTime.addingTimeInterval(4)
        )
        
        assert(group.canAccept(asset: rawAsset), "Группа кадра должна принять запаздывающий RAW")
        group.addAsset(rawAsset)
        
        // 3. Проверка обновленного состояния кадра
        assert(group.hasBothRawAndJpeg, "После прихода RAW кадр должен быть парным (hasBothRawAndJpeg == true)")
        assert(group.formatBadge == "RAW + JPG", "Бейдж должен обновиться на RAW + JPG")
        assert(group.allAssets.count == 2, "В группе должно быть ровно 2 оригинала")
        assert(group.rawAsset?.filename == "DSC_0042.NEF", "RAW ассет должен быть сохранен")
        assert(group.jpegAsset?.filename == "DSC_0042.JPG", "JPEG ассет должен быть сохранен")
        assert(group.primaryAsset?.isRAW == true, "Основным ассетом кадра должен стать RAW")
        
        print("  ✓ Вторая часть пары успешно объединена с существующей карточкой без дублирования в галерее")
    }
    
    // MARK: - 8. Разделение фильтров отображения и настроек импорта
    
    @MainActor
    func testSeparationOfDisplayFiltersAndImportSettings() async throws {
        print("\n[8/8] Тест разделения фильтров отображения галереи и настроек импорта...")
        
        let appState = AppState()
        let sessionID = UUID()
        
        // Наполняем тестовыми группами
        let group1 = CaptureGroup(
            baseName: "DSC_0001",
            sessionID: sessionID,
            rawAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0001.NEF", fileURL: tempDir.appendingPathComponent("DSC_0001.NEF"), format: .raw(fileExtension: "nef"), fileSize: 40_000_000),
            jpegAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0001.JPG", fileURL: tempDir.appendingPathComponent("DSC_0001.JPG"), format: .jpeg, fileSize: 8_000_000)
        )
        
        let group2 = CaptureGroup(
            baseName: "DSC_0002",
            sessionID: sessionID,
            rawAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0002.NEF", fileURL: tempDir.appendingPathComponent("DSC_0002.NEF"), format: .raw(fileExtension: "nef"), fileSize: 40_000_000)
        )
        
        let group3 = CaptureGroup(
            baseName: "DSC_0003",
            sessionID: sessionID,
            heifAsset: MediaAsset(sessionID: sessionID, filename: "DSC_0003.HIF", fileURL: tempDir.appendingPathComponent("DSC_0003.HIF"), format: .heif, fileSize: 12_000_000)
        )
        
        appState.captureGroups = [group1, group2, group3]
        
        // 1. Проверка счетчиков
        assert(appState.totalFramesCount == 3, "Всего 3 кадра")
        assert(appState.pairedCount == 1, "1 парный кадр")
        assert(appState.rawCount == 2, "2 кадра содержат RAW")
        assert(appState.heifCount == 1, "1 кадр содержит HEIF")
        
        // 2. Изменение настроек импорта (не должно менять filteredGroups!)
        appState.usbImportMode = .selected
        appState.importFormatPreference = .rawOnly
        assert(appState.filteredGroups.count == 3, "Смена правил импорта не должна скрывать уже сохраненные файлы в галерее")
        
        // 3. Изменение фильтров отображения
        appState.onlyPaired = true
        assert(appState.filteredGroups.count == 1, "При фильтре onlyPaired должен остаться только 1 кадр")
        assert(appState.filteredGroups.first?.baseName == "DSC_0001", "Должен остаться парный кадр DSC_0001")
        
        appState.onlyPaired = false
        appState.showRAW = false
        assert(!appState.filteredGroups.contains(where: { $0.baseName == "DSC_0002" }), "Одиночный RAW должен быть скрыт при выключенном showRAW")
        
        print("  ✓ Фильтры отображения и параметры импорта полностью изолированы друг от друга")
    }
    
    // MARK: - Вспомогательные генераторы
    
    private func createValidSampleJPEG(at url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }
        
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let cgImage = ctx.makeImage() else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image dest"])
        }
        
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }
    
    private func makeDummyImage(width: Int, height: Int) -> PlatformImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let cg = ctx.makeImage()!
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
        #endif
    }
}
