import Foundation

/// Структурированная модель метаданных EXIF для отображения в интерфейсе
public struct PhotoEXIFData: Sendable {
    public let filename: String
    public let fileSizeString: String
    public let fileFormatString: String
    public let isRAW: Bool
    
    // 1. Оборудование
    public var cameraModel: String?
    public var cameraMake: String?
    public var lensModel: String?
    public var softwareVersion: String?
    
    // 2. Ключевые параметры экспозиции
    public var shutterSpeed: String?
    public var aperture: String?
    public var iso: String?
    public var focalLength: String?
    public var focalLength35mm: String?
    
    // 3. Детали и режимы съёмки
    public var exposureProgram: String?
    public var exposureBias: String?
    public var meteringMode: String?
    public var whiteBalance: String?
    public var flash: String?
    public var colorSpace: String?
    
    // 4. Параметры изображения
    public var dimensions: String?
    public var dateTimeOriginal: String?
    
    public init(
        item: CameraFileItem,
        defaultCameraName: String? = nil,
        rawProperties: [String: Any]? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.filename = item.filename
        self.fileSizeString = item.formattedSize
        self.fileFormatString = item.isRAW ? "RAW (Nikon NEF)" : "JPEG / HEIF"
        self.isRAW = item.isRAW
        
        self.cameraModel = defaultCameraName ?? "Nikon Z"
        
        if let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 {
            self.dimensions = "\(w) × \(h) px"
        } else if let thumb = item.thumbnail {
            self.dimensions = "\(thumb.width) × \(thumb.height) px"
        }
        
        if let creation = item.creationDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .medium
            self.dateTimeOriginal = df.string(from: creation)
        }
        
