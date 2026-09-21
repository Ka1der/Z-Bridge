import Foundation
import CoreGraphics
import SQLite3
import SwiftUI

@inline(__always)
func verify(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Verification failed: \(message)", file: file, line: line)
    }
}

@main
struct SessionsAndSettingsVerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ РАЗДЕЛА «СЕССИИ» И «НАСТРОЙКИ» ===")
        
        let suite = SessionsAndSettingsVerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ РАЗДЕЛА «СЕССИИ» И «НАСТРОЙКИ» УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class SessionsAndSettingsVerificationSuite {
    let tempBaseURL: URL
    let dbURL: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionsSettingsTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempBaseURL = tempDir
        self.dbURL = tempDir.appendingPathComponent("sessions_settings_catalog.sqlite")
    }
    
    func runAllTests() async throws {
        defer { try? FileManager.default.removeItem(at: tempBaseURL) }
        
        try await testSettingsFiveGroupsStructure()
        try await testDefaultEmptyStartupSession()
        try await testResumeLastSessionTogglePersistence()
        try await testSessionSwitchPreservesOriginalFiles()
        try await testSessionStatsFramesCountAndFormatting()
        try await testSessionMetadataPersistence()
        try await testThumbnailCacheClearDoesNotAffectDiskFiles()
        try await testDiagnosticsStoragePathsAndSQLiteWALStats()
        try await testCatalogReconciliationSafety()
    }
    
    // MARK: - 1. Тест структуры 5 профессиональных групп настроек
    func testSettingsFiveGroupsStructure() async throws {
        print("\n--- [1/9] Тест структуры 5 профессиональных групп настроек ---")
        
        let tabs = SettingsTab.allCases
        verify(tabs.count == 5, "В настройках должно быть ровно 5 групп")
        
        verify(tabs[0] == .connection, "Группа 1: .connection")
        verify(tabs[0].title == "Подключение", "Название группы 1: Подключение")
        verify(!tabs[0].subtitle.isEmpty, "Подзаголовок группы 1 не должен быть пустым")
        
        verify(tabs[1] == .importTab, "Группа 2: .importTab")
        verify(tabs[1].title == "Импорт", "Название группы 2: Импорт")
        verify(!tabs[1].subtitle.isEmpty, "Подзаголовок группы 2 не должен быть пустым")
        
        verify(tabs[2] == .sessions, "Группа 3: .sessions")
        verify(tabs[2].title == "Сессии и хранение", "Название группы 3: Сессии и хранение")
        verify(!tabs[2].subtitle.isEmpty, "Подзаголовок группы 3 не должен быть пустым")
        
        verify(tabs[3] == .clientScreen, "Группа 4: .clientScreen")
        verify(tabs[3].title == "Клиентский экран", "Название группы 4: Клиентский экран")
        verify(!tabs[3].subtitle.isEmpty, "Подзаголовок группы 4 не должен быть пустым")
        
        verify(tabs[4] == .diagnostics, "Группа 5: .diagnostics")
        verify(tabs[4].title == "Диагностика", "Название группы 5: Диагностика")
        verify(!tabs[4].subtitle.isEmpty, "Подзаголовок группы 5 не должен быть пустым")
        
        print("  ✓ Все 5 групп настроек корректно определены, имеют полные названия и подзаголовки")
    }
    
    // MARK: - 2. Тест пустой стартовой сессии по умолчанию
    func testDefaultEmptyStartupSession() async throws {
        print("\n--- [2/9] Тест пустой стартовой сессии по умолчанию ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        // Создаем предыдущую сессию со снимком
        await coordinator.bootstrap()
        let prev = await coordinator.activeSession
        let photoURL = prev.folderURL.appendingPathComponent("DSC_PREV.JPG")
        let testData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        try testData.write(to: photoURL)
        await db.upsertAsset(MediaAsset(sessionID: prev.id, filename: "DSC_PREV.JPG", fileURL: photoURL, format: .jpeg, fileSize: Int64(testData.count)))
        
        // Перезапуск с параметром по умолчанию resumeLastSession: false
        let freshCoordinator = TransferCoordinator(storageManager: storage, database: db)
        try await freshCoordinator.bootstrapForLaunch(resumeLastSession: false)
        
        let active = await freshCoordinator.activeSession
        let assets = await freshCoordinator.assets
        let groups = await freshCoordinator.captureGroups
        let allSessions = await freshCoordinator.allSessions
        
        verify(active.id != prev.id, "При старте по умолчанию должна быть создана новая чистая сессия")
        verify(assets.isEmpty, "В новой сессии не должно быть старых файлов")
        verify(groups.isEmpty, "В новой сессии не должно быть групп кадров")
        verify(allSessions.contains { $0.id == prev.id }, "Предыдущая сессия сохранена в истории съемок")
        
        print("  ✓ Приложение корректно начинает работу с пустой сессии, сохраняя историю")
    }
    
    // MARK: - 3. Тест персистентности переключателя продолжения сессии в UserDefaults
    func testResumeLastSessionTogglePersistence() async throws {
        print("\n--- [3/9] Тест переключателя продолжения последней сессии ---")
        
        let defaults = UserDefaults.standard
        let prevVal = defaults.object(forKey: "nikon_resume_last_session")
        defer { defaults.setValue(prevVal, forKey: "nikon_resume_last_session") }
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        // Создаем AppState с изолированным координатором и тестовым портом
        let appState = AppState(port: 39121, coordinator: coordinator, resumeLastSessionOnLaunch: false)
        verify(appState.resumeLastSessionOnLaunch == false)
        verify(defaults.bool(forKey: "nikon_resume_last_session") == false)
        
        // Включаем переключатель
        appState.resumeLastSessionOnLaunch = true
        verify(defaults.bool(forKey: "nikon_resume_last_session") == true)
        
        // Выключаем обратно
        appState.resumeLastSessionOnLaunch = false
        verify(defaults.bool(forKey: "nikon_resume_last_session") == false)
        
        print("  ✓ Переключатель продолжения последней сессии сохраняется в UserDefaults")
    }
    
    // MARK: - 4. Тест: переключение между сессиями истории не удаляет и не перемещает файлы
    func testSessionSwitchPreservesOriginalFiles() async throws {
        print("\n--- [4/9] Тест сохранности оригиналов при переключении сессий ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        // Сессия А
        let sessionA = try await coordinator.startNewSession(named: "Session_Alpha")
        let photoA = sessionA.folderURL.appendingPathComponent("ALPHA_001.JPG")
        let bytesA = "AlphaOriginalBytes".data(using: .utf8)!
        try bytesA.write(to: photoA)
        await db.upsertAsset(MediaAsset(sessionID: sessionA.id, filename: "ALPHA_001.JPG", fileURL: photoA, format: .jpeg, fileSize: Int64(bytesA.count)))
        
        // Сессия Б
        let sessionB = try await coordinator.startNewSession(named: "Session_Beta")
        let photoB = sessionB.folderURL.appendingPathComponent("BETA_001.JPG")
        let bytesB = "BetaOriginalBytes".data(using: .utf8)!
        try bytesB.write(to: photoB)
        await db.upsertAsset(MediaAsset(sessionID: sessionB.id, filename: "BETA_001.JPG", fileURL: photoB, format: .jpeg, fileSize: Int64(bytesB.count)))
        
        // Переключаемся обратно на Сессию А
        let switchedA = await coordinator.switchActiveSession(to: sessionA.id)
        verify(switchedA?.id == sessionA.id, "Сессия А должна стать активной")
        
        // Проверяем, что файлы сессии А на диске в полной сохранности
        verify(FileManager.default.fileExists(atPath: photoA.path), "Файл Alpha должен существовать на диске")
        let readBytesA = try Data(contentsOf: photoA)
        verify(readBytesA == bytesA, "Содержимое файла Alpha не должно измениться")
        
        // Проверяем, что файлы сессии Б на диске НЕ тронуты и НЕ перемещены
        verify(FileManager.default.fileExists(atPath: photoB.path), "Файл Beta должен оставаться на месте")
        let readBytesB = try Data(contentsOf: photoB)
        verify(readBytesB == bytesB, "Содержимое файла Beta не должно измениться")
        
        // Переключаемся на Сессию Б
        let switchedB = await coordinator.switchActiveSession(to: sessionB.id)
        verify(switchedB?.id == sessionB.id, "Сессия Б должна стать активной")
        verify(FileManager.default.fileExists(atPath: photoA.path), "Файл Alpha сохранен")
        verify(FileManager.default.fileExists(atPath: photoB.path), "Файл Beta сохранен")
        
        print("  ✓ Открытие сессий из истории не удаляет и не перемещает оригинальные файлы на диске")
    }
    
    // MARK: - 5. Тест получения SessionStats: подсчет количества кадров и форматирование
    func testSessionStatsFramesCountAndFormatting() async throws {
        print("\n--- [5/9] Тест подсчета количества кадров и размера в SessionStats ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        let session = try await coordinator.startNewSession(named: "StatsTestSession")
        
        // Добавляем 2 кадра: RAW+JPEG (один кадр, 2 файла) и одиночный JPEG (один кадр, 1 файл)
        let nefURL = session.folderURL.appendingPathComponent("DSC_1001.NEF")
        let jpgURL = session.folderURL.appendingPathComponent("DSC_1001.JPG")
        let singleJpgURL = session.folderURL.appendingPathComponent("DSC_1002.JPG")
        
        try Data(repeating: 0x11, count: 20_000_000).write(to: nefURL)
        try Data(repeating: 0x22, count: 5_000_000).write(to: jpgURL)
        try Data(repeating: 0x33, count: 6_000_000).write(to: singleJpgURL)
        
        await db.upsertAsset(MediaAsset(sessionID: session.id, filename: "DSC_1001.NEF", fileURL: nefURL, format: .raw(fileExtension: "NEF"), fileSize: 20_000_000))
        await db.upsertAsset(MediaAsset(sessionID: session.id, filename: "DSC_1001.JPG", fileURL: jpgURL, format: .jpeg, fileSize: 5_000_000))
        await db.upsertAsset(MediaAsset(sessionID: session.id, filename: "DSC_1002.JPG", fileURL: singleJpgURL, format: .jpeg, fileSize: 6_000_000))
        
        let stats = await coordinator.getSessionStats(id: session.id)
        
        verify(stats.filesCount == 3, "Всего файлов должно быть 3")
        verify(stats.framesCount == 2, "Всего кадров должно быть 2 (RAW+JPEG считается за один кадр)")
        verify(stats.totalBytes == 31_000_000, "Общий объем должен составлять 31 МБ")
        verify(!stats.formattedSize.isEmpty, "Форматированный размер должен быть заполнен")
        
        print("  ✓ SessionStats корректно группирует кадры (2 кадра, 3 файла, \(stats.formattedSize))")
    }
    
    // MARK: - 6. Тест сохранения и чтения метаданных сессии
    func testSessionMetadataPersistence() async throws {
        print("\n--- [6/9] Тест сохранения и чтения метаданных сессии ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        let session = try await coordinator.startNewSession(named: "MetadataSession")
        
        await coordinator.updateSessionMetadata(
            id: session.id,
            author: "Алексей Смирнов",
            copyright: "© 2026 Алексей Смирнов",
            comment: "Студийная портретная съемка"
        )
        
        let loadedSession = await db.getSession(by: session.id)
        verify(loadedSession?.author == "Алексей Смирнов", "Автор должен сохраниться")
        verify(loadedSession?.copyright == "© 2026 Алексей Смирнов", "Копирайт должен сохраниться")
        verify(loadedSession?.comment == "Студийная портретная съемка", "Заметка должна сохраниться")
        
        print("  ✓ Метаданные сессии (Автор, Копирайт, Комментарий) успешно сохраняются в каталоге")
    }
    
    // MARK: - 7. Тест: очистка кэша миниатюр не затрагивает базу данных и оригиналы
    func testThumbnailCacheClearDoesNotAffectDiskFiles() async throws {
        print("\n--- [7/9] Тест изоляции очистки кэша миниатюр от файлов на диске ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        let session = try await coordinator.startNewSession(named: "CacheClearSession")
        let photoURL = session.folderURL.appendingPathComponent("DSC_SAFE.JPG")
        let fileContent = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try fileContent.write(to: photoURL)
        await db.upsertAsset(MediaAsset(sessionID: session.id, filename: "DSC_SAFE.JPG", fileURL: photoURL, format: .jpeg, fileSize: 4))
        
        // Заполняем кэш превью в оперативной памяти
        #if canImport(UIKit)
        let dummyImage = UIImage()
        PreviewMemoryCache.shared.setImage(dummyImage, forKey: photoURL.path)
        #elseif canImport(AppKit)
        let dummyImage = NSImage()
        PreviewMemoryCache.shared.setImage(dummyImage, forKey: photoURL.path)
        #endif
        
        // Очищаем кэш ОЗУ
        PreviewMemoryCache.shared.clear()
        
        // Проверяем, что файл на диске цел и невредим
        verify(FileManager.default.fileExists(atPath: photoURL.path), "Оригинал на диске не должен быть удален")
        let diskBytes = try Data(contentsOf: photoURL)
        verify(diskBytes == fileContent, "Содержимое файла на диске не должно измениться")
        
        // Проверяем, что запись в БД осталась
        let assets = await db.getAssets(for: session.id)
        verify(assets.count == 1, "Запись в каталоге SQLite должна остаться нетронутой")
        
        print("  ✓ Очистка кэша миниатюр освобождает только память и не затрагивает файлы на диске")
    }
    
    // MARK: - 8. Тест: пути файловой системы и статистика базы данных SQLite в Диагностике
    func testDiagnosticsStoragePathsAndSQLiteWALStats() async throws {
        print("\n--- [8/9] Тест путей файловой системы и статистики SQLite в диагностике ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        _ = try await coordinator.startNewSession(named: "DiagnosticsSession")
        
        // Проверяем базовый путь хранения
        let basePath = storage.baseStorageURL.path
        verify(!basePath.isEmpty, "Базовый путь хранения должен быть доступен")
        verify(FileManager.default.fileExists(atPath: basePath), "Папка хранения существует")
        
        // Проверяем статистику базы данных SQLite
        let dbStats = await coordinator.getDatabaseStats()
        verify(dbStats.schemaVersion >= 2, "Версия схемы должна быть v2 или выше")
        verify(dbStats.journalMode.uppercased() == "WAL", "SQLite должен работать в режиме WAL")
        verify(dbStats.totalSessions >= 1, "Число сессий в БД >= 1")
        verify(dbStats.fileSizeBytes > 0, "Размер файла базы данных больше нуля")
        
        print("  ✓ Диагностика корректно возвращает путь к диску и метрики SQLite (WAL, v\(dbStats.schemaVersion), \(dbStats.totalSessions) сессий)")
    }
    
    // MARK: - 9. Тест сверки каталога с диском
    func testCatalogReconciliationSafety() async throws {
        print("\n--- [9/9] Тест безопасной сверки каталога с диском ---")
        
        let storage = StorageManager(customBaseURL: tempBaseURL)
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        
        let session = try await coordinator.startNewSession(named: "ReconcileSession")
        
        // Подбрасываем новый неотслеженный файл прямо в папку сессии
        let unrecordedFile = session.folderURL.appendingPathComponent("DSC_RECONCILE.JPG")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: unrecordedFile)
        
        let (missing, recovered) = await coordinator.reconcileDiskCatalog()
        verify(recovered == 1, "Сверка должна обнаружить и восстановить 1 неотслеженный файл")
        verify(missing == 0, "Отсутствующих файлов быть не должно")
        
        let assets = await coordinator.assets
        verify(assets.contains { $0.filename == "DSC_RECONCILE.JPG" }, "Восстановленный файл должен появиться в ассетах")
        
        print("  ✓ Сверка каталога восстановила неотслеженный файл без сбоев")
    }
}
