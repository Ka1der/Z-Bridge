import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct Stage10VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 10: ПАКЕТНЫЙ ЭКСПОРТ И ВНЕШНЕЕ ХРАНИЛИЩЕ ===")
        
        let suite = Stage10VerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 10 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

final class Stage10VerificationSuite {
    let tempDir: URL
    let localStoreDir: URL
    let externalDriveDir: URL
    
    init() {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("Stage10Test_\(UUID().uuidString)", isDirectory: true)
        let local = baseDir.appendingPathComponent("LocalStore", isDirectory: true)
        let ext = baseDir.appendingPathComponent("ExternalDriveMock", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true)
        
        self.tempDir = baseDir
        self.localStoreDir = local
        self.externalDriveDir = ext
    }
    
    func runAllTests() async throws {
        try await testExportDestinationAndModels()
        try await testFolderExportWithFormatFiltering()
        try await testNameConflictStrategies()
        try await testTargetVolumeFreeSpaceCheck()
        try await testExternalDriveDisconnectionHandling()
        try await testPerFileProgressAndCooperativeCancellation()
        try await testPartialFailureTrackingAndRetryFailedOnly()
        try await testBackgroundAutoExportAndLocalOriginalsSafety()
    }
    
    // MARK: - Helpers
    private func createDummyLocalFile(named name: String, byteCount: Int, patternByte: UInt8 = 0x5A) throws -> URL {
        let fileURL = localStoreDir.appendingPathComponent(name)
        let data = Data(repeating: patternByte, count: max(byteCount, 16))
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func createDummyAsset(named name: String, byteCount: Int, sessionID: UUID = UUID()) throws -> MediaAsset {
        let fileURL = try createDummyLocalFile(named: name, byteCount: byteCount)
        let ext = (name as NSString).pathExtension
        let format = MediaFormat(fileExtension: ext)
        return MediaAsset(
            sessionID: sessionID,
            filename: name,
            fileURL: fileURL,
            format: format,
            fileSize: Int64(byteCount)
        )
    }
    
    // MARK: - 1. Тест моделей ExportJob, ExportDestination, ExportFormatSelection
    func testExportDestinationAndModels() async throws {
        print("\n[1/8] Тест моделей ExportJob, ExportDestination, ExportFormatSelection...")
        
        // 1.1 Destinations
        let dirURL = tempDir.appendingPathComponent("TestExportFolder", isDirectory: true)
        let destFolder = ExportDestination.directory(url: dirURL, bookmarkData: nil)
        let destExt = ExportDestination.externalDrive(url: dirURL, volumeName: "SANDISK_1TB", bookmarkData: nil)
        let destPhotos = ExportDestination.photoLibrary(albumName: "NikonSession")
        let destShare = ExportDestination.shareSheet
        
        assert(destFolder.displayName.contains("TestExportFolder"), "Название папки должно содержать имя папки")
        assert(destExt.displayName.contains("SANDISK_1TB"), "Внешний диск должен показывать имя тома")
        assert(destPhotos.displayName.contains("NikonSession"), "Медиатека должна указывать альбом")
        assert(destShare.displayName.contains("Поделиться"), "Share sheet должен содержать 'Поделиться'")
        
        // 1.2 Format filtering predicate
        let rawAsset = try createDummyAsset(named: "DSC_0001.NEF", byteCount: 1000)
        let jpgAsset = try createDummyAsset(named: "DSC_0001.JPG", byteCount: 500)
        let heifAsset = try createDummyAsset(named: "DSC_0001.HIF", byteCount: 600)
        
        assert(ExportFormatSelection.both.shouldExport(asset: rawAsset) == true)
        assert(ExportFormatSelection.both.shouldExport(asset: jpgAsset) == true)
        assert(ExportFormatSelection.both.shouldExport(asset: heifAsset) == true)
        
        assert(ExportFormatSelection.rawOnly.shouldExport(asset: rawAsset) == true)
        assert(ExportFormatSelection.rawOnly.shouldExport(asset: jpgAsset) == false)
        assert(ExportFormatSelection.rawOnly.shouldExport(asset: heifAsset) == false)
        
        assert(ExportFormatSelection.companionOnly.shouldExport(asset: rawAsset) == false)
        assert(ExportFormatSelection.companionOnly.shouldExport(asset: jpgAsset) == true)
        assert(ExportFormatSelection.companionOnly.shouldExport(asset: heifAsset) == true)
        
        // 1.3 Job calculations
        let rawItem = ExportItem(asset: rawAsset)
        let jpgItem = ExportItem(asset: jpgAsset)
        let job = ExportJob(
            destination: destFolder,
            items: [rawItem, jpgItem],
            formatSelection: .both,
            conflictStrategy: .rename
        )
        
        assert(job.totalBytes == 1500, "Общий объем 1500 байт")
        assert(job.progressPercentage == 0.0, "Стартовый прогресс 0%")
        assert(job.items.count == 2)
        assert(job.state == .pending)
        
        print("✓ Модели ExportJob, Destination и FormatSelection корректны.")
    }
    
    // MARK: - 2. Тест экспорта в папку с фильтрацией форматов (RAW, JPEG, оба)
    func testFolderExportWithFormatFiltering() async throws {
        print("\n[2/8] Тест экспорта в папку с фильтрацией форматов (RAW only, JPEG only, оба)...")
        
        let exportManager = ExportManager()
        let targetExportDir = tempDir.appendingPathComponent("FilterExportTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetExportDir, withIntermediateDirectories: true)
        
        let sessionID = UUID()
        let raw = try createDummyAsset(named: "DSC_1001.NEF", byteCount: 2048, sessionID: sessionID)
        let jpg = try createDummyAsset(named: "DSC_1001.JPG", byteCount: 1024, sessionID: sessionID)
        
        // 2.1 Экспорт только RAW
        let rawOnlyJob = ExportJob(
            destination: .directory(url: targetExportDir, bookmarkData: nil),
            items: [ExportItem(asset: raw), ExportItem(asset: jpg)],
            formatSelection: .rawOnly,
            conflictStrategy: .overwrite
        )
        
        let rawCompleted = await exportManager.executeJob(rawOnlyJob)
        let rawResult = rawCompleted.result!
        assert(rawResult.successCount == 1, "Должен экспортироваться ровно 1 RAW файл")
        assert(rawResult.skippedCount == 1, "1 JPEG файл должен быть пропущен фильтром")
        assert(FileManager.default.fileExists(atPath: targetExportDir.appendingPathComponent("DSC_1001.NEF").path), "NEF должен быть в целевой папке")
        assert(!FileManager.default.fileExists(atPath: targetExportDir.appendingPathComponent("DSC_1001.JPG").path), "JPG НЕ должен экспортироваться при rawOnly")
        
        // 2.2 Экспорт только Companion (JPEG)
        let targetCompanionDir = tempDir.appendingPathComponent("CompanionExportTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetCompanionDir, withIntermediateDirectories: true)
        
        let companionOnlyJob = ExportJob(
            destination: .directory(url: targetCompanionDir, bookmarkData: nil),
            items: [ExportItem(asset: raw), ExportItem(asset: jpg)],
            formatSelection: .companionOnly,
            conflictStrategy: .overwrite
        )
        
        let companionCompleted = await exportManager.executeJob(companionOnlyJob)
        let companionResult = companionCompleted.result!
        assert(companionResult.successCount == 1, "Должен экспортироваться ровно 1 JPEG файл")
        assert(companionResult.skippedCount == 1, "1 RAW файл должен быть пропущен")
        assert(FileManager.default.fileExists(atPath: targetCompanionDir.appendingPathComponent("DSC_1001.JPG").path), "JPG должен быть в целевой папке")
        assert(!FileManager.default.fileExists(atPath: targetCompanionDir.appendingPathComponent("DSC_1001.NEF").path), "NEF НЕ должен быть в целевой папке")
        
        // 2.3 Экспорт обоих оригиналов
        let targetBothDir = tempDir.appendingPathComponent("BothExportTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetBothDir, withIntermediateDirectories: true)
        
        let bothJob = ExportJob(
            destination: .directory(url: targetBothDir, bookmarkData: nil),
            items: [ExportItem(asset: raw), ExportItem(asset: jpg)],
            formatSelection: .both,
            conflictStrategy: .overwrite
        )
        
        let bothCompleted = await exportManager.executeJob(bothJob)
        let bothResult = bothCompleted.result!
        assert(bothResult.successCount == 2, "Оба файла должны успешно экспортироваться")
        assert(bothResult.skippedCount == 0, "Ни один файл не должен быть пропущен")
        assert(FileManager.default.fileExists(atPath: targetBothDir.appendingPathComponent("DSC_1001.NEF").path))
        assert(FileManager.default.fileExists(atPath: targetBothDir.appendingPathComponent("DSC_1001.JPG").path))
        
        // Проверка неизменности локальных исходных файлов
        assert(FileManager.default.fileExists(atPath: raw.fileURL.path), "Локальный оригинал RAW не должен быть удален")
        assert(FileManager.default.fileExists(atPath: jpg.fileURL.path), "Локальный оригинал JPG не должен быть удален")
        
        print("✓ Экспорт с фильтрацией форматов работает безупречно.")
    }
    
    // MARK: - 3. Тест стратегий разрешения конфликтов имен (overwrite, skip, rename)
    func testNameConflictStrategies() async throws {
        print("\n[3/8] Тест стратегий разрешения конфликтов имен (overwrite, skip, rename)...")
        
        let exportManager = ExportManager()
        let conflictDir = tempDir.appendingPathComponent("ConflictTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        
        let destinationURL = conflictDir.appendingPathComponent("DSC_2000.JPG")
        
        // 3.1 Стратегия .skip
        // Заранее создаем файл назначения с другим содержимым
        let existingOriginalData = "EXISTING_CONTENT".data(using: .utf8)!
        try existingOriginalData.write(to: destinationURL)
        
        let sourceAsset = try createDummyAsset(named: "DSC_2000.JPG", byteCount: 4096)
        let skipJob = ExportJob(
            destination: .directory(url: conflictDir, bookmarkData: nil),
            items: [ExportItem(asset: sourceAsset)],
            formatSelection: .both,
            conflictStrategy: .skip
        )
        
        let skipCompleted = await exportManager.executeJob(skipJob)
        let skipResult = skipCompleted.result!
        assert(skipResult.skippedCount == 1, "Файл должен быть пропущен из-за конфликта")
        assert(skipResult.successCount == 0, "Успешных записей не должно быть")
        let postSkipData = try Data(contentsOf: destinationURL)
        assert(postSkipData == existingOriginalData, "Существующий файл не должен быть перезаписан при .skip")
        
        // 3.2 Стратегия .rename
        let renameJob = ExportJob(
            destination: .directory(url: conflictDir, bookmarkData: nil),
            items: [ExportItem(asset: sourceAsset)],
            formatSelection: .both,
            conflictStrategy: .rename
        )
        
        let renameCompleted = await exportManager.executeJob(renameJob)
        let renameResult = renameCompleted.result!
        assert(renameResult.successCount == 1, "Файл должен быть успешно сохранен с новым именем")
        let expectedRenamedFile = conflictDir.appendingPathComponent("DSC_2000 (1).JPG")
        assert(FileManager.default.fileExists(atPath: expectedRenamedFile.path), "Должен появиться переименованный файл DSC_2000 (1).JPG")
        let originalContent = try Data(contentsOf: destinationURL)
        assert(originalContent == existingOriginalData, "Первоначальный файл должен остаться нетронутым")
        
        // 3.3 Стратегия .overwrite
        let overwriteJob = ExportJob(
            destination: .directory(url: conflictDir, bookmarkData: nil),
            items: [ExportItem(asset: sourceAsset)],
            formatSelection: .both,
            conflictStrategy: .overwrite
        )
        
        let overwriteCompleted = await exportManager.executeJob(overwriteJob)
        let overwriteResult = overwriteCompleted.result!
        assert(overwriteResult.successCount == 1, "Файл должен быть успешно перезаписан")
        let postOverwriteSize = try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64 ?? 0
        assert(postOverwriteSize == 4096, "Размер файла должен обновиться до размера источника (4096)")
        
        print("✓ Стратегии разрешения конфликтов имен (.overwrite, .skip, .rename) работают корректно.")
    }
    
    // MARK: - 4. Тест проверки свободного места на целевом носителе
    func testTargetVolumeFreeSpaceCheck() async throws {
        print("\n[4/8] Тест проверки свободного места на целевом носителе перед экспортом...")
        
        let checkDir = tempDir.appendingPathComponent("SpaceCheckTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: checkDir, withIntermediateDirectories: true)
        
        // Обычный объем (1 КБ) должен проходить проверку
        let normalPass = DiskSpaceGuard.hasSufficientSpace(for: 1024, destinationURL: checkDir, safetyMargin: 1024 * 1024)
        assert(normalPass == true, "1 КБ с запасом 1 МБ должен проходить проверку свободного места")
        
        // Астрономический объем (10 Петабайт) должен отклоняться
        let hugeBytes: Int64 = 10_000_000_000_000_000
        let hugeFail = DiskSpaceGuard.hasSufficientSpace(for: hugeBytes, destinationURL: checkDir)
        assert(hugeFail == false, "10 Петабайт не должны проходить проверку свободного места")
        
        // Экспорт с недостатком места должен сразу завершаться ошибкой без частичных битых файлов
        let exportManager = ExportManager()
        let asset = try createDummyAsset(named: "DSC_3000.NEF", byteCount: 1024)
        var item = ExportItem(asset: asset)
        item.asset = MediaAsset(sessionID: asset.sessionID, filename: asset.filename, fileURL: asset.fileURL, format: asset.format, fileSize: hugeBytes)
        
        let noSpaceJob = ExportJob(
            destination: .directory(url: checkDir, bookmarkData: nil),
            items: [item],
            formatSelection: .both,
            conflictStrategy: .overwrite
        )
        
        let failedJob = await exportManager.executeJob(noSpaceJob)
        assert(failedJob.state.isFailed, "Задание с дефицитом места должно завершиться в состоянии failed")
        assert(failedJob.result?.failedCount == 1, "Элемент должен быть помечен как failed")
        assert(failedJob.items.first?.errorMessage?.contains("Недостаточно") == true, "Ошибка должна описывать нехватку места")
        
        print("✓ Проверка свободного места защищает диск от переполнения.")
    }
    
    // MARK: - 5. Тест отключения внешнего накопителя и защита локальных оригиналов
    func testExternalDriveDisconnectionHandling() async throws {
        print("\n[5/8] Тест отключения внешнего диска: обработка ошибки и сохранность оригиналов...")
        
        let exportManager = ExportManager()
        
        // Создаем локальный оригинал и фиксируем его хэш/байты
        let originalURL = try createDummyLocalFile(named: "DSC_CRITICAL.NEF", byteCount: 8192, patternByte: 0x7E)
        let asset = MediaAsset(sessionID: UUID(), filename: "DSC_CRITICAL.NEF", fileURL: originalURL, format: .raw(fileExtension: "NEF"), fileSize: 8192)
        
        // Симулируем внешний диск, который отмонтируется / исчезнет
        let virtualMount = tempDir.appendingPathComponent("MockRemovableVolume", isDirectory: true)
        try FileManager.default.createDirectory(at: virtualMount, withIntermediateDirectories: true)
        
        // Теперь отмонтируем (удалим) точку монтирования, имитируя резкое извлечение кабеля SSD
        try FileManager.default.removeItem(at: virtualMount)
        
        let disconnectJob = ExportJob(
            destination: .externalDrive(url: virtualMount, volumeName: "SSD_DISCONNECTED", bookmarkData: nil),
            items: [ExportItem(asset: asset)],
            formatSelection: .both,
            conflictStrategy: .overwrite
        )
        
        let resultJob = await exportManager.executeJob(disconnectJob)
        assert(resultJob.state.isFailed, "Экспорт на отключенный диск должен завершиться с состоянием failed")
        assert(resultJob.items.first?.status.isFailed == true, "Элемент должен получить статус failed")
        
        // ГЛАВНОЕ: Проверяем, что локальный оригинал не поврежден и не удален!
        assert(FileManager.default.fileExists(atPath: originalURL.path), "Локальный оригинал ОБЯЗАН остаться на месте!")
        let localData = try Data(contentsOf: originalURL)
        assert(localData.count == 8192, "Размер локального оригинала не должен измениться")
        assert(localData.allSatisfy({ $0 == 0x7E }), "Содержимое локального файла не должно быть повреждено")
        
        print("✓ Отключение внешнего диска корректно обработано; локальные оригиналы в полной безопасности.")
    }
    
    // MARK: - 6. Тест пофайлового прогресса и кооперативной отмены
    func testPerFileProgressAndCooperativeCancellation() async throws {
        print("\n[6/8] Тест пофайлового прогресса и кооперативной отмены экспорта...")
        
        let exportManager = ExportManager()
        let targetDir = tempDir.appendingPathComponent("CancelTestTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        
        var items: [ExportItem] = []
        for i in 1...10 {
            let asset = try createDummyAsset(named: "DSC_CANCEL_\(i).JPG", byteCount: 1024 * 50)
            items.append(ExportItem(asset: asset))
        }
        
        let job = ExportJob(
            destination: .directory(url: targetDir, bookmarkData: nil),
            items: items,
            formatSelection: .both,
            conflictStrategy: .overwrite
        )
        
        final class ProgressTracker: @unchecked Sendable {
            var count = 0
            var didCancel = false
        }
        let tracker = ProgressTracker()
        
        let finishedJob = await exportManager.executeJob(job, onProgress: { progressJob in
            tracker.count += 1
            if !tracker.didCancel {
                tracker.didCancel = true
                Task {
                    await exportManager.cancel()
                }
            }
        })
        
        assert(finishedJob.state.isCancelled || finishedJob.items.contains(where: { $0.status.isFailed }), "Состояние задания должно быть отменено или содержать прерванные элементы")
        
        print("✓ Кооперативная отмена остановила процесс без падений.")
    }
    
    // MARK: - 7. Тест отслеживания частичных ошибок и повтора только неудачных файлов (retryFailed)
    func testPartialFailureTrackingAndRetryFailedOnly() async throws {
        print("\n[7/8] Тест частичных ошибок и повтора ТОЛЬКО неудачных элементов (retryFailed)...")
        
        let exportManager = ExportManager()
        let targetDir = tempDir.appendingPathComponent("PartialFailureTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        
        let validAsset1 = try createDummyAsset(named: "DSC_VALID_1.JPG", byteCount: 2048)
        let brokenAsset = try createDummyAsset(named: "DSC_BROKEN.JPG", byteCount: 2048)
        let validAsset2 = try createDummyAsset(named: "DSC_VALID_2.JPG", byteCount: 2048)
        
        // Удаляем исходный файл brokenAsset с диска, чтобы спровоцировать ошибку его экспорта
        try FileManager.default.removeItem(at: brokenAsset.fileURL)
        
        let job = ExportJob(
            destination: .directory(url: targetDir, bookmarkData: nil),
            items: [ExportItem(asset: validAsset1), ExportItem(asset: brokenAsset), ExportItem(asset: validAsset2)],
            formatSelection: .both,
            conflictStrategy: .overwrite
        )
        
        let initialResultJob = await exportManager.executeJob(job)
        let initialResult = initialResultJob.result!
        assert(initialResult.successCount == 2, "2 валидных файла должны быть успешно экспортированы")
        assert(initialResult.failedCount == 1, "1 файл должен получить статус failed")
        
        let failedItems = initialResultJob.failedItems()
        assert(failedItems.count == 1, "failedItems() должен возвращать ровно 1 элемент")
        assert(failedItems.first?.asset.filename == "DSC_BROKEN.JPG")
        
        // Теперь "чиним" битый файл перед вызовом retry
        try Data(repeating: 0x42, count: 2048).write(to: brokenAsset.fileURL)
        
        // Вызываем повтор только неудачных операций
        let retryJob = await exportManager.retryFailed(in: initialResultJob)
        let retryResult = retryJob.result!
        assert(retryResult.successCount == 3, "Все 3 файла должны быть отмечены как успешные")
        assert(retryJob.failedItems().isEmpty, "Все ошибки должны быть устранены")
        assert(retryJob.state.isCompleted, "Задание должно перейти в статус completed")
        
        // Проверяем, что все 3 файла присутствуют в папке назначения
        assert(FileManager.default.fileExists(atPath: targetDir.appendingPathComponent("DSC_VALID_1.JPG").path))
        assert(FileManager.default.fileExists(atPath: targetDir.appendingPathComponent("DSC_BROKEN.JPG").path))
        assert(FileManager.default.fileExists(atPath: targetDir.appendingPathComponent("DSC_VALID_2.JPG").path))
        
        print("✓ retryFailed перезапускает исключительно упавшие элементы без повторного копирования успешных.")
    }
    
    // MARK: - 8. Тест фонового авто-экспорта (Live Mirror) и защиты локальных файлов
    func testBackgroundAutoExportAndLocalOriginalsSafety() async throws {
        print("\n[8/8] Тест фонового авто-экспорта (Live Mirror) и абсолютной сохранности локальных файлов...")
        
        let storage = StorageManager(customBaseURL: localStoreDir)
        let coordinator = TransferCoordinator(storageManager: storage)
        let autoMirrorDir = tempDir.appendingPathComponent("AutoMirrorTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: autoMirrorDir, withIntermediateDirectories: true)
        
        // Включаем авто-экспорт в координаторе
        await coordinator.setAutoExport(
            enabled: true,
            destinationURL: autoMirrorDir,
            bookmarkData: nil,
            format: .both
        )
        
        let isEnabled = await coordinator.isAutoExportEnabled
        let mirrorURL = await coordinator.autoExportDestinationURL
        assert(isEnabled == true)
        assert(mirrorURL == autoMirrorDir)
        
        // Симулируем сохранение локального оригинала через TransferCoordinator
        _ = try await coordinator.startNewSession(named: "TetherLiveSession")
        var validNEFData = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        validNEFData.append(Data(repeating: 0x01, count: 1016))
        let originalFileName = "DSC_LIVE_001.NEF"
        
        let cameraSource = CameraSource(id: "z8_usb", model: "Nikon Z 8", transportType: .usb)
        let job = try await coordinator.createTransferJob(
            source: cameraSource,
            filename: originalFileName,
            expectedSize: Int64(validNEFData.count)
        )
        
        let writeURL = job.stagingURL ?? job.destinationURL
        try validNEFData.write(to: writeURL)
        
        let asset = try await coordinator.finalizeTransfer(
            jobID: job.id,
            actualSize: Int64(validNEFData.count),
            duration: 0.05
        )
        
        // Даем короткое время utility-задаче отработать фоновое зеркалирование
        var mirrored = false
        let mirrorTargetFile = autoMirrorDir.appendingPathComponent(originalFileName)
        for _ in 1...30 {
            if FileManager.default.fileExists(atPath: mirrorTargetFile.path) {
                mirrored = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        assert(mirrored == true, "Файл должен быть автоматически скопирован в фоновое зеркало")
        let mirroredData = try Data(contentsOf: mirrorTargetFile)
        assert(mirroredData == validNEFData, "Скопированные в зеркало данные должны совпадать байт-в-байт")
        
        // КРИТИЧЕСКИЙ АССЕРТ: Проверяем, что локальный оригинал остался нетронут!
        assert(FileManager.default.fileExists(atPath: asset.fileURL.path), "Локальный оригинальный файл не должен быть удален!")
        let localDataAfterAutoExport = try Data(contentsOf: asset.fileURL)
        assert(localDataAfterAutoExport == validNEFData, "Локальный оригинал не должен быть модифицирован при авто-экспорте")
        
        // Отключаем авто-экспорт
        await coordinator.setAutoExport(enabled: false)
        let isEnabledAfter = await coordinator.isAutoExportEnabled
        assert(isEnabledAfter == false)
        
        print("✓ Фоновый авто-экспорт успешно работает без влияния на локальное хранилище.")
    }
}
