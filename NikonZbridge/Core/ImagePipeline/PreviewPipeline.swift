import Foundation
import ImageIO
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Состояние загрузки превью для UI
public enum PreviewState: Equatable, Sendable {
    case idle
    case loading
    case success(PlatformImage)
    case failure(PreviewError)
}

/// Ошибки декодирования и загрузки превью
public enum PreviewError: LocalizedError, Equatable, Sendable {
    case fileNotFound(path: String)
    case corruptedFile(reason: String)
    case unsupportedFormat(ext: String)
    case decodingFailed
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Файл не найден на диске"
        case .corruptedFile(let reason):
            return "Повреждённый файл (\(reason))"
        case .unsupportedFormat(let ext):
            return "Формат .\(ext.uppercased()) не поддерживается"
        case .decodingFailed:
            return "Не удалось декодировать изображение"
        case .cancelled:
            return "Загрузка отменена"
        }
    }
}

/// Потокобезопасный кэш изображений с контролем памяти и количества элементов
public final class PreviewMemoryCache: @unchecked Sendable {
    public static let shared = PreviewMemoryCache()
    
    private let cache = NSCache<NSString, PlatformImage>()
    private let lock = NSLock()
    
    public init(
        maxCostMB: Int = 128,
        countLimit: Int = 300
    ) {
        cache.totalCostLimit = maxCostMB * 1024 * 1024
        cache.countLimit = countLimit
        
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clear()
        }
        #endif
    }
    
    public func image(forKey key: String) -> PlatformImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSString)
    }
    
    public func setImage(_ image: PlatformImage, forKey key: String, cost: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        let calculatedCost: Int
        if let explicitCost = cost {
            calculatedCost = explicitCost
        } else {
            #if canImport(UIKit)
            if let cgImage = image.cgImage {
                calculatedCost = cgImage.bytesPerRow * cgImage.height
            } else {
                calculatedCost = Int(image.size.width * image.size.height * 4)
            }
            #elseif canImport(AppKit)
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                calculatedCost = cgImage.bytesPerRow * cgImage.height
            } else {
                calculatedCost = Int(image.size.width * image.size.height * 4)
            }
            #endif
        }
        
        cache.setObject(image, forKey: key as NSString, cost: max(1, calculatedCost))
    }
    
    public func removeImage(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeObject(forKey: key as NSString)
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }
}

/// Высокопроизводительный асинхронный актор для неблокирующего декодирования превью
public actor PreviewPipeline {
    public static let shared = PreviewPipeline()
    
    private let memoryCache: PreviewMemoryCache
    private let maxConcurrentDecodes: Int
    private var activeDecodesCount: Int = 0
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var activeTasks: [String: Task<Result<PlatformImage, PreviewError>, Never>] = [:]
    
    public init(
        memoryCache: PreviewMemoryCache = .shared,
        maxConcurrentDecodes: Int = 4
    ) {
        self.memoryCache = memoryCache
        self.maxConcurrentDecodes = maxConcurrentDecodes
    }
    
    /// Загрузка миниатюры заданного максимального размера (по умолчанию 300px для сетки)
    public func loadThumbnail(
        for url: URL,
        maxPixelSize: Int = 300
    ) async -> Result<PlatformImage, PreviewError> {
        let cacheKey = "\(url.path)_\(maxPixelSize)"
        
        // 1. Проверка оперативного кэша
        if let cached = memoryCache.image(forKey: cacheKey) {
            return .success(cached)
        }
        
        // 2. Дедупликация: если запрос уже выполняется, ждём его результат
        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }
        
        // 3. Создание новой задачи с управлением жизненным циклом
        let task = Task<Result<PlatformImage, PreviewError>, Never> {
            await self.acquireDecodeSlot()
            defer {
                self.releaseDecodeSlot()
                self.removeActiveTask(forKey: cacheKey)
            }
            
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            // Выполняем декодирование вне главного потока
            let decodeResult = await Self.decodeImageOffThread(from: url, maxPixelSize: maxPixelSize)
            
            if case .success(let image) = decodeResult {
                self.memoryCache.setImage(image, forKey: cacheKey)
            }
            
            return decodeResult
        }
        
        activeTasks[cacheKey] = task
        return await task.value
    }
    
    /// Отмена выполняющегося запроса (например, при скролле ячейки за пределы экрана)
    public func cancelLoading(for url: URL, maxPixelSize: Int = 300) {
        let cacheKey = "\(url.path)_\(maxPixelSize)"
        if let task = activeTasks.removeValue(forKey: cacheKey) {
            task.cancel()
        }
    }
    
    private func removeActiveTask(forKey key: String) {
        activeTasks.removeValue(forKey: key)
    }
    
    // MARK: - Ограничение параллелизма (Bounded Queue)
    
    private func acquireDecodeSlot() async {
        if activeDecodesCount < maxConcurrentDecodes {
            activeDecodesCount += 1
            return
        }
        
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
        activeDecodesCount += 1
    }
    
    private func releaseDecodeSlot() {
        activeDecodesCount = max(0, activeDecodesCount - 1)
        if !pendingContinuations.isEmpty {
            let next = pendingContinuations.removeFirst()
            next.resume()
        }
    }
    
    // MARK: - Фоновое декодирование вне MainActor
    
    private static func decodeImageOffThread(
        from url: URL,
        maxPixelSize: Int
    ) async -> Result<PlatformImage, PreviewError> {
        // Запуск в отдельном непривязанном потоке пула Swift Concurrency
        return await Task.detached(priority: .userInitiated) { () -> Result<PlatformImage, PreviewError> in
            // 1. Проверка существования файла
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(.fileNotFound(path: url.path))
            }
            
            let ext = url.pathExtension.lowercased()
            let isRaw = (ext == "nef" || ext == "nrw")
            let isJpeg = (ext == "jpg" || ext == "jpeg")
            let isHeif = (ext == "hif" || ext == "heic" || ext == "heif")
            
            guard isRaw || isJpeg || isHeif else {
                return .failure(.unsupportedFormat(ext: ext))
            }
            
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            // 2. Чтение источника ImageIO
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldAllowFloat: false
            ]
            
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
                return .failure(.corruptedFile(reason: "Не удалось открыть дескриптор файла"))
            }
            
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return .failure(.decodingFailed)
            }
            
            #if canImport(UIKit)
            let platformImage = UIImage(cgImage: cgImage)
            #elseif canImport(AppKit)
            let platformImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            #endif
            
            return .success(platformImage)
        }.value
    }
}
