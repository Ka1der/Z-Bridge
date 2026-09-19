import Foundation

/// Группа связанных файлов одного кадра (например, парные RAW .NEF и JPEG/HEIF)
public struct CaptureGroup: Identifiable, Sendable, Codable, Hashable {
    /// Уникальный идентификатор группы в рамках сессии и камеры
    public let id: String
    public let baseName: String
    public let sessionID: UUID
    public var sourceCamera: String?
    public var normalizedKey: String
    public var rawAsset: MediaAsset?
    public var jpegAsset: MediaAsset?
    public var heifAsset: MediaAsset?
    public var otherAssets: [MediaAsset]
    public var updatedAt: Date
    public var rating: Int
    public var pickStatus: PickStatus
    
    /// Основной ассет для отображения превью и инспекции (предпочтительно RAW, иначе JPEG, HEIF, либо первый доступный)
    public var primaryAsset: MediaAsset? {
        if let raw = rawAsset { return raw }
        if let jpeg = jpegAsset { return jpeg }
        if let heif = heifAsset { return heif }
        return otherAssets.first
    }
    
    public var captureDate: Date? {
        primaryAsset?.metadata.captureDate ?? primaryAsset?.receivedAt
    }
    
    /// Присутствуют ли одновременно RAW и companion-файл (JPEG или HEIF)
    public var hasBothRawAndJpeg: Bool {
        rawAsset != nil && (jpegAsset != nil || heifAsset != nil)
    }
    
    /// Присутствуют ли одновременно RAW и HEIF
    public var hasBothRawAndHeif: Bool {
        rawAsset != nil && heifAsset != nil
    }
    
    /// Текстовый бейдж для отображения на карточке галереи
    public var formatBadge: String {
        let hasRaw = rawAsset != nil
        let hasJpg = jpegAsset != nil && jpegAsset?.format.isJPEG == true
        let hasHeif = heifAsset != nil || (jpegAsset?.format.isHEIF == true)
        
        if hasRaw && hasHeif {
            return "RAW + HEIF"
        } else if hasRaw && hasJpg {
            return "RAW + JPG"
        } else if hasRaw {
            return "RAW"
        } else if hasHeif {
            return "HEIF"
        } else if hasJpg {
            return "JPG"
        } else if let first = otherAssets.first {
            return first.format.displayName
        } else {
            return "FILE"
        }
    }
    
    /// Все доступные оригиналы данного кадра
    public var allAssets: [MediaAsset] {
        var list: [MediaAsset] = []
        if let raw = rawAsset { list.append(raw) }
        if let jpeg = jpegAsset {
            if !list.contains(where: { $0.id == jpeg.id }) {
                list.append(jpeg)
            }
        }
        if let heif = heifAsset {
            if !list.contains(where: { $0.id == heif.id }) {
                list.append(heif)
            }
        }
        for other in otherAssets {
            if !list.contains(where: { $0.id == other.id }) {
                list.append(other)
            }
        }
        return list
    }
    
    /// Суммарный объём оригиналов кадра в байтах
    public var totalSize: Int64 {
        allAssets.reduce(0) { $0 + $1.fileSize }
    }
    
    /// Форматированный суммарный объём
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Краткая сводка доступных оригиналов (например: "RAW (.NEF, 48.2 МБ) • JPG (8.4 МБ)")
    public var availableOriginalsSummary: String {
        let parts = allAssets.map { "\($0.format.displayName) (\($0.formattedSize))" }
        return parts.joined(separator: " • ")
    }
    
    // MARK: - Инициализаторы
    
    public init(
        id: String? = nil,
        baseName: String,
        sessionID: UUID,
        sourceCamera: String? = nil,
        rawAsset: MediaAsset? = nil,
        jpegAsset: MediaAsset? = nil,
        heifAsset: MediaAsset? = nil,
        otherAssets: [MediaAsset] = [],
        updatedAt: Date = Date(),
        rating: Int? = nil,
        pickStatus: PickStatus? = nil
    ) {
        let normKey = FramePairingEngine.normalizeFrameName(baseName)
        let camPrefix = sourceCamera ?? "default"
        if let explicitID = id {
            self.id = explicitID
        } else if let date = rawAsset?.metadata.captureDate ?? jpegAsset?.metadata.captureDate ?? heifAsset?.metadata.captureDate ?? otherAssets.first?.metadata.captureDate {
            let timestamp = Int64(date.timeIntervalSince1970)
            self.id = "\(sessionID.uuidString)_\(camPrefix)_\(normKey)_\(timestamp)"
        } else {
            self.id = "\(sessionID.uuidString)_\(camPrefix)_\(normKey)"
        }
        self.baseName = baseName
        self.sessionID = sessionID
        self.sourceCamera = sourceCamera
        self.normalizedKey = normKey
        self.rawAsset = rawAsset
        self.jpegAsset = jpegAsset
        self.heifAsset = heifAsset
        self.otherAssets = otherAssets
        self.updatedAt = updatedAt
        let determinedRating = rating ?? (rawAsset?.rating ?? jpegAsset?.rating ?? heifAsset?.rating ?? otherAssets.first?.rating ?? 0)
        self.rating = max(0, min(5, determinedRating))
        self.pickStatus = pickStatus ?? (rawAsset?.pickStatus ?? jpegAsset?.pickStatus ?? heifAsset?.pickStatus ?? otherAssets.first?.pickStatus ?? .unflagged)
    }
    
