import Foundation

/// Типы действий, доступных фотографу на главном экране
public enum MainScreenActionType: String, Equatable, Sendable {
    case connectCamera = "connect_camera"
    case openConnectionGuide = "open_connection_guide"
    case retryConnection = "retry_connection"
    case importAllFromCard = "import_all_from_card"
    case selectCardFiles = "select_card_files"
    case refreshCard = "refresh_card"
    case viewTransferQueue = "view_transfer_queue"
    case resetFilters = "reset_filters"
}

/// Описание интерактивной кнопки действия на главном экране
public struct MainScreenAction: Equatable, Sendable {
    public let type: MainScreenActionType
    public let title: String
    public let systemImage: String?
    public let isPrimary: Bool
    public let isEnabled: Bool
    
    public init(
        type: MainScreenActionType,
        title: String,
        systemImage: String? = nil,
        isPrimary: Bool = true,
        isEnabled: Bool = true
    ) {
        self.type = type
        self.title = title
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
    }
}

/// Полноэкранное пустое состояние главного экрана
public struct MainScreenEmptyState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case disconnected
        case connecting
        case readingCard
        case cardReady
        case cardEmptyOrNoMatchingFiles
        case transferring
        case error
        case ftpWaiting
        case allFilteredOut
    }
    
    public let kind: Kind
    public let title: String
    public let description: String
    public let systemImage: String
    public let showsProgress: Bool
    public let progressValue: Double?
    public let primaryAction: MainScreenAction?
    public let secondaryAction: MainScreenAction?
    
    public init(
        kind: Kind,
        title: String,
        description: String,
        systemImage: String,
        showsProgress: Bool = false,
        progressValue: Double? = nil,
        primaryAction: MainScreenAction? = nil,
        secondaryAction: MainScreenAction? = nil
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.showsProgress = showsProgress
        self.progressValue = progressValue
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

/// Компактный плавающий статус поверх галереи (когда фотографии уже есть)
public struct MainScreenCompactBanner: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case info
        case warning
        case error
        case success
    }
    
    public let style: Style
    public let systemImage: String
    public let title: String
    public let message: String?
    public let showsProgress: Bool
    public let action: MainScreenAction?
    
    public init(
        style: Style,
        systemImage: String,
        title: String,
        message: String? = nil,
        showsProgress: Bool = false,
        action: MainScreenAction? = nil
    ) {
        self.style = style
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.showsProgress = showsProgress
        self.action = action
    }
}

/// Результирующее состояние главного экрана
public struct MainScreenState: Equatable, Sendable {
    /// Есть ли на устройстве сохраненные фотографии
    public let hasPhotos: Bool
    
    /// Скрыли ли активные фильтры все кадры сессии
    public let areAllPhotosFilteredOut: Bool
    
    /// Полноэкранное пустое состояние (когда галерея пуста или все отфильтровано)
    public let emptyState: MainScreenEmptyState?
    
    /// Компактный статус-баннер поверх галереи (когда фото есть, но требуется уведомить о статусе)
    public let compactBanner: MainScreenCompactBanner?
    
    public init(
        hasPhotos: Bool,
        areAllPhotosFilteredOut: Bool,
        emptyState: MainScreenEmptyState?,
        compactBanner: MainScreenCompactBanner?
    ) {
        self.hasPhotos = hasPhotos
        self.areAllPhotosFilteredOut = areAllPhotosFilteredOut
        self.emptyState = emptyState
        self.compactBanner = compactBanner
    }
}

/// Чистая тестируемая модель представления главного экрана
public struct MainScreenPresentationModel: Sendable {
    
