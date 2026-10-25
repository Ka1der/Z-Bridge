import Foundation

/// Целевые фоторедакторы для проверки совместимости метаданных
public enum TargetEditor: String, CaseIterable, Identifiable, Sendable, Codable {
    case lightroomClassic = "Adobe Lightroom Classic"
    case adobeCameraRaw = "Adobe Camera Raw (ACR)"
    case adobeBridge = "Adobe Bridge"
    case captureOne = "Capture One Pro"
    case photoMechanic = "Photo Mechanic"
    case darktable = "darktable"
    case rawTherapee = "RawTherapee"
    case applePhotos = "Apple Photos (Медиатека)"
    
    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

/// Информация о совместимости XMP метаданных с целевым RAW-редактором
public struct EditorCompatibilityInfo: Identifiable, Sendable, Hashable {
    public var id: String { target.rawValue }
    public let target: TargetEditor
    public var name: String { target.displayName }
    public let ratingSupported: Bool
    public let pickSupported: Bool
    public let rejectSupported: Bool
    public let metadataSupported: Bool
    public let recommendedNaming: XMPSidecarNamingConvention
    public let ratingNotes: String
    public let pickNotes: String
    public let rejectNotes: String
    public let workflowTip: String?
    public let nonPortableNotes: String?
    
    public init(
        target: TargetEditor,
        ratingSupported: Bool = true,
        pickSupported: Bool = true,
        rejectSupported: Bool = true,
        metadataSupported: Bool = true,
        recommendedNaming: XMPSidecarNamingConvention = .standardBasename,
        ratingNotes: String,
        pickNotes: String,
        rejectNotes: String,
        workflowTip: String? = nil,
        nonPortableNotes: String? = nil
    ) {
        self.target = target
        self.ratingSupported = ratingSupported
        self.pickSupported = pickSupported
        self.rejectSupported = rejectSupported
        self.metadataSupported = metadataSupported
        self.recommendedNaming = recommendedNaming
        self.ratingNotes = ratingNotes
        self.pickNotes = pickNotes
        self.rejectNotes = rejectNotes
        self.workflowTip = workflowTip
        self.nonPortableNotes = nonPortableNotes
    }
}

/// Справочник соглашений совместимости XMP метаданных с целевыми редакторами
public struct XMPCompatibilityGuide: Sendable {
    
    /// Словарь несовместимых и непереносимых отметок с пояснениями
    public static let nonPortableTags: [String: String] = [
        "Pick / Flag (Lightroom Classic)": "Флаг Pick в Adobe Lightroom Classic хранится исключительно внутри базы каталога (.lrcat) и не имеет официального тега в спецификации XMP Adobe. Z-Bridge транслирует Pick в xmp:Label='Pick' и photoshop:Urgency='1'.",
        "Reject (ACR / darktable)": "Отклонённые кадры помечаются тегом xmp:Rating='-1' и xmp:Label='Reject'. Нативно открываются в Adobe Camera Raw, Adobe Bridge и darktable.",
        "Capture One Color Tags": "Capture One транслирует xmp:Label='Pick' в цветовой тег Color Tag Green/Pick."
    ]
    