    /// Конструктор обратной совместимости
    public init(
        baseName: String,
        sessionID: UUID,
        rawAsset: MediaAsset? = nil,
        jpegAsset: MediaAsset? = nil,
        otherAssets: [MediaAsset] = [],
        updatedAt: Date = Date()
    ) {
        self.init(
            baseName: baseName,
            sessionID: sessionID,
            sourceCamera: rawAsset?.metadata.cameraModel ?? jpegAsset?.metadata.cameraModel,
            rawAsset: rawAsset,
            jpegAsset: jpegAsset,
            heifAsset: nil,
            otherAssets: otherAssets,
            updatedAt: updatedAt,
            rating: rawAsset?.rating ?? jpegAsset?.rating,
            pickStatus: rawAsset?.pickStatus ?? jpegAsset?.pickStatus
        )
    }
    
    /// Создание новой группы из одного входящего ассета
    public init(asset: MediaAsset) {
        let base = Self.extractBaseName(from: asset.filename)
        self.init(
            baseName: base,
            sessionID: asset.sessionID,
            sourceCamera: asset.metadata.cameraModel,
            rawAsset: asset.isRAW ? asset : nil,
            jpegAsset: asset.isJPEG ? asset : nil,
            heifAsset: asset.isHEIF ? asset : nil,
            otherAssets: (!asset.isRAW && !asset.isJPEG && !asset.isHEIF) ? [asset] : [],
            updatedAt: asset.receivedAt,
            rating: asset.rating,
            pickStatus: asset.pickStatus
        )
    }
    
    /// Извлечение базового имени кадра из имени файла (например, "DSC_0001.NEF" -> "DSC_0001")
    public static func extractBaseName(from filename: String) -> String {
        let nsString = filename as NSString
        return nsString.deletingPathExtension
    }
    
    /// Проверка, может ли группа принять данный ассет как вторую часть пары
    public func canAccept(asset: MediaAsset) -> Bool {
        guard sessionID == asset.sessionID else { return false }
        
        // 1. Не принимаем дубликат формата, если такой формат в группе уже занят
        if asset.isRAW && rawAsset != nil { return false }
        if asset.isJPEG && jpegAsset != nil { return false }
        if asset.isHEIF && heifAsset != nil { return false }
        
        // 2. Если в группе уже есть ассеты, сопоставление строго делегируется FramePairingEngine
        if !allAssets.isEmpty {
            for existing in allAssets {
                if FramePairingEngine.areMatchingPair(asset1: existing, asset2: asset) {
                    return true
                }
            }
            return false
        }
        
        // 3. Запасной критерий только для пустой группы (без ассетов): эквивалентность базовых имён и совпадение камеры
        let norm = FramePairingEngine.normalizeFrameName(asset.filename)
        if norm == self.normalizedKey || FramePairingEngine.areEquivalentNikonNames(asset.filename, baseName) {
            if let cam1 = sourceCamera, let cam2 = asset.metadata.cameraModel {
                if cam1.caseInsensitiveCompare(cam2) != .orderedSame {
                    return false
                }
            }
            return true
        }
        
        return false
    }
    
    /// Установка рейтинга кадра с каскадным обновлением всех связанных оригиналов пары
    public mutating func setRating(_ newRating: Int) {
        let clamped = max(0, min(5, newRating))
        self.rating = clamped
        self.rawAsset?.rating = clamped
        self.jpegAsset?.rating = clamped
        self.heifAsset?.rating = clamped
        for i in 0..<otherAssets.count {
            self.otherAssets[i].rating = clamped
        }
        self.updatedAt = Date()
    }
    
    /// Установка статуса отбора кадра с каскадным обновлением всех связанных оригиналов пары
    public mutating func setPickStatus(_ newStatus: PickStatus) {
        self.pickStatus = newStatus
        self.rawAsset?.pickStatus = newStatus
        self.jpegAsset?.pickStatus = newStatus
        self.heifAsset?.pickStatus = newStatus
        for i in 0..<otherAssets.count {
            self.otherAssets[i].pickStatus = newStatus
        }
        self.updatedAt = Date()
    }
    
    /// Добавление ассета в группу (включая сценарий запаздывающего прихода второй части)
    public mutating func addAsset(_ asset: MediaAsset) {
        self.updatedAt = Date()
        if sourceCamera == nil {
            self.sourceCamera = asset.metadata.cameraModel
        }
        
        var assetToAdd = asset
        if self.rating > 0 && assetToAdd.rating == 0 {
            assetToAdd.rating = self.rating
        } else if assetToAdd.rating > 0 && self.rating == 0 {
            self.rating = assetToAdd.rating
        }
        
        if self.pickStatus != .unflagged && assetToAdd.pickStatus == .unflagged {
            assetToAdd.pickStatus = self.pickStatus
        } else if assetToAdd.pickStatus != .unflagged && self.pickStatus == .unflagged {
            self.pickStatus = assetToAdd.pickStatus
        }
        
        if assetToAdd.isRAW {
            self.rawAsset = assetToAdd
        } else if assetToAdd.isHEIF {
            self.heifAsset = assetToAdd
            if self.jpegAsset == nil {
                self.jpegAsset = assetToAdd
            }
        } else if assetToAdd.isJPEG {
            self.jpegAsset = assetToAdd
        } else {
            if !otherAssets.contains(where: { $0.id == assetToAdd.id }) {
                self.otherAssets.append(assetToAdd)
            }
        }
    }
}
