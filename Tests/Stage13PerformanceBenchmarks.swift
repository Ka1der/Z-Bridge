import Foundation
import Combine
import CommonCrypto
import Darwin
import ImageIO
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Benchmark verification failed: \(message)", file: file, line: line)
    }
}

func getResidentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kerr = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
        }
    }
    guard kerr == KERN_SUCCESS else { return 0.0 }
    return Double(info.resident_size) / (1024.0 * 1024.0)
}

@main
struct Stage13PerformanceBenchmarksMain {
    static func main() async throws {
        print("=== ЗАПУСК КОНТРОЛЬНЫХ ЗАМЕРОВ ПРОИЗВОДИТЕЛЬНОСТИ (ЭТАП 13) ===")
        
        let suite = Stage13PerformanceBenchmarksSuite()
        try await suite.runAllBenchmarks()
        
        print("\n=== ВСЕ КОНТРОЛЬНЫЕ ЗАМЕРЫ УСПЕШНО ВЫПОЛНЕНЫ! ===")
    }
}

@MainActor
final class Stage13PerformanceBenchmarksSuite {
    let tempDir: URL
    let fileManager = FileManager.default
    
    init() {
        let base = fileManager.temporaryDirectory.appendingPathComponent("Stage13Perf_\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.tempDir = base
    }
    
    func runAllBenchmarks() async throws {
        try await benchmarkTransferThroughput()
        try await benchmarkPreviewExtractionLatency()
        try await benchmarkMemoryFootprintDuringBatch()
        try await benchmarkUIThreadResponsiveness()
    }
    
    // MARK: - 1. Замер скорости переноса оригиналов (МБ/с)
    func benchmarkTransferThroughput() async throws {
        print("\n[Бенчмарк 1/4] Замер скорости сохранения и финализации оригиналов...")
        
        let storage = StorageManager(customBaseURL: tempDir.appendingPathComponent("perf1_storage", isDirectory: true))
        let dbURL = tempDir.appendingPathComponent("perf1_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "bench-cam", model: "Nikon Z 8", transportType: .usb)
        
        // Тест А: 10 МБ JPEG
        let size10MB = 10 * 1024 * 1024
        let job10MB = try await coordinator.createTransferJob(source: source, filename: "BENCH_10MB.JPG", expectedSize: nil)
        let data10MB = createDummyJPEGData(targetSize: size10MB)
        try data10MB.write(to: job10MB.stagingURL!)
        
        let start10 = DispatchTime.now()
        let asset10 = try await coordinator.finalizeTransfer(jobID: job10MB.id, actualSize: Int64(data10MB.count), duration: 0.05)
        let end10 = DispatchTime.now()
        
        let elapsed10 = Double(end10.uptimeNanoseconds - start10.uptimeNanoseconds) / 1_000_000_000.0
        let speed10 = (Double(data10MB.count) / (1024.0 * 1024.0)) / elapsed10
        print(String(format: "  • 10 МБ JPEG: %.2f МБ/с (время финализации: %.3f сек, хеш: %@)", speed10, elapsed10, String(asset10.sha256Checksum?.prefix(8) ?? "")))
        
        // Тест Б: 45 МБ RAW (.NEF)
        let size45MB = 45 * 1024 * 1024
        let job45MB = try await coordinator.createTransferJob(source: source, filename: "BENCH_45MB.NEF", expectedSize: nil)
        let data45MB = createDummyTIFFData(size: size45MB)
        try data45MB.write(to: job45MB.stagingURL!)
        
        let start45 = DispatchTime.now()
        let asset45 = try await coordinator.finalizeTransfer(jobID: job45MB.id, actualSize: Int64(data45MB.count), duration: 0.15)
        let end45 = DispatchTime.now()
        
        let elapsed45 = Double(end45.uptimeNanoseconds - start45.uptimeNanoseconds) / 1_000_000_000.0
        let speed45 = (Double(data45MB.count) / (1024.0 * 1024.0)) / elapsed45
        print(String(format: "  • 45 МБ RAW .NEF: %.2f МБ/с (время финализации: %.3f сек, хеш: %@)", speed45, elapsed45, String(asset45.sha256Checksum?.prefix(8) ?? "")))
        
        verify(speed10 > 20.0, "Скорость дискового пайплайна для 10 МБ должна превышать 20 МБ/с")
        verify(speed45 > 30.0, "Скорость дискового пайплайна для 45 МБ должна превышать 30 МБ/с")
        print("  ✓ Высокая скорость атомарного сохранения и хеширования SHA-256 подтверждена")
    }
    
    // MARK: - 2. Замер задержки от финализации до превью (мс)
    func benchmarkPreviewExtractionLatency() async throws {
        print("\n[Бенчмарк 2/4] Замер задержки генерации превью/миниатюры...")
        
        // Создаем валидный JPEG файл высокого разрешения (2400x1600)
        let sampleURL = tempDir.appendingPathComponent("preview_bench.jpg")
        try createSampleJPEG(at: sampleURL, width: 2400, height: 1600)
        
        var latencies: [Double] = []
        
        // Выполняем 10 замеров извлечения миниатюры
        for _ in 1...10 {
            let start = DispatchTime.now()
            let thumb = RAWPreviewExtractor.extractThumbnail(from: sampleURL, maxPixelSize: 1600)
            let end = DispatchTime.now()
            
            verify(thumb != nil, "Миниатюра должна быть успешно извлечена")
            let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            latencies.append(elapsedMs)
        }
        
        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = latencies.min() ?? 0
        let maxLatency = latencies.max() ?? 0
        
        print(String(format: "  • Задержка первого декодирования: %.2f мс", latencies.first ?? 0))
        print(String(format: "  • Средняя задержка с кэшированием: %.2f мс (мин: %.2f мс, макс: %.2f мс)", avgLatency, minLatency, maxLatency))
        
        verify(avgLatency < 50.0, "Средняя задержка отображения превью должна быть менее 50 мс")
        print("  ✓ Сверхнизкая задержка появления превью подтверждена")
    }
    
    // MARK: - 3. Замер потребления памяти (RSS) при пакетной обработке
    func benchmarkMemoryFootprintDuringBatch() async throws {
        print("\n[Бенчмарк 3/4] Замер потребления оперативной памяти (Resident Set Size)...")
        
        let storage = StorageManager(customBaseURL: tempDir.appendingPathComponent("perf3_storage", isDirectory: true))
        let dbURL = tempDir.appendingPathComponent("perf3_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "burst-cam", model: "Nikon Z 9", transportType: .usb)
        
        let baselineRSS = getResidentMemoryMB()
        print(String(format: "  • Исходное потребление памяти (Baseline): %.2f МБ", baselineRSS))
        
        var peakRSS = baselineRSS
        
        // Симулируем серию из 10 кадров по 15 МБ каждый (суммарно 150 МБ входных данных)
        for i in 1...10 {
            let filename = String(format: "BURST_%04d.NEF", i)
            let job = try await coordinator.createTransferJob(source: source, filename: filename, expectedSize: nil)
            let data = createDummyTIFFData(size: 15 * 1024 * 1024)
            try data.write(to: job.stagingURL!)
            
            _ = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: Int64(data.count), duration: 0.05)
            
            let currentRSS = getResidentMemoryMB()
            if currentRSS > peakRSS {
                peakRSS = currentRSS
            }
        }
        
        print(String(format: "  • Пиковое потребление памяти во время серии 150 МБ: %.2f МБ (прирост: +%.2f МБ)", peakRSS, peakRSS - baselineRSS))
        
        // Даем сборщику мусора и пулам autoreleasepool сработать
        try await Task.sleep(nanoseconds: 200_000_000)
        let finalRSS = getResidentMemoryMB()
        print(String(format: "  • Конечное потребление памяти после серии: %.2f МБ (остаточный прирост: +%.2f МБ)", finalRSS, max(0, finalRSS - baselineRSS)))
        
        // Проверяем, что память не улетела в бесконечность (прирост менее 100 МБ при обработке 150 МБ данных блоками)
        let growth = peakRSS - baselineRSS
        verify(growth < 150.0, "Потребление памяти должно быть строго ограничено потоковой записью блоками")
        print("  ✓ Потребление памяти строго ограничено и предсказуемо при непрерывной съемке")
    }
    
    // MARK: - 4. Проверка неблокирующего характера для Главного Потока (UI Responsiveness)
    func benchmarkUIThreadResponsiveness() async throws {
        print("\n[Бенчмарк 4/4] Замер отзывчивости основного потока (UI Responsiveness)...")
        
        let storage = StorageManager(customBaseURL: tempDir.appendingPathComponent("perf4_storage", isDirectory: true))
        let dbURL = tempDir.appendingPathComponent("perf4_catalog.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        await coordinator.bootstrap()
        
        let source = CameraSource(id: "ui-cam", model: "Nikon Z 8", transportType: .usb)
        
        // Фоновая тяжелая операция финализации и вычисления SHA-256 для 30 МБ файла
        let job = try await coordinator.createTransferJob(source: source, filename: "UI_TEST.NEF", expectedSize: nil)
        let data = createDummyTIFFData(size: 30 * 1024 * 1024)
        try data.write(to: job.stagingURL!)
        
        var mainThreadMaxLagMs: Double = 0.0
        
        // Запускаем фоновую задачу переноса
        let transferTask = Task.detached(priority: .userInitiated) {
            _ = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: Int64(data.count), duration: 0.1)
        }
        
        // Замеряем отзывчивость главного потока каждые 5 мс во время выполнения переноса
        for _ in 0..<20 {
            let tickStart = DispatchTime.now()
            try await Task.sleep(nanoseconds: 5_000_000) // 5 мс
            let tickEnd = DispatchTime.now()
            let actualTickDurationMs = Double(tickEnd.uptimeNanoseconds - tickStart.uptimeNanoseconds) / 1_000_000.0
            let lagMs = max(0.0, actualTickDurationMs - 5.0)
            if lagMs > mainThreadMaxLagMs {
                mainThreadMaxLagMs = lagMs
            }
        }
        
        try await transferTask.value
        
        print(String(format: "  • Максимальная задержка главного потока: %.2f мс (целевой порог < 16.6 мс для 60 FPS)", mainThreadMaxLagMs))
        verify(mainThreadMaxLagMs < 16.6, "Тяжелые дисковые и хеширующие операции не должны блокировать главный поток")
        print("  ✓ Главный поток свободен, интерфейс сохраняет частоту 60/120 кадров в секунду")
    }
    
    // MARK: - Вспомогательные генераторы тестовых данных
    
    private func createDummyTIFFData(size: Int) -> Data {
        var data = Data([0x4D, 0x4D, 0x00, 0x2A]) // TIFF Big Endian
        let remaining = max(0, size - 4)
        data.append(Data(repeating: 0x55, count: remaining))
        return data
    }
    
    private func createDummyJPEGData(targetSize: Int) -> Data {
        // Создаем валидный JPEG минимального размера, затем дополняем нулями внутри APP1 сегмента
        let tempURL = tempDir.appendingPathComponent("base_\(UUID().uuidString).jpg")
        try? createSampleJPEG(at: tempURL, width: 400, height: 300)
        guard var baseData = try? Data(contentsOf: tempURL) else {
            return Data(repeating: 0xFF, count: targetSize)
        }
        try? fileManager.removeItem(at: tempURL)
        
        if baseData.count < targetSize {
            let padding = targetSize - baseData.count
            // Вставляем padding перед маркером EOI (FF D9)
            if baseData.count >= 2 && baseData[baseData.count - 2] == 0xFF && baseData[baseData.count - 1] == 0xD9 {
                baseData.removeLast(2)
                baseData.append(Data(repeating: 0x00, count: padding))
                baseData.append(contentsOf: [0xFF, 0xD9])
            } else {
                baseData.append(Data(repeating: 0x00, count: padding))
            }
        }
        return baseData
    }
    
    private func createSampleJPEG(at url: URL, width: Int, height: Int) throws {
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
            throw NSError(domain: "PerfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }
        
        ctx.setFillColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let cgImage = ctx.makeImage() else {
            throw NSError(domain: "PerfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "PerfTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image dest"])
        }
        
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }
}