    /// Рассчитывает состояние главного экрана на основе реальных данных системы
    public static func resolve(
        totalGalleryCount: Int,
        filteredGalleryCount: Int,
        hasActiveFilters: Bool,
        usbConnectionState: USBCameraConnectionState,
        isCatalogReady: Bool,
        catalogTotalCount: Int,
        catalogUnimportedCount: Int,
        isDownloading: Bool,
        activeTransferCount: Int,
        pendingQueueCount: Int,
        transferSpeedMBs: Double? = nil,
        isFTPServerRunning: Bool,
        ftpClientCount: Int,
        ftpServerIP: String?,
        ftpServerPort: UInt16,
        isFTPReceivingEnabled: Bool
    ) -> MainScreenState {
        let hasPhotos = totalGalleryCount > 0
        
        // СЦЕНАРИЙ 1: В сессии ЕСТЬ сохраненные фотографии
        if hasPhotos {
            // Если все фотографии скрыты фильтрами — показываем экран «Сбросить фильтры»
            if filteredGalleryCount == 0 && hasActiveFilters {
                let empty = MainScreenEmptyState(
                    kind: .allFilteredOut,
                    title: "Снимки скрыты фильтрами",
                    description: "На устройстве сохранено \(totalGalleryCount) кадр(ов), но активные фильтры скрыли все результаты.",
                    systemImage: "line.3.horizontal.decrease.circle",
                    showsProgress: false,
                    primaryAction: MainScreenAction(
                        type: .resetFilters,
                        title: "Сбросить фильтры",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isPrimary: true
                    )
                )
                return MainScreenState(
                    hasPhotos: true,
                    areAllPhotosFilteredOut: true,
                    emptyState: empty,
                    compactBanner: nil
                )
            }
            
            // Фотографии отображаются в галерее. Рассчитываем компактный баннер поверх интерфейса.
            let banner = resolveCompactBanner(
                usbConnectionState: usbConnectionState,
                isCatalogReady: isCatalogReady,
                catalogTotalCount: catalogTotalCount,
                catalogUnimportedCount: catalogUnimportedCount,
                isDownloading: isDownloading,
                activeTransferCount: activeTransferCount,
                pendingQueueCount: pendingQueueCount,
                isFTPServerRunning: isFTPServerRunning,
                ftpClientCount: ftpClientCount
            )
            
            return MainScreenState(
                hasPhotos: true,
                areAllPhotosFilteredOut: false,
                emptyState: nil,
                compactBanner: banner
            )
        }
        
        // СЦЕНАРИЙ 2: В сессии НЕТ фотографий (пустая галерея)
        // Рассчитываем полноэкранное объяснение ситуации и применимые действия
        let empty = resolveEmptyState(
            usbConnectionState: usbConnectionState,
            isCatalogReady: isCatalogReady,
            catalogTotalCount: catalogTotalCount,
            catalogUnimportedCount: catalogUnimportedCount,
            isDownloading: isDownloading,
            activeTransferCount: activeTransferCount,
            pendingQueueCount: pendingQueueCount,
            isFTPServerRunning: isFTPServerRunning,
            ftpClientCount: ftpClientCount,
            ftpServerIP: ftpServerIP,
            ftpServerPort: ftpServerPort,
            isFTPReceivingEnabled: isFTPReceivingEnabled
        )
        
        return MainScreenState(
            hasPhotos: false,
            areAllPhotosFilteredOut: false,
            emptyState: empty,
            compactBanner: nil
        )
    }
    
    // MARK: - Расчет полноэкранного пустого состояния
    