        if let props = rawProperties {
            parseProperties(props)
        }
    }
    
    private mutating func parseProperties(_ props: [String: Any]) {
        let exif = (props["{Exif}"] as? [String: Any]) ?? [:]
        let tiff = (props["{TIFF}"] as? [String: Any]) ?? [:]
        
        // Оборудование
        if let model = (tiff["Model"] as? String) ?? (props["Model"] as? String), !model.isEmpty {
            self.cameraModel = model
        }
        if let make = (tiff["Make"] as? String) ?? (props["Make"] as? String), !make.isEmpty {
            self.cameraMake = make
        }
        if let soft = (tiff["Software"] as? String) ?? (props["Software"] as? String), !soft.isEmpty {
            self.softwareVersion = soft
        }
        if let lens = (exif["LensModel"] as? String) ?? (props["LensModel"] as? String), !lens.isEmpty {
            self.lensModel = lens
        }
        
        // Выдержка (Shutter Speed)
        if let expTime = (exif["ExposureTime"] as? Double) ?? (props["ExposureTime"] as? Double) {
            if expTime < 1.0 && expTime > 0.0 {
                let denom = Int(round(1.0 / expTime))
                self.shutterSpeed = "1/\(denom)s"
            } else {
                self.shutterSpeed = String(format: "%.1fs", expTime)
            }
        }
        
        // Диафрагма (Aperture)
        if let fNum = (exif["FNumber"] as? Double) ?? (props["FNumber"] as? Double) {
            self.aperture = String(format: "f/%.1f", fNum)
        }
        
        // ISO
        if let isos = (exif["ISOSpeedRatings"] as? [Int]) ?? (props["ISOSpeedRatings"] as? [Int]), let first = isos.first {
            self.iso = "\(first)"
        } else if let isoVal = (exif["ISOSpeedRatings"] as? Int) ?? (props["ISOSpeedRatings"] as? Int) {
            self.iso = "\(isoVal)"
        } else if let sens = (exif["PhotographicSensitivity"] as? Int) ?? (props["PhotographicSensitivity"] as? Int) {
            self.iso = "\(sens)"
        } else if let sensArr = (exif["PhotographicSensitivity"] as? [Int]) ?? (props["PhotographicSensitivity"] as? [Int]), let first = sensArr.first {
            self.iso = "\(first)"
        }
        
        // Фокусное расстояние
        if let fl = (exif["FocalLength"] as? Double) ?? (props["FocalLength"] as? Double) {
            self.focalLength = String(format: "%.1f мм", fl)
        }
        if let fl35 = (exif["FocalLenIn35mmFilm"] as? Double) ?? (props["FocalLenIn35mmFilm"] as? Double) {
            self.focalLength35mm = "\(Int(round(fl35))) мм"
        } else if let fl35Int = (exif["FocalLenIn35mmFilm"] as? Int) ?? (props["FocalLenIn35mmFilm"] as? Int) {
            self.focalLength35mm = "\(fl35Int) мм"
        }
        
        // Экспокоррекция (Exposure Bias)
        if let bias = (exif["ExposureBiasValue"] as? Double) ?? (props["ExposureBiasValue"] as? Double) {
            self.exposureBias = String(format: "%+.1f EV", bias)
        }
        
        // Режим экспозиции (Exposure Program)
        if let prog = (exif["ExposureProgram"] as? Int) ?? (props["ExposureProgram"] as? Int) {
            switch prog {
            case 1: self.exposureProgram = tr("Ручной (M)", "Manual (M)")
            case 2: self.exposureProgram = tr("Программный (P)", "Program AE (P)")
            case 3: self.exposureProgram = tr("Приоритет диафрагмы (A)", "Aperture Priority (A)")
            case 4: self.exposureProgram = tr("Приоритет выдержки (S)", "Shutter Priority (S)")
            case 5: self.exposureProgram = tr("Творческий", "Creative")
            case 6: self.exposureProgram = tr("Спорт / Движение", "Action")
            case 7: self.exposureProgram = tr("Портрет", "Portrait")
            case 8: self.exposureProgram = tr("Пейзаж", "Landscape")
            default: self.exposureProgram = tr("Автоматический", "Auto")
            }
        }
        
        // Режим замера (Metering Mode)
        if let meter = (exif["MeteringMode"] as? Int) ?? (props["MeteringMode"] as? Int) {
            switch meter {
            case 1: self.meteringMode = tr("Усредненный", "Average")
            case 2: self.meteringMode = tr("Центровзвешенный", "Center-weighted")
            case 3: self.meteringMode = tr("Точечный", "Spot")
            case 4: self.meteringMode = tr("Многозонный", "Multi-spot")
            case 5: self.meteringMode = tr("Матричный", "Pattern / Matrix")
            case 6: self.meteringMode = tr("Частичный", "Partial")
            default: self.meteringMode = nil
            }
        }
        
        // Баланс белого (White Balance)
        if let wb = (exif["WhiteBalance"] as? Int) ?? (props["WhiteBalance"] as? Int) {
            self.whiteBalance = wb == 0 ? tr("Автоматический", "Auto") : tr("Ручной", "Manual")
        }
        
        // Вспышка (Flash)
        if let flashVal = (exif["Flash"] as? Int) ?? (props["Flash"] as? Int) {
            self.flash = (flashVal & 1) == 0 ? tr("Не сработала", "Did not fire") : tr("Сработала", "Fired")
        }
        
        // Цветовое пространство (ColorSpace)
        if let cs = (exif["ColorSpace"] as? Int) ?? (props["ColorSpace"] as? Int) {
            self.colorSpace = cs == 1 ? "sRGB" : (cs == 2 ? "Adobe RGB" : tr("Не калибровано", "Uncalibrated"))
        }
        
        // Разрешение (Pixel dimensions)
        let w = (props["PixelWidth"] as? Int) ?? (exif["PixelXDimension"] as? Int)
        let h = (props["PixelHeight"] as? Int) ?? (exif["PixelYDimension"] as? Int)
        if let width = w, let height = h, width > 0, height > 0 {
            self.dimensions = "\(width) × \(height) px"
        }
        
        // Дата съёмки (Date/Time Original)
        if let dateStr = (exif["DateTimeOriginal"] as? String) ?? (tiff["DateTime"] as? String) ?? (props["DateTimeOriginal"] as? String) {
            self.dateTimeOriginal = dateStr
        }
    }
}
