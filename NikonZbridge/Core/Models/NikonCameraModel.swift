import Foundation

/// Поколение процессора обработки изображений камеры
public enum NikonProcessorGeneration: String, Sendable, Codable, CaseIterable {
    case expeed7 = "EXPEED 7"
    case dualExpeed6 = "Dual EXPEED 6"
    case expeed6 = "EXPEED 6"
}

/// Физический тип сетевого или кабельного транспорта камеры
public enum NikonConnectionTransport: String, Sendable, Codable, CaseIterable, Identifiable {
    case directUSB = "direct_usb"
    case builtInEthernet = "builtin_ethernet"
    case usbToEthernet = "usb_ethernet"
    case builtInWiFiFTP = "builtin_wifi_ftp"
    case wt7Transmitter = "wt7_transmitter"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .directUSB:
            return "Прямой кабель USB-C (PTP)"
        case .builtInEthernet:
            return "Встроенный Ethernet RJ-45 (FTP)"
        case .usbToEthernet:
            return "Адаптер USB-C -> Ethernet (FTP)"
        case .builtInWiFiFTP:
            return "Встроенный Wi-Fi (FTP)"
        case .wt7Transmitter:
            return "Передатчик WT-7 (Ethernet / Wi-Fi)"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .directUSB:
            return "Кабель в Mac/iPad. Чтение карты памяти, автоприём новых снимков. Не требует настройки сети."
        case .builtInEthernet:
            return "Сетевой провод RJ-45 прямо в корпус камеры. Высочайшая надёжность и дистанции до 100 м."
        case .usbToEthernet:
            return "USB-C Ethernet адаптер в порт данных камеры. Проводная сеть без встроенного разъёма RJ-45."
        case .builtInWiFiFTP:
            return "Беспроводная передача без проводов на встроенную точку доступа или через общий студийный роутер."
        case .wt7Transmitter:
            return "Высокоскоростной внешний модуль с аппаратным разъемом LAN и антеннами Wi-Fi."
        }
    }
    
    public var isFTP: Bool {
        switch self {
        case .builtInEthernet, .usbToEthernet, .builtInWiFiFTP, .wt7Transmitter:
            return true
        case .directUSB:
            return false
        }
    }
    
    public var isWired: Bool {
        switch self {
        case .directUSB, .builtInEthernet, .usbToEthernet:
            return true
        case .builtInWiFiFTP, .wt7Transmitter:
            return false
        }
    }
}

/// Шаг инструкции по настройке камеры
public struct CameraInstructionStep: Identifiable, Sendable, Codable {
    public let id: Int
    public let title: String
    public let menuPathRu: String
    public let menuPathEn: String
    public let details: String
    public let tip: String?
    
    public init(
        id: Int,
        title: String,
        menuPathRu: String,
        menuPathEn: String,
        details: String,
        tip: String? = nil
    ) {
        self.id = id
        self.title = title
        self.menuPathRu = menuPathRu
        self.menuPathEn = menuPathEn
        self.details = details
        self.tip = tip
    }
}

/// Модель камеры линейки Nikon Z
public enum NikonCameraModel: String, Sendable, Codable, CaseIterable, Identifiable {
    case z9 = "Z 9"
    case z8 = "Z 8"
    case z7ii = "Z 7II"
    case z7 = "Z 7"
    case z6iii = "Z 6III"
    case z6ii = "Z 6II"
    case z6 = "Z 6"
    case zf = "Z f"
    case z5ii = "Z 5II"
    case z5iic = "Z 5IIC"
    case z5 = "Z 5"
    case z50ii = "Z 50II"
    case z50 = "Z 50"
    case z30 = "Z 30"
    case zfc = "Z fc"
    
    public var id: String { rawValue }
    
    public var fullName: String { "Nikon \(rawValue)" }
    
    /// Каноническое коммерческое имя камеры (например: "Nikon Z5 II", "Nikon Z8")
    public var marketingName: String {
        switch self {
        case .z9: return "Nikon Z9"
        case .z8: return "Nikon Z8"
        case .z7ii: return "Nikon Z7 II"
        case .z7: return "Nikon Z7"
        case .z6iii: return "Nikon Z6 III"
        case .z6ii: return "Nikon Z6 II"
        case .z6: return "Nikon Z6"
        case .zf: return "Nikon Z f"
        case .zfc: return "Nikon Z fc"
        case .z5ii, .z5iic: return "Nikon Z5 II"
        case .z5: return "Nikon Z5"
        case .z50ii: return "Nikon Z50 II"
        case .z50: return "Nikon Z50"
        case .z30: return "Nikon Z30"
        }
    }
    