    private static func resolveEmptyState(
        usbConnectionState: USBCameraConnectionState,
        isCatalogReady: Bool,
        catalogTotalCount: Int,
        catalogUnimportedCount: Int,
        isDownloading: Bool,
        activeTransferCount: Int,
        pendingQueueCount: Int,
        isFTPServerRunning: Bool,
        ftpClientCount: Int,
        ftpServerIP: String?,
        ftpServerPort: UInt16,
        isFTPReceivingEnabled: Bool
    ) -> MainScreenEmptyState {
        
        // 1. Ошибка USB / Ограничение доступа
        switch usbConnectionState {
        case .error(let msg):
            return MainScreenEmptyState(
                kind: .error,
                title: "Ошибка USB подключения",
                description: msg,
                systemImage: "exclamationmark.triangle.fill",
                showsProgress: false,
                primaryAction: MainScreenAction(
                    type: .retryConnection,
                    title: "Повторить подключение",
                    systemImage: "arrow.clockwise",
                    isPrimary: true
                ),
                secondaryAction: MainScreenAction(
                    type: .connectCamera,
                    title: "Мастер подключения",
                    systemImage: "questionmark.circle",
                    isPrimary: false
                )
            )
            
        case .accessDenied(let reason):
            return MainScreenEmptyState(
                kind: .error,
                title: "Доступ к камере ограничен",
                description: reason,
                systemImage: "lock.fill",
                showsProgress: false,
                primaryAction: MainScreenAction(
                    type: .openConnectionGuide,
                    title: "Инструкция по разблокировке",
                    systemImage: "book.fill",
                    isPrimary: true
                )
            )
            
        default:
            break
        }
        
        // 2. Идёт передача снимков
        if isDownloading || activeTransferCount > 0 || pendingQueueCount > 0 {
            let totalInQueue = activeTransferCount + pendingQueueCount
            return MainScreenEmptyState(
                kind: .transferring,
                title: "Идёт передача снимков",
                description: "Активных загрузок: \(activeTransferCount), в очереди: \(pendingQueueCount) (всего: \(totalInQueue)).",
                systemImage: "arrow.down.circle.fill",
                showsProgress: true,
                primaryAction: MainScreenAction(
                    type: .viewTransferQueue,
                    title: "Перейти к очереди",
                    systemImage: "list.bullet.rectangle",
                    isPrimary: true
                )
            )
        }
        
        // 3. Подключение устанавливается (.discovered, .openingSession, .sessionOpened)
        switch usbConnectionState {
        case .discovered(let name):
            return MainScreenEmptyState(
                kind: .connecting,
                title: "Обнаружена камера",
                description: "Инициализация соединения с \(name)...",
                systemImage: "cable.connector",
                showsProgress: true,
                primaryAction: nil
            )
        case .openingSession(let name):
            return MainScreenEmptyState(
                kind: .connecting,
                title: "Подключение камеры",
                description: "\(name): установка соединения...",
                systemImage: "cable.connector",
                showsProgress: true,
                primaryAction: nil
            )
        case .sessionOpened(let name):
            return MainScreenEmptyState(
                kind: .connecting,
                title: "Камера подключена",
                description: "\(name): подготовка к чтению оглавления карты памяти...",
                systemImage: "cable.connector",
                showsProgress: true,
                primaryAction: nil
            )
        default:
            break
        }
        
        // 4. Читается карта памяти (.enumeratingCatalog)
        if case .enumeratingCatalog(let name, let itemsFound) = usbConnectionState {
            return MainScreenEmptyState(
                kind: .readingCard,
                title: "Чтение карты памяти",
                description: "\(name): найдено \(itemsFound) файлов...",
                systemImage: "creditcard",
                showsProgress: true,
                primaryAction: nil
            )
        }
        if usbConnectionState.isConnected && !isCatalogReady {
            let name = usbConnectionState.cameraName ?? "Nikon Z"
            return MainScreenEmptyState(
                kind: .readingCard,
                title: "Чтение оглавления карты",
                description: "\(name): найдено \(catalogTotalCount) файлов на карте...",
                systemImage: "creditcard",
                showsProgress: true,
                primaryAction: nil
            )
        }
        
        // 5. Карта готова
        if isCatalogReady {
            if catalogUnimportedCount > 0 {
                return MainScreenEmptyState(
                    kind: .cardReady,
                    title: "Карта памяти готова к импорту",
                    description: "На карте найдено \(catalogTotalCount) файлов, из них \(catalogUnimportedCount) доступно для импорта на устройство.",
                    systemImage: "tray.and.arrow.down.fill",
                    showsProgress: false,
                    primaryAction: MainScreenAction(
                        type: .importAllFromCard,
                        title: "Загрузить с камеры",
                        systemImage: "arrow.down.circle.fill",
                        isPrimary: true
                    ),
                    secondaryAction: MainScreenAction(
                        type: .selectCardFiles,
                        title: "Выбрать снимки",
                        systemImage: "checklist",
                        isPrimary: false
                    )
                )
            } else {
                // На карте нет подходящих файлов или все уже импортированы
                let desc = catalogTotalCount == 0
                    ? "На карте памяти камеры нет файлов. Сделайте снимок на камеру (live tethering)."
                    : "Все файлы с карты памяти (\(catalogTotalCount)) уже импортированы на устройство. Сделайте новый снимок."
                return MainScreenEmptyState(
                    kind: .cardEmptyOrNoMatchingFiles,
                    title: "На карте нет подходящих файлов",
                    description: desc,
                    systemImage: "photo.on.rectangle.angled",
                    showsProgress: false,
                    primaryAction: MainScreenAction(
                        type: .refreshCard,
                        title: "Обновить оглавление",
                        systemImage: "arrow.clockwise",
                        isPrimary: true
                    ),
                    secondaryAction: MainScreenAction(
                        type: .selectCardFiles,
                        title: "Выбрать снимки",
                        systemImage: "folder",
                        isPrimary: false
                    )
                )
            }
        }
        
        // 6. Ожидание передачи по Wi-Fi FTP
        if isFTPServerRunning {
            let ipText = ftpServerIP ?? "Wi-Fi IP"
            let clientsText = ftpClientCount > 0 ? "Камера подключена (\(ftpClientCount) клиенс)." : "Ожидание подключения камеры."
            return MainScreenEmptyState(
                kind: .ftpWaiting,
                title: "Ожидание передачи с камеры",
                description: "FTP-сервер запущен: \(ipText):\(ftpServerPort). \(clientsText) Сделайте снимок на камеру для автоматической передачи.",
                systemImage: "wifi",
                showsProgress: false,
                primaryAction: MainScreenAction(
                    type: .openConnectionGuide,
                    title: "Инструкция настройки камеры",
                    systemImage: "info.circle",
                    isPrimary: true
                )
            )
        }
        
        // 7. Камера не подключена (USB отключен, FTP не запущен)
        return MainScreenEmptyState(
            kind: .disconnected,
            title: "Камера не подключена",
            description: "Подключите камеру Nikon через USB-C кабель в режиме «Передача файлов» или настройте беспроводную передачу по Wi-Fi FTP.",
            systemImage: "camera.viewfinder",
            showsProgress: false,
            primaryAction: MainScreenAction(
                type: .connectCamera,
                title: "Подключить камеру",
                systemImage: "cable.connector",
                isPrimary: true
            ),
            secondaryAction: MainScreenAction(
                type: .openConnectionGuide,
                title: "Инструкция подключения",
                systemImage: "book",
                isPrimary: false
            )
        )
    }
    
