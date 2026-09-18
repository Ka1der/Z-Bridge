import Foundation

/// Движок многокритериального сопоставления и объединения пар RAW+JPEG/HEIF одного кадра
public struct FramePairingEngine: Sendable {
    
    /// Проверка, принадлежат ли два ассета одному и тому же спуску затвора
    public static func areMatchingPair(
        asset1: MediaAsset,
        asset2: MediaAsset,
        toleranceSeconds: TimeInterval = 2.0
    ) -> Bool {
        // 1. Должны принадлежать одной рабочей сессии
        guard asset1.sessionID == asset2.sessionID else { return false }
        
        // 2. Форматы файлов должны различаться (не объединяем два разных RAW или два разных JPEG в один кадр)
        guard asset1.format != asset2.format else { return false }
        
        // 3. Проверка источника/камеры: исключаем склеивание кадров от разных камер в мультикамерной съемке
        if let cam1 = asset1.metadata.cameraModel, let cam2 = asset2.metadata.cameraModel {
            guard cam1.caseInsensitiveCompare(cam2) == .orderedSame else {
                return false
            }
        }
        
        // 4. Сопоставление нормализованных номеров кадров и базовых имён
        let key1 = normalizeFrameName(asset1.filename)
        let key2 = normalizeFrameName(asset2.filename)
        
        let namesMatch = (key1 == key2) || areEquivalentNikonNames(asset1.filename, asset2.filename)
        guard namesMatch else { return false }
        
        // 5. Проверка времени съемки EXIF (если доступно в обоих файлах)
        if let d1 = asset1.metadata.captureDate, let d2 = asset2.metadata.captureDate {
            guard abs(d1.timeIntervalSince(d2)) <= toleranceSeconds else {
                return false
            }
        }
        
        // 6. Проверка параметров экспозиции (если зафиксированы в EXIF)
        if let iso1 = asset1.metadata.iso, let iso2 = asset2.metadata.iso {
            guard iso1 == iso2 else { return false }
        }
        if let exp1 = asset1.metadata.exposureTime, let exp2 = asset2.metadata.exposureTime {
            guard abs(exp1 - exp2) < 0.0002 else { return false }
        }
        if let f1 = asset1.metadata.fNumber, let f2 = asset2.metadata.fNumber {
            guard abs(f1 - f2) < 0.05 else { return false }
        }
        
        return true
    }
    
    /// Нормализация имени файла кадра: удаление расширения, приведение к верхнему регистру,
    /// и удаление ведущего подчеркивания AdobeRGB (например, "_DSC0001" -> "DSC0001")
    public static func normalizeFrameName(_ filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension.uppercased()
        if base.hasPrefix("_") {
            base.removeFirst()
        }
        return base
    }
    
    /// Проверка эквивалентности имён Nikon с учётом цветовых пространств sRGB и AdobeRGB
    /// (например: "DSC_0001.NEF" и "_DSC0001.JPG" или "_DSC_0001.JPG")
    public static func areEquivalentNikonNames(_ name1: String, _ name2: String) -> Bool {
        let norm1 = normalizeFrameName(name1).replacingOccurrences(of: "_", with: "")
        let norm2 = normalizeFrameName(name2).replacingOccurrences(of: "_", with: "")
        guard !norm1.isEmpty && norm1 == norm2 else { return false }
        
        // Дополнительно проверяем числовую часть
        let digits1 = extractTrailingDigits(from: norm1)
        let digits2 = extractTrailingDigits(from: norm2)
        if !digits1.isEmpty && !digits2.isEmpty {
            return digits1 == digits2
        }
        return true
    }
    
    /// Извлечение последовательного номера кадра из конца имени (например, "DSC0042" -> "0042")
    public static func extractTrailingDigits(from string: String) -> String {
        let digits = string.reversed().prefix { $0.isNumber }
        return String(digits.reversed())
    }
}