    /// Короткое имя без марки (например: "Z5 II", "Z8")
    public var shortMarketingName: String {
        switch self {
        case .z9: return "Z9"
        case .z8: return "Z8"
        case .z7ii: return "Z7 II"
        case .z7: return "Z7"
        case .z6iii: return "Z6 III"
        case .z6ii: return "Z6 II"
        case .z6: return "Z6"
        case .zf: return "Z f"
        case .zfc: return "Z fc"
        case .z5ii, .z5iic: return "Z5 II"
        case .z5: return "Z5"
        case .z50ii: return "Z50 II"
        case .z50: return "Z50"
        case .z30: return "Z30"
        }
    }
    
    /// Имя изображения камеры в Asset Catalog приложения
    public var assetImageName: String {
        switch self {
        case .z9: return "nikon_z9"
        case .z8: return "nikon_z8"
        case .z7ii: return "nikon_z7ii"
        case .z7: return "nikon_z7"
        case .z6iii: return "nikon_z6iii"
        case .z6ii: return "nikon_z6ii"
        case .z6: return "nikon_z6"
        case .zf: return "nikon_zf"
        case .zfc: return "nikon_zfc"
        case .z5ii, .z5iic: return "nikon_z5ii"
        case .z5: return "nikon_z5"
        case .z50ii: return "nikon_z50ii"
        case .z50: return "nikon_z50"
        case .z30: return "nikon_z30"
        }
    }
    
    /// Официальный URL студийного фото продукта на сервере Nikon Imaging
    public var officialImageURL: URL? {
        let slug: String
        switch self {
        case .z9: slug = "z_9"
        case .z8: slug = "z_8"
        case .z7ii: slug = "z_7_2"
        case .z7: slug = "z_7"
        case .z6iii: slug = "z6_3"
        case .z6ii: slug = "z_6_2"
        case .z6: slug = "z_6"
        case .zf: slug = "z_f"
        case .zfc: slug = "z_fc"
        case .z5ii, .z5iic: slug = "z5_2"
        case .z5: slug = "z_5"
        case .z50ii: slug = "z50_2"
        case .z50: slug = "z_50"
        case .z30: slug = "z_30"
        }
        return URL(string: "https://imaging.nikon.com/imaging/lineup/mirrorless/\(slug)/img/product_01_01.jpg")
    }
    
    /// Распознавание модели камеры из сырого идентификатора USB PTP (например "NIKON DSC Z 5_2", "Z5_2", "NIKON Z 6_3")
    public static func match(from rawName: String?) -> NikonCameraModel? {
        guard let raw = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        
        var clean = raw.uppercased()
        clean = clean.replacingOccurrences(of: "NIKON", with: "")
        clean = clean.replacingOccurrences(of: "DSC", with: "")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "-", with: "_")
        
        let compact = clean.replacingOccurrences(of: " ", with: "")
        
        // Сначала проверяем модели с поколением (_2, _3, II, III), чтобы "Z 5_2" не сматчился на "Z 5"
        if compact.contains("50_2") || compact.contains("50II") || compact.contains("50_II") {
            return .z50ii
        }
        if compact.contains("5_2") || compact.contains("5II") || compact.contains("5_II") {
            return .z5ii
        }
        if compact.contains("6_3") || compact.contains("6III") || compact.contains("6_III") {
            return .z6iii
        }
        if compact.contains("6_2") || compact.contains("6II") || compact.contains("6_II") {
            return .z6ii
        }
        if compact.contains("7_2") || compact.contains("7II") || compact.contains("7_II") {
            return .z7ii
        }
        if compact.contains("ZFC") || compact.contains("FC") {
            return .zfc
        }
        if compact.contains("ZF") {
            return .zf
        }
        if compact.contains("Z9") {
            return .z9
        }
        if compact.contains("Z8") {
            return .z8
        }
        if compact.contains("Z7") {
            return .z7
        }
        if compact.contains("Z6") {
            return .z6
        }
        if compact.contains("Z50") {
            return .z50
        }
        if compact.contains("Z30") {
            return .z30
        }
        if compact.contains("Z5") {
            return .z5
        }
        