    // MARK: - Расчет компактного статуса поверх галереи
    
    private static func resolveCompactBanner(
        usbConnectionState: USBCameraConnectionState,
        isCatalogReady: Bool,
        catalogTotalCount: Int,
        catalogUnimportedCount: Int,
        isDownloading: Bool,
        activeTransferCount: Int,
        pendingQueueCount: Int,
        isFTPServerRunning: Bool,
        ftpClientCount: Int
    ) -> MainScreenCompactBanner? {
        
        // 1. Ошибка USB
        switch usbConnectionState {
        case .error(let msg):
            return MainScreenCompactBanner(
                style: .error,
                systemImage: "exclamationmark.triangle.fill",
                title: "Ошибка USB: \(msg)",
                message: nil,
                showsProgress: false,
                action: MainScreenAction(
                    type: .retryConnection,
                    title: "Повторить",
                    systemImage: "arrow.clockwise",
                    isPrimary: true
                )
            )
        case .accessDenied(let reason):
            return MainScreenCompactBanner(
                style: .error,
                systemImage: "lock.fill",
                title: "Доступ ограничен: \(reason)",
                message: nil,
                showsProgress: false,
                action: MainScreenAction(
                    type: .openConnectionGuide,
                    title: "Инструкция",
                    systemImage: "questionmark.circle",
                    isPrimary: false
                )
            )
        default:
            break
        }
        
        // 2. Идёт загрузка
        if isDownloading || activeTransferCount > 0 || pendingQueueCount > 0 {
            return MainScreenCompactBanner(
                style: .info,
                systemImage: "arrow.down.circle.fill",
                title: "USB импорт: \(activeTransferCount) акт., \(pendingQueueCount) в очереди",
                message: nil,
                showsProgress: true,
                action: MainScreenAction(
                    type: .viewTransferQueue,
                    title: "Очередь",
                    systemImage: "list.bullet",
                    isPrimary: true
                )
            )
        }
        
        // 3. Подключение устанавливается (.discovered, .openingSession, .sessionOpened)
        switch usbConnectionState {
        case .discovered(let name):
            return MainScreenCompactBanner(
                style: .info,
                systemImage: "cable.connector",
                title: "Обнаружена: \(name)",
                message: nil,
                showsProgress: true,
                action: nil
            )
        case .openingSession(let name):
            return MainScreenCompactBanner(
                style: .info,
                systemImage: "cable.connector",
                title: "\(name): подключение...",
                message: nil,
                showsProgress: true,
                action: nil
            )
        case .sessionOpened(let name):
            return MainScreenCompactBanner(
                style: .info,
                systemImage: "cable.connector",
                title: "\(name): камера подключена",
                message: nil,
                showsProgress: true,
                action: nil
            )
        default:
            break
        }
        
        // 4. Чтение оглавления карты (.enumeratingCatalog)
        if case .enumeratingCatalog(_, let itemsFound) = usbConnectionState {
            return MainScreenCompactBanner(
                style: .info,
                systemImage: "creditcard",
                title: "Чтение карты: найдено \(itemsFound) файлов...",
                message: nil,
                showsProgress: true,
                action: nil
            )
        }
        if usbConnectionState.isConnected && !isCatalogReady {
            return MainScreenCompactBanner(
                style: .info,
                systemImage: "creditcard",
                title: "Чтение оглавления карты...",
                message: nil,
                showsProgress: true,
                action: nil
            )
        }
        
        // 5. Карта готова и есть неимпортированные файлы
        if isCatalogReady && catalogUnimportedCount > 0 {
            return MainScreenCompactBanner(
                style: .success,
                systemImage: "tray.and.arrow.down",
                title: "На карте \(catalogUnimportedCount) новых файлов",
                message: nil,
                showsProgress: false,
                action: MainScreenAction(
                    type: .importAllFromCard,
                    title: "Загрузить все",
                    systemImage: "arrow.down.circle",
                    isPrimary: true
                )
            )
        }
        
        // 6. Потеря подключения при наличии фото в галерее
        if usbConnectionState == .disconnected && !isFTPServerRunning {
            return MainScreenCompactBanner(
                style: .warning,
                systemImage: "cable.connector.slash",
                title: "Камера отключена",
                message: "Новые снимки не поступают",
                showsProgress: false,
                action: MainScreenAction(
                    type: .connectCamera,
                    title: "Подключить",
                    systemImage: "cable.connector",
                    isPrimary: true
                )
            )
        }
        
        // Штатное состояние (камера подключена и готова, либо FTP ждет без ошибок)
        return nil
    }
}