    /// Перечень проверенных целевых редакторов и статус их совместимости
    public static let allEditors: [EditorCompatibilityInfo] = [
        EditorCompatibilityInfo(
            target: .lightroomClassic,
            ratingSupported: true,
            pickSupported: true,
            rejectSupported: true,
            metadataSupported: true,
            recommendedNaming: .standardBasename,
            ratingNotes: "100% совместимость (1..5★ через xmp:Rating)",
            pickNotes: "Транслируется в xmp:Label='Pick' и Urgency=1 (флаг Pick в Lightroom хранится только в .lrcat каталоге)",
            rejectNotes: "xmp:Label='Reject' для фильтрации и смарт-коллекций",
            workflowTip: "Для чтения внешних XMP выберите файлы и нажмите «Metadata > Read Metadata from Files».",
            nonPortableNotes: "Белый флаг Pick в Adobe Lightroom хранится только в каталоге .lrcat. Используйте фильтр по метке Pick."
        ),
        EditorCompatibilityInfo(
            target: .adobeCameraRaw,
            ratingSupported: true,
            pickSupported: true,
            rejectSupported: true,
            metadataSupported: true,
            recommendedNaming: .standardBasename,
            ratingNotes: "Полная поддержка стандартов Adobe XMP (1..5★)",
            pickNotes: "Отображается через xmp:Label='Pick' и photoshop:Urgency=1",
            rejectNotes: "Нативная поддержка xmp:Rating='-1' (отображается как отклонённый снимок)",
            workflowTip: "Эталонная реализация Adobe XMP. Рейтинги и метки открываются автоматически.",
            nonPortableNotes: nil
        ),
        EditorCompatibilityInfo(
            target: .adobeBridge,
            ratingSupported: true,
            pickSupported: true,
            rejectSupported: true,
            metadataSupported: true,
            recommendedNaming: .standardBasename,
            ratingNotes: "Мгновенное отображение звёздного рейтинга (1..5★)",
            pickNotes: "Поддерживает текстовые и цветовые метки xmp:Label='Pick'",
            rejectNotes: "Рейтинг -1 обозначается значком Reject (Reject/Отклонено)",
            workflowTip: "При открытии папки Bridge мгновенно считывает sidecar файлы без предварительного импорта.",
            nonPortableNotes: nil
        ),
        EditorCompatibilityInfo(
            target: .captureOne,
            ratingSupported: true,
            pickSupported: true,
            rejectSupported: true,
            metadataSupported: true,
            recommendedNaming: .standardBasename,
            ratingNotes: "Полная поддержка (1..5★ через xmp:Rating)",
            pickNotes: "Транслируется в Color Tag (Green / Pick)",
            rejectNotes: "Отображается как 0★ с текстовой меткой Reject",
            workflowTip: "Включите «Параметры -> Изображение -> Автосинхронизация XMP» (Загрузка/Полная) или нажмите «Синхронизировать метаданные».",
            nonPortableNotes: "Capture One использует Color Tags вместо единичного флага Pick."
        ),
        EditorCompatibilityInfo(
            target: .photoMechanic,
            ratingSupported: true,
            pickSupported: true,
            rejectSupported: true,
            metadataSupported: true,
            recommendedNaming: .standardBasename,
            ratingNotes: "Мгновенное чтение 1..5★ при пролистывании",
            pickNotes: "Отображается через Color Class и xmp:Label='Pick'",
            rejectNotes: "xmp:Rating='-1' и xmp:Label='Reject'",
            workflowTip: "Идеально подходит для спортивного и репортажного отбора. Мгновенно подхватывает XMP файлы.",
            nonPortableNotes: nil
        ),
        EditorCompatibilityInfo(
            target: .darktable,
            ratingSupported: true,
            pickSupported: true,
            rejectSupported: true,
            metadataSupported: true,
            recommendedNaming: .fullFilename,
            ratingNotes: "Полная поддержка 0..5★ через xmp:Rating",
            pickNotes: "Через цветовую метку xmp:Label и darktable:colorlabels",
            rejectNotes: "Нативная поддержка xmp:Rating='-1' (помечается как отклонённый кадр)",
            workflowTip: "darktable предпочитает именование DSC_0001.NEF.xmp, но корректно читает и стандартное DSC_0001.xmp.",
            nonPortableNotes: nil
        ),
        EditorCompatibilityInfo(
            target: .rawTherapee,
            ratingSupported: true,
            pickSupported: false,
            rejectSupported: false,
            metadataSupported: true,
            recommendedNaming: .standardBasename,
            ratingNotes: "Звёздный рейтинг 1..5★ считывается из XMP",
            pickNotes: "Не поддерживается в интерфейсе программы",
            rejectNotes: "Не поддерживается в интерфейсе программы",
            workflowTip: "Использует собственные .pp3 профили обработки, но импортирует звёздные рейтинги из XMP.",
            nonPortableNotes: "Отметки Pick и Reject не отображаются в интерфейсе RawTherapee."
        ),
        EditorCompatibilityInfo(
            target: .applePhotos,
            ratingSupported: false,
            pickSupported: false,
            rejectSupported: false,
            metadataSupported: false,
            recommendedNaming: .standardBasename,
            ratingNotes: "Частичная (только при ручном пакетном импорте через системный диалог)",
            pickNotes: "Не поддерживается (своя система Favorites / Сердечко)",
            rejectNotes: "Не поддерживается",
            workflowTip: "Медиатека Apple Photos использует собственную закрытую БД SQLite и игнорирует внешние sidecar файлы.",
            nonPortableNotes: "Внешние файлы sidecar не импортируются в Apple Photos напрямую."
        )
    ]
    
    /// Документация несовместимых и непереносимых отметок (Требование 4)
    public static let nonPortableTagsDocumentation: String = """
    # Соглашения совместимости и непереносимые отметки (XMP Sidecar)
    
    ### 1. Звёздный рейтинг (xmp:Rating) — 100% совместимость
    - Стандартный тег `xmp:Rating` со значениями от 1 до 5 звёзд поддерживается всеми без исключения профессиональными редакторами (Adobe Lightroom Classic, Camera Raw, Bridge, Capture One Pro, Photo Mechanic, darktable, DxO PhotoLab).
    - Оценка, выставленная на iPad во время съёмки, гарантированно откроется в вашем целевом RAW-конвертере.
    
    ### 2. Отметка отбора (Pick / Белый флаг) — Ограничение Adobe Lightroom
    - В **Adobe Lightroom Classic** флаг отбора (Pick) является **внутренним свойством каталога (.lrcat)**. Компания Adobe никогда не включала белый флаг в спецификацию открытого стандарта XMP.
    - **Решение Z-Bridge**:
      - При установке отметки «Отобран» (Pick, клавиша P) в XMP записываются стандартные теги:
        `xmp:Label="Pick"`
        `photoshop:Urgency="1"`
      - В Lightroom Classic вы можете мгновенно отфильтровать отобранные кадры через фильтр по метке (Label) или создать смарт-коллекцию с условием `Label = Pick`.
      - В **Capture One Pro** эта отметка преобразуется в цветной тег (Color Tag).
    
    ### 3. Отклоненный снимок (Reject / Черный флаг)
    - В **Adobe Camera Raw, Adobe Bridge и darktable** отклоненный кадр обозначается значением `xmp:Rating="-1"`.
    - Z-Bridge записывает `xmp:Rating="-1"` и дублирует текстовую метку `xmp:Label="Reject"`.
    
    ### 4. Соглашение по именам файлов XMP
    - **DSC_0001.xmp (по умолчанию)**: стандарт Adobe Lightroom, ACR, Bridge, Capture One.
    - **DSC_0001.NEF.xmp**: формат, предпочитаемый darktable и некоторыми скриптами Linux.
    
    ### 5. Защита RAW-оригиналов
    - Оригинальные файлы Nikon (.NEF, .NRW, .HIF) никогда не модифицируются. Запись метаданных производится строго во внешние файлы .xmp с кодировкой UTF-8.
    """
}