        // Поиск по CaseIterable
        for model in allCases {
            let key = model.rawValue.replacingOccurrences(of: " ", with: "")
            if compact == key || compact.contains(key) {
                return model
            }
        }
        
        return nil
    }
    
    /// Нормализованное отображаемое имя (например "Nikon Z5 II" вместо "Z5_2" или "NIKON DSC Z 5_2")
    public static func normalizedDisplayName(from rawName: String?) -> String {
        guard let raw = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Nikon Z"
        }
        if let matched = match(from: raw) {
            return matched.marketingName
        }
        
        var clean = raw
        clean = clean.replacingOccurrences(of: "NIKON DSC ", with: "")
        clean = clean.replacingOccurrences(of: "NIKON ", with: "")
        clean = clean.replacingOccurrences(of: "DSC ", with: "")
        clean = clean.replacingOccurrences(of: "_2", with: " II")
        clean = clean.replacingOccurrences(of: "_3", with: " III")
        clean = clean.replacingOccurrences(of: "_", with: " ")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.lowercased().hasPrefix("nikon") {
            clean = "Nikon " + clean
        }
        return clean
    }
    
    public var processor: NikonProcessorGeneration {
        switch self {
        case .z9, .z8, .z6iii, .zf, .z5ii, .z5iic, .z50ii:
            return .expeed7
        case .z7ii, .z6ii:
            return .dualExpeed6
        case .z7, .z6, .z5, .z50, .z30, .zfc:
            return .expeed6
        }
    }
    
    public var isFullFrame: Bool {
        switch self {
        case .z50, .z50ii, .z30, .zfc:
            return false
        default:
            return true
        }
    }
    
    public var sensorDescription: String {
        isFullFrame ? "FX (Полнокадровый)" : "DX (Кроп 1.5x)"
    }
    
    /// Наличие встроенного разъема RJ-45
    public var hasBuiltInRJ45: Bool {
        self == .z9
    }
    
    /// Наличие двух отдельных портов USB-C (Data + Power Delivery)
    public var hasDualUSBPorts: Bool {
        self == .z8
    }
    
    /// Тип физического USB разъема
    public var usbPortType: String {
        switch self {
        case .z50:
            return "Micro-USB (Micro-B)"
        case .z8:
            return "Двойной USB-C (Верхний: Передача данных / USB-LAN, Нижний: Питание USB-PD)"
        default:
            return "USB-C (SuperSpeed USB 3.2)"
        }
    }
    
    /// Поддерживаемые диапазоны Wi-Fi
    public var wifiBands: [String] {
        switch self {
        case .z9, .z8, .z6iii, .zf, .z5ii, .z5iic, .z7ii, .z6ii, .z7, .z6, .z50ii:
            return ["2.4 ГГц", "5 ГГц (IEEE 802.11ac/ax)"]
        case .z5, .z50, .z30, .zfc:
            return ["2.4 ГГц (IEEE 802.11b/g/n)"]
        }
    }
    
    /// Список транспортов, аппаратно и программно поддерживаемых данной моделью
    public var supportedTransports: [NikonConnectionTransport] {
        switch self {
        case .z9:
            return [.directUSB, .builtInEthernet, .builtInWiFiFTP]
        case .z8, .z6iii, .zf, .z5ii, .z5iic:
            return [.directUSB, .usbToEthernet, .builtInWiFiFTP]
        case .z7ii, .z6ii:
            return [.directUSB, .builtInWiFiFTP, .wt7Transmitter]
        case .z7, .z6:
            return [.directUSB, .builtInWiFiFTP, .wt7Transmitter]
        case .z5:
            return [.directUSB, .builtInWiFiFTP]
        case .z50ii:
            return [.directUSB, .builtInWiFiFTP]
        case .z50, .z30, .zfc:
            return [.directUSB, .builtInWiFiFTP]
        }
    }
    
    /// Поддерживает ли данная модель прямое сетевое подключение по проводу (Ethernet)
    public var supportsWiredNetwork: Bool {
        hasBuiltInRJ45 || supportedTransports.contains(.usbToEthernet) || supportedTransports.contains(.wt7Transmitter)
    }
    
    // MARK: - Пошаговые инструкции под выбранную модель и транспорт
    
    public func instructions(for transport: NikonConnectionTransport) -> [CameraInstructionStep] {
        switch (self.processor, transport) {
            
        // =====================================================================
        // EXPEED 7 (Z 9, Z 8, Z 6III, Z f)
        // =====================================================================
        case (.expeed7, .directUSB):
            let steps = [
                CameraInstructionStep(
                    id: 1,
                    title: "Настройка приоритета порта USB",
                    menuPathRu: "Меню настройки ➔ Приоритет подключения USB",
                    menuPathEn: "Setup Menu ➔ USB connection priority",
                    details: "Установите значение «Передача данных» (Upload). Это переводит порт в режим MTP/PTP для мгновенного обнаружения приложением.",
                    tip: self == .z8 ? "Внимание: на Z 8 подключайте кабель к ВЕРХНЕМУ порту с пиктограммой вилки/стрелок (Data)." : nil
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Предотвращение засыпания камеры",
                    menuPathRu: "Польз. настройки ➔ c: Таймеры/фикс. AE ➔ c3: Время отключения питания ➔ Таймер режима ожидания",
                    menuPathEn: "Custom Settings ➔ c: Timers/AE lock ➔ c3: Power off delay ➔ Standby timer",
                    details: "Установите значение «Без ограничений» (No limit) или как минимум «30 мин». Если таймер камеры истечёт во время съёмки, связь по кабелю разорвётся.",
                    tip: "При питании от внешнего источника через нижний порт USB-PD камера может работать неограниченно."
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Физическое подключение кабеля",
                    menuPathRu: "Кабель USB-C ➔ Порт камеры ➔ iPad / Mac",
                    menuPathEn: "USB-C cable ➔ Camera port ➔ iPad / Mac",
                    details: "Используйте надёжный кабель USB 3.2 (до 3 метров) с фиксатором на клетке камеры. При подключении в приложении появится бейдж «USB Подключено».",
                    tip: "Снимки будут поступать в приложение автоматически сразу после срабатывания затвора."
                )
            ]
            return steps
            
        case (.expeed7, .builtInEthernet): // Z 9
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Подключение сетевого кабеля RJ-45",
                    menuPathRu: "Разъём 1000BASE-T RJ-45 на корпусе Z 9",
                    menuPathEn: "Built-in 1000BASE-T RJ-45 port on Z 9 body",
                    details: "Вставьте кабель Cat 5e/Cat 6 в порт RJ-45 камеры и соедините с Mac/iPad (напрямую или через сетевой коммутатор).",
                    tip: "Зеленый светодиод у разъема подтверждает наличие физического линка 1 Гбит/с."
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Создание профиля FTP-сервера",
                    menuPathRu: "Меню сети ➔ Подключение к FTP-серверу ➔ Настройки сети ➔ Создать профиль",
                    menuPathEn: "Network Menu ➔ Connect to FTP server ➔ Network settings ➔ Create profile",
                    details: "Выберите метод мастера настройки. В качестве типа соединения выберите «Проводная сеть (Wired LAN)».",
                    tip: "Камера автоматически получит IP-адрес по DHCP, либо вы можете ввести статическую подсеть."
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Ввод параметров сервера приложения",
                    menuPathRu: "Тип FTP: FTP ➔ Адрес сервера ➔ Вход по логину/паролю",
                    menuPathEn: "FTP type: FTP ➔ Server address ➔ User ID & Password",
                    details: "Введите IP-адрес и порт 2121 из Шага 5 нашего Мастера. Введите отображаемый Логин и Пароль.",
                    tip: "Порт по умолчанию в Nikon Z-Bridge: 2121 (не 21!). Убедитесь, что порт указан в настройках профиля."
                ),
                CameraInstructionStep(
                    id: 4,
                    title: "Включение автоотправки при съёмке",
                    menuPathRu: "Меню сети ➔ Подключение к FTP-серверу ➔ Параметры ➔ Автоотправка",
                    menuPathEn: "Network Menu ➔ Connect to FTP server ➔ Options ➔ Auto send",
                    details: "Установите «ВКЛ» (ON). Камера будет немедленно передавать каждый кадр сразу после экспонирования.",
                    tip: "Вы также можете выбрать, отправлять ли только RAW, только JPEG или оба формата в пункте «Отправка RAW + JPEG»."
                )
            ]
            
        case (.expeed7, .usbToEthernet): // Z 8, Z 6III, Z f
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Подключение адаптера USB-C -> Ethernet",
                    menuPathRu: "ВЕРХНИЙ порт USB-C (Data) ➔ Переходник USB-C RJ-45",
                    menuPathEn: "UPPER USB-C port (Data) ➔ USB-C RJ-45 Adapter",
                    details: "Вставьте поддерживаемый адаптер USB-C Gigabit Ethernet в порт данных камеры. Соедините сетевым кабелем с Mac/iPad.",
                    tip: "Рекомендуются адаптеры на чипсетах Realtek RTL8153 или AX88179 (Anker, Apple, Belkin, Ugreen)."
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Активация режима USB-LAN в меню сети",
                    menuPathRu: "Меню сети ➔ USB-LAN",
                    menuPathEn: "Network Menu ➔ USB-LAN",
                    details: "Переведите переключатель в положение «ВКЛ» (ON). В строке состояния камеры появится значок кабельного подключения.",
                    tip: "Если пункт USB-LAN неактивен, проверьте, вставлен ли адаптер в верхний порт данных, а не в порт зарядки."
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Создание профиля FTP-сервера",
                    menuPathRu: "Меню сети ➔ Подключение к FTP-серверу ➔ Создать профиль ➔ Проводная сеть",
                    menuPathEn: "Network Menu ➔ Connect to FTP server ➔ Create profile ➔ Wired LAN",
                    details: "Введите IP-адрес Ethernet-интерфейса, порт 2121 и учетные данные из Шага 5.",
                    tip: "При прямом кабеле от камеры к iPad без роутера задайте на камере статический IP (например 192.168.8.10, маска 255.255.255.0)."
                ),
                CameraInstructionStep(
                    id: 4,
                    title: "Активация автоматической передачи",
                    menuPathRu: "Меню сети ➔ Подключение к FTP-серверу ➔ Параметры ➔ Автоотправка ➔ ВКЛ",
                    menuPathEn: "Network Menu ➔ Connect to FTP server ➔ Options ➔ Auto send ➔ ON",
                    details: "Каждый снятый кадр автоматически отправляется по кабелю на iPad/Mac на максимальной скорости гигабитного адаптера.",
                    tip: nil
                )
            ]
            
        case (.expeed7, .builtInWiFiFTP):
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Выбор режима сети Wi-Fi",
                    menuPathRu: "Меню сети ➔ Подключение к FTP-серверу ➔ Настройки сети ➔ Создать профиль ➔ Беспроводная сеть",
                    menuPathEn: "Network Menu ➔ Connect to FTP server ➔ Network settings ➔ Create profile ➔ Wi-Fi",
                    details: "Выберите режим прямого подключения к iPad/Mac («Прямое соединение / Direct link») или подключение к общей студийной сети Wi-Fi («Поиск сети Wi-Fi»).",
                    tip: "Для максимальной скорости на камерах с Expeed 7 используйте сеть 5 ГГц."
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Ввод реквизитов FTP-сервера",
                    menuPathRu: "Подключение к FTP-серверу ➔ Настройки FTP",
                    menuPathEn: "Connect to FTP server ➔ FTP setup",
                    details: "Укажите IP-адрес Wi-Fi интерфейса из Шага 5, порт 2121 и учётную запись (Логин и Пароль).",
                    tip: "Режим PASV (Пассивный) должен быть включен в настройках FTP камеры."
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Включение автоотправки",
                    menuPathRu: "Меню сети ➔ Подключение к FTP-серверу ➔ Параметры ➔ Автоотправка ➔ ВКЛ",
                    menuPathEn: "Network Menu ➔ Connect to FTP server ➔ Options ➔ Auto send ➔ ON",
                    details: "При успешном соединении значок FTP на экране камеры загорится зеленым цветом.",
                    tip: nil
                )
            ]
            
        // =====================================================================
        // EXPEED 6 & DUAL EXPEED 6 (Z 7II, Z 6II, Z 7, Z 6, Z 5, DX)
        // =====================================================================
        case (_, .directUSB):
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Подключение кабеля USB",
                    menuPathRu: "Разъем USB камеры ➔ Кабель USB ➔ iPad / Mac",
                    menuPathEn: "Camera USB port ➔ USB cable ➔ iPad / Mac",
                    details: "Соедините камеру качественным кабелем. Камера перейдет в режим связи с компьютером (на дисплее появится значок USB).",
                    tip: self == .z50 ? "На Nikon Z 50 используется разъем Micro-USB. Используйте качественный кабель с поддержкой передачи данных (Data), а не только зарядки." : nil
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Настройка таймера автоотключения",
                    menuPathRu: "Меню польз. настроек ➔ c: Таймеры ➔ c3: Время отключения питания ➔ Таймер режима ожидания",
                    menuPathEn: "Custom Settings ➔ c: Timers ➔ c3: Power off delay ➔ Standby timer",
                    details: "Увеличьте время засыпания камеры (рекомендуется «Без ограничений» или «30 мин»), чтобы предотвратить обрыв связи во время паузы в съемке.",
                    tip: nil
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Импорт снимков в приложении",
                    menuPathRu: "Приложение Nikon Z-Bridge ➔ Сессия",
                    menuPathEn: "Nikon Z-Bridge App ➔ Session",
                    details: "Приложение сразу увидит подключенную камеру. Новые кадры будут скачиваться автоматически в фоновом режиме очереди.",
                    tip: "Также вам доступен просмотр содержимого карты памяти по кнопке «Карта» в верхнем баре."
                )
            ]
            
        case (_, .builtInWiFiFTP):
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Создание сетевого профиля",
                    menuPathRu: "Меню сети ➔ Подключение к ПК / FTP ➔ Настройки сети ➔ Создать профиль",
                    menuPathEn: "Network Menu ➔ Connect to PC / FTP ➔ Network settings ➔ Create profile",
                    details: "Выберите беспроводное соединение и подключитесь к той же Wi-Fi сети, в которой находится Mac/iPad, либо создайте прямое соединение с устройством.",
                    tip: "Для первого поколения Z 6 / Z 7 убедитесь, что установлена прошивка v3.60 для максимальной стабильности Wi-Fi."
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Настройка адреса и порта FTP",
                    menuPathRu: "Настройки FTP ➔ Адрес сервера и Порт",
                    menuPathEn: "FTP setup ➔ Server address and Port",
                    details: "Введите IP-адрес Wi-Fi из Шага 5 и обязательно укажите нестандартный порт 2121. Введите логин и пароль.",
                    tip: "Пассивный режим (PASV) должен быть включен."
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Автоматическая отправка",
                    menuPathRu: "Подключение к FTP ➔ Параметры ➔ Автоотправка ➔ ВКЛ",
                    menuPathEn: "Connect to FTP ➔ Options ➔ Auto send ➔ ON",
                    details: "Камера начнет передачу отснятых кадров по беспроводной сети.",
                    tip: nil
                )
            ]
            
        case (_, .wt7Transmitter):
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Подключение передатчика WT-7",
                    menuPathRu: "Монтаж блока WT-7 к штативному гнезду и разъемам камеры",
                    menuPathEn: "Mount WT-7 to tripod socket & camera ports",
                    details: "Закрепите блок WT-7 и соедините интерфейсный кабель с портом USB камеры. Включите питание передатчика.",
                    tip: "WT-7 оснащен встроенным портом RJ-45 1000BASE-T и мощной антенной Wi-Fi."
                ),
                CameraInstructionStep(
                    id: 2,
                    title: "Выбор режима беспроводного передатчика",
                    menuPathRu: "Меню настройки ➔ Беспроводной передатчик (WT-7) ➔ Режим ➔ FTP",
                    menuPathEn: "Setup Menu ➔ Wireless transmitter (WT-7) ➔ Mode ➔ FTP",
                    details: "Выберите режим передачи файлов по FTP (через Ethernet или Wi-Fi).",
                    tip: nil
                ),
                CameraInstructionStep(
                    id: 3,
                    title: "Настройка адреса сервера",
                    menuPathRu: "Настройки сети ➔ Настройки мастера ➔ Ввод IP и порта 2121",
                    menuPathEn: "Network settings ➔ Wizard setup ➔ Enter IP & Port 2121",
                    details: "Укажите IP-адрес из Шага 5 мастера, порт 2121, логин и пароль.",
                    tip: nil
                )
            ]
            
        default:
            return [
                CameraInstructionStep(
                    id: 1,
                    title: "Подключение устройства",
                    menuPathRu: "Меню настройки / Меню сети",
                    menuPathEn: "Setup Menu / Network Menu",
                    details: "Подключите камеру выбранным способом, следуя руководству пользователя вашей модели.",
                    tip: nil
                )
            ]
        }
    }
}
