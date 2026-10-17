import Foundation
import ImageIO
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Высокоскоростное извлечение превью из Nikon .NEF и .JPG файлов
public struct RAWPreviewExtractor: Sendable {
    private static let cache = NSCache<NSString, PlatformImage>()
    
    /// Извлечение превью без полного декодирования сенсорного RAW (задержка < 30 мс)
    public static func extractThumbnail(
        from url: URL,
        maxPixelSize: Int = 1600
    ) -> PlatformImage? {
        let cacheKey = "\(url.path)_\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        
        #if canImport(UIKit)
        let img = UIImage(cgImage: cgImage)
        cache.setObject(img, forKey: cacheKey)
        return img
        #elseif canImport(AppKit)
        let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(img, forKey: cacheKey)
        return img
        #endif
    }
    
    /// Извлечение высококачественного CGImage (до 4096px) без полного декодирования сенсорного RAW
    public static func extractCGImage(
        from url: URL,
        maxPixelSize: Int = 3840
    ) -> CGImage? {
        if let platformImg = extractThumbnail(from: url, maxPixelSize: maxPixelSize) {
            #if canImport(UIKit)
            return platformImg.cgImage
            #elseif canImport(AppKit)
            return platformImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #endif
        }
        return nil
    }
    
    /// Извлечение метаданных EXIF (выдержка, диафрагма, ISO, фокусное расстояние)
    public static func extractEXIFMetadata(from url: URL) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        
        return properties
    }
}
