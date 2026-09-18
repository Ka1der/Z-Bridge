import Foundation
import Combine
import CommonCrypto

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct Stage12VerificationMain {
    static func main() async throws {
        print("=== СТАРТ ТЕСТОВ ЭТАПА 12: XMP И МЕТАДАННЫЕ СЕССИИ ===")
        
        let suite = Stage12VerificationSuite()
        try await suite.runAllTests()
        
        print("\n=== ВСЕ ТЕСТЫ ЭТАПА 12 УСПЕШНО ПРОЙДЕНЫ! ===")
    }
}

@MainActor
final class Stage12VerificationSuite {
    let tempDir: URL
    let fileManager = FileManager.default
    
    init() {
        let baseDir = fileManager.temporaryDirectory.appendingPathComponent("Stage12Test_\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.tempDir = baseDir
    }
    
    func runAllTests() async throws {
        try await testXMLSidecarGenerationAndNamespaces()
        try await testRatingsAndFlagsExport()
        try await testSessionMetadataInXMP()
        try await testSidecarNamingConventions()
        try await testStrictRAWOriginalImmutability()
        try await testTargetEditorsCompatibilityMatrixAndNonPortableDocumentation()
        try await testSessionManifestAndMarkdownReportGeneration()
        try await testExportManagerEndToEndBatchExportWithXMPAndManifest()
        try await testCatalogDatabaseSessionMetadataMigrationV3()
    }
    
    // MARK: - Вспомогательные методы
    
    private func computeSHA256(for fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func createDummyRAWAsset(name: String, rating: Int = 0, pickStatus: PickStatus = .unflagged) -> MediaAsset {
        let fileURL = tempDir.appendingPathComponent("\(name).NEF")
        // Создаем псевдо-RAW файл
        var rawData = Data([0x4D, 0x4D, 0x00, 0x2A]) // TIFF / NEF header
        rawData.append(Data(repeating: 0xAA, count: 4096))
        try? rawData.write(to: fileURL)
        
        let metadata = AssetMetadata(
            cameraModel: "NIKON Z8",
            lensModel: "NIKKOR Z 50mm f/1.2 S",
            exposureTime: 0.005, // 1/200s
            fNumber: 1.8,
            iso: 400,
            focalLength: 50.0
        )
        
        return MediaAsset(
            sessionID: UUID(),
            filename: "\(name).NEF",
            fileURL: fileURL,
            format: .raw(fileExtension: "nef"),
            fileSize: Int64(rawData.count),
            metadata: metadata,
            rating: rating,
            pickStatus: pickStatus
        )
    }
    
    // MARK: - 1. Структура XML XMP и стандартные пространства имен Adobe
    
    func testXMLSidecarGenerationAndNamespaces() async throws {
        print("\n[1/9] Тест генерации XMP XML и пространств имен Adobe...")
        
        let asset = createDummyRAWAsset(name: "DSC_0010", rating: 4, pickStatus: .picked)
        let sessionMeta = SessionMetadata(
            sessionName: "Lookbook Autumn",
            author: "Alex Morgan",
            copyright: "© 2026 Alex Morgan Studio",
            comment: "Editorial shoot with Nikon Z8"
        )
        
        let xml = XMPGenerator.generateXMP(for: asset, sessionMetadata: sessionMeta)
        
        assert(xml.contains("<?xpacket begin=") && xml.contains("id=\"W5M0MpCehiHzreSzNTczkc9d\""), "Заголовок xpacket отсутствует")
        assert(xml.contains("<?xpacket end=\"w\"?>"), "Завершающий тег xpacket отсутствует")
        assert(xml.contains("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\""), "adobe:ns:meta/ пространство имен отсутствует")
        assert(xml.contains("xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\""), "RDF пространство имен отсутствует")
        assert(xml.contains("xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\""), "XMP пространство имен отсутствует")
        assert(xml.contains("xmlns:photoshop=\"http://ns.adobe.com/photoshop/1.0/\""), "Photoshop пространство имен отсутствует")
        assert(xml.contains("xmlns:dc=\"http://purl.org/dc/elements/1.1/\""), "Dublin Core пространство имен отсутствует")
        assert(xml.contains("xmlns:tiff=\"http://ns.adobe.com/tiff/1.0/\""), "TIFF пространство имен отсутствует")
        assert(xml.contains("xmlns:exif=\"http://ns.adobe.com/exif/1.0/\""), "EXIF пространство имен отсутствует")
        assert(xml.contains("xmlns:xmpRights=\"http://ns.adobe.com/xap/1.0/rights/\""), "xmpRights пространство имен отсутствует")
        
        print("✓ Валидация структуры XML и стандартных пространств имен Adobe пройдена.")
    }
    
    // MARK: - 2. Экспорт рейтингов (0–5★) и отметок Pick/Reject
    
    func testRatingsAndFlagsExport() async throws {
        print("\n[2/9] Тест экспорта рейтингов и флагов Pick / Reject...")
        
        // Кадр 1: 5 звезд, Pick
        let pickAsset = createDummyRAWAsset(name: "SHOT_PICK", rating: 5, pickStatus: .picked)
        let pickXML = XMPGenerator.generateXMP(for: pickAsset)
        assert(pickXML.contains("xmp:Rating=\"5\""), "5-звездочный рейтинг не найден в XMP")
        assert(pickXML.contains("xmp:Label=\"Pick\""), "xmp:Label='Pick' отсутствует")
        assert(pickXML.contains("photoshop:Urgency=\"1\""), "photoshop:Urgency='1' отсутствует")
        
        // Кадр 2: 0 звезд, Reject
        let rejectAsset = createDummyRAWAsset(name: "SHOT_REJECT", rating: 0, pickStatus: .rejected)
        let rejectXML = XMPGenerator.generateXMP(for: rejectAsset)
        assert(pickXML.contains("xmp:Rating=\"5\""), "5-звездочный рейтинг не найден в XMP")
        assert(rejectXML.contains("xmp:Rating=\"-1\""), "Отклонённый кадр должен иметь xmp:Rating='-1' для ACR/darktable")
        assert(rejectXML.contains("xmp:Label=\"Reject\""), "xmp:Label='Reject' отсутствует")
        assert(!rejectXML.contains("photoshop:Urgency=\"1\""), "photoshop:Urgency='1' не должен присутствовать на Rejected")
        
        // Кадр 3: 3 звезды, Unflagged
        let unflaggedAsset = createDummyRAWAsset(name: "SHOT_UNFLAGGED", rating: 3, pickStatus: .unflagged)
        let unflaggedXML = XMPGenerator.generateXMP(for: unflaggedAsset)
        assert(unflaggedXML.contains("xmp:Rating=\"3\""), "3-звездочный рейтинг не найден")
        assert(!unflaggedXML.contains("xmp:Label=\"Pick\""), "Unflagged не должен иметь метку Pick")
        assert(!unflaggedXML.contains("xmp:Label=\"Reject\""), "Unflagged не должен иметь метку Reject")
        
        print("✓ Экспорт рейтингов (0–5★, -1 для Reject) и меток Pick/Reject работает корректно.")
    }
    
    // MARK: - 3. Авторские метаданные сессии и экранирование спецсимволов
    
    func testSessionMetadataInXMP() async throws {
        print("\n[3/9] Тест записи авторских метаданных и экранирования XML...")
        
        let asset = createDummyRAWAsset(name: "SHOT_META")
        let sessionMeta = SessionMetadata(
            sessionName: "Brand <Shoot> & Co \"Luxury\"",
            author: "Ivan & Maria",
            copyright: "© 2026 Ivan & Maria",
            comment: "Studio light: key 45° & rim light"
        )
        
        let xml = XMPGenerator.generateXMP(for: asset, sessionMetadata: sessionMeta)
        
        // Проверка экранирования XML (& -> &amp;, < -> &lt;, > -> &gt;)
        assert(xml.contains("Ivan &amp; Maria"), "Символ & должен быть экранирован в dc:creator")
        assert(xml.contains("Brand &lt;Shoot&gt; &amp; Co &quot;Luxury&quot;"), "Спецсимволы должны быть экранированы в названии")
        assert(xml.contains("<dc:creator>"), "Тег dc:creator отсутствует")
        assert(xml.contains("<dc:rights>"), "Тег dc:rights отсутствует")
        assert(xml.contains("<dc:description>"), "Тег dc:description отсутствует")
        assert(xml.contains("<xmpRights:Marked>True</xmpRights:Marked>"), "xmpRights:Marked должен быть True при наличии копирайта")
        
        print("✓ Авторские метаданные сессии и XML-экранирование валидны.")
    }
    
    // MARK: - 4. Соглашения об именовании сопутствующих файлов
    
    func testSidecarNamingConventions() async throws {
        print("\n[4/9] Тест соглашений об именовании XMP sidecar (.standardBasename vs .fullFilename)...")
        
        let baseNameConvention = XMPSidecarNamingConvention.standardBasename
        let fullFilenameConvention = XMPSidecarNamingConvention.fullFilename
        
        // 1. RAW файл: DSC_0001.NEF
        let rawStandard = XMPGenerator.sidecarFilename(for: "DSC_0001.NEF", convention: baseNameConvention)
        let rawFull = XMPGenerator.sidecarFilename(for: "DSC_0001.NEF", convention: fullFilenameConvention)
        assert(rawStandard == "DSC_0001.xmp", "Ожидалось DSC_0001.xmp, получено \(rawStandard)")
        assert(rawFull == "DSC_0001.NEF.xmp", "Ожидалось DSC_0001.NEF.xmp, получено \(rawFull)")
        
        // 2. JPEG файл: DSC_0001.JPG
        let jpgStandard = XMPGenerator.sidecarFilename(for: "DSC_0001.JPG", convention: baseNameConvention)
        let jpgFull = XMPGenerator.sidecarFilename(for: "DSC_0001.JPG", convention: fullFilenameConvention)
        assert(jpgStandard == "DSC_0001.xmp", "Ожидалось DSC_0001.xmp, получено \(jpgStandard)")
        assert(jpgFull == "DSC_0001.JPG.xmp", "Ожидалось DSC_0001.JPG.xmp, получено \(jpgFull)")
        
        // 3. Запись файла sidecar на диск
        let asset = createDummyRAWAsset(name: "DSC_TEST_WRITE")
        let destinationFolder = tempDir.appendingPathComponent("SidecarTestFolder", isDirectory: true)
        try? fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        
        let writtenURL = try XMPGenerator.writeSidecar(for: asset, to: destinationFolder, convention: .standardBasename)
        assert(fileManager.fileExists(atPath: writtenURL.path), "Sidecar файл не найден на диске")
        assert(writtenURL.lastPathComponent == "DSC_TEST_WRITE.xmp", "Неверное имя созданного файла sidecar")
        
        print("✓ Соглашения об именовании XMP sidecar работают безукоризненно.")
    }
    
    // MARK: - 5. Строгая неизменность RAW-оригиналов (SHA-256)
    
    func testStrictRAWOriginalImmutability() async throws {
        print("\n[5/9] Тест строгой неизменности RAW-оригиналов (побайтовая проверка SHA-256)...")
        
        let rawAsset = createDummyRAWAsset(name: "IMMUTABLE_SHOT", rating: 5, pickStatus: .picked)
        let originalPath = rawAsset.fileURL
        
        // Фиксируем контрольную сумму SHA-256 исходного RAW-оригинала
        guard let hashBefore = computeSHA256(for: originalPath) else {
            fatalError("Не удалось вычислить SHA-256 до экспорта")
        }
        
        let attrsBefore = try fileManager.attributesOfItem(atPath: originalPath.path)
        let modDateBefore = attrsBefore[.modificationDate] as? Date
        
        // Выполняем генерацию XMP sidecar в ту же папку, где лежит оригинал
        let sidecarURL = try XMPGenerator.writeSidecar(
            for: rawAsset,
            to: originalPath.deletingLastPathComponent(),
            convention: .standardBasename,
            sessionMetadata: SessionMetadata(sessionName: "Test", author: "Photographer")
        )
        
        // Выполняем экспорт через ExportManager
        let exportTarget = tempDir.appendingPathComponent("ImmutableExportTarget", isDirectory: true)
        try? fileManager.createDirectory(at: exportTarget, withIntermediateDirectories: true)
        
        let job = ExportJob(
            items: [ExportItem(asset: rawAsset)],
            destination: .directory(url: exportTarget),
            includeXMPSidecars: true
        )
        _ = await ExportManager.shared.executeJob(job)
        
        // Проверяем SHA-256 исходного RAW-оригинала ПОСЛЕ всех операций
        guard let hashAfter = computeSHA256(for: originalPath) else {
            fatalError("Не удалось вычислить SHA-256 после экспорта")
        }
        
        let attrsAfter = try fileManager.attributesOfItem(atPath: originalPath.path)
        let modDateAfter = attrsAfter[.modificationDate] as? Date
        
        assert(hashBefore == hashAfter, "КРИТИЧЕСКАЯ ОШИБКА: RAW-оригинал был модифицирован! Хеши не совпадают!")
        assert(modDateBefore == modDateAfter, "Дата модификации исходного RAW-файла изменилась!")
        assert(fileManager.fileExists(atPath: sidecarURL.path), "Sidecar файл должен быть создан рядом с оригиналом")
        
        print("✓ RAW-оригинал остался на 100% нетронутым (SHA-256 идентичен байт-в-байт: \(hashBefore.prefix(12))...).")
    }
    
    // MARK: - 6. Матрица совместимости с редакторами и документация непереносимых отметок
    
    func testTargetEditorsCompatibilityMatrixAndNonPortableDocumentation() async throws {
        print("\n[6/9] Тест матрицы совместимости с редакторами и документации непереносимых меток...")
        
        let editors = XMPCompatibilityGuide.allEditors
        assert(editors.count >= 8, "В матрице должно быть представлено не менее 8 целевых редакторов")
        
        let targets = Set(editors.map { $0.target })
        assert(targets.contains(.lightroomClassic), "Adobe Lightroom Classic отсутствует в матрице")
        assert(targets.contains(.adobeCameraRaw), "Adobe Camera Raw отсутствует в матрице")
        assert(targets.contains(.adobeBridge), "Adobe Bridge отсутствует в матрице")
        assert(targets.contains(.captureOne), "Capture One Pro отсутствует в матрице")
        assert(targets.contains(.photoMechanic), "Photo Mechanic отсутствует в матрице")
        assert(targets.contains(.darktable), "darktable отсутствует в матрице")
        assert(targets.contains(.rawTherapee), "RawTherapee отсутствует в матрице")
        assert(targets.contains(.applePhotos), "Apple Photos отсутствует в матрице")
        
        // Проверка документирования ограничения Lightroom Pick:
        let lrInfo = editors.first { $0.target == .lightroomClassic }!
        assert(lrInfo.pickNotes.contains(".lrcat") || lrInfo.pickNotes.contains("каталог"), "Lightroom Pick должен быть документирован как catalog-only")
        assert(lrInfo.pickNotes.contains("Label=\"Pick\"") || lrInfo.pickNotes.contains("Pick"), "Должно быть указано использование xmp:Label='Pick'")
        
        // Проверка непереносимых тегов
        let nonPortable = XMPCompatibilityGuide.nonPortableTags
        assert(!nonPortable.isEmpty, "Словарь непереносимых отметок не должен быть пустым")
        assert(nonPortable.keys.contains("Pick / Flag (Lightroom Classic)"), "Ограничение Pick в Lightroom не задокументировано в nonPortableTags")
        
        print("✓ Матрица совместимости и документация специфики редакторов полностью проверены.")
    }
    
    // MARK: - 7. Генерация манифеста сессии (JSON) и Markdown-отчёта
    
    func testSessionManifestAndMarkdownReportGeneration() async throws {
        print("\n[7/9] Тест манифеста фотосессии (session_manifest.json) и отчета (session_report.md)...")
        
        let sessionMeta = SessionMetadata(
            sessionName: "Vogue Cover Shoot",
            author: "Elena Rostova",
            copyright: "© 2026 Elena Studio",
            comment: "Studio daylight series",
            clientName: "Condé Nast"
        )
        
        let files: [SessionManifestFileEntry] = [
            SessionManifestFileEntry(
                filename: "DSC_0001.NEF",
                format: "NEF",
                fileSize: 45_000_000,
                rating: 5,
                pickStatus: "Отобран",
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                cameraModel: "NIKON Z8",
                lensModel: "NIKKOR Z 50mm f/1.2 S",
                exposureSummary: "1/250  f/1.4  ISO 200",
                exportStatus: "Успешно"
            ),
            SessionManifestFileEntry(
                filename: "DSC_0001.JPG",
                format: "JPG",
                fileSize: 12_000_000,
                rating: 5,
                pickStatus: "Отобран",
                cameraModel: "NIKON Z8",
                lensModel: "NIKKOR Z 50mm f/1.2 S",
                exposureSummary: "1/250  f/1.4  ISO 200",
                exportStatus: "Успешно"
            ),
            SessionManifestFileEntry(
                filename: "DSC_0002.NEF",
                format: "NEF",
                fileSize: 44_500_000,
                rating: 0,
                pickStatus: "Отклонён",
                cameraModel: "NIKON Z8",
                lensModel: "NIKKOR Z 50mm f/1.2 S",
                exposureSummary: "1/250  f/1.4  ISO 200",
                exportStatus: "Успешно"
            )
        ]
        
        let manifest = SessionManifest(
            session: sessionMeta,
            files: files,
            averageTransferSpeedMBs: 145.0
        )
        
        // 1. Проверка статистики
        assert(manifest.statistics.totalFiles == 3, "totalFiles должно быть 3")
        assert(manifest.statistics.rawCount == 2, "rawCount должно быть 2")
        assert(manifest.statistics.jpegCount == 1, "jpegCount должно быть 1")
        assert(manifest.statistics.pickedCount == 2, "pickedCount должно быть 2")
        assert(manifest.statistics.rejectedCount == 1, "rejectedCount должно быть 1")
        assert(manifest.statistics.ratedCounts[5] == 2, "Кадров с рейтингом 5★ должно быть 2")
        
        // 2. Сериализация и десериализация JSON
        let jsonData = try manifest.generateJSON()
        assert(!jsonData.isEmpty, "JSON манифеста не должен быть пустым")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionManifest.self, from: jsonData)
        assert(decoded.session.sessionName == "Vogue Cover Shoot", "Декодированное имя сессии не совпадает")
        assert(decoded.session.author == "Elena Rostova", "Декодированный автор не совпадает")
        assert(decoded.files.count == 3, "Количество файлов в декодированном JSON не совпадает")
        
        // 3. Генерация Markdown-отчета
        let report = manifest.generateMarkdownReport()
        assert(report.contains("# Отчёт фотосессии: Vogue Cover Shoot"), "Заголовок отчета отсутствует")
        assert(report.contains("Elena Rostova"), "Автор отсутствует в Markdown отчете")
        assert(report.contains("Condé Nast"), "Клиент отсутствует в отчете")
        assert(report.contains("| Всего файлов | 3 |"), "Сводная статистика отсутствует в отчете")
        assert(report.contains("DSC_0001.NEF"), "Таблица файлов отсутствует в отчете")
        
        print("✓ Манифест JSON и отчет Markdown сгенерированы и проверены.")
    }
    
    // MARK: - 8. Комплексный пакетный экспорт с XMP и манифестом через ExportManager
    
    func testExportManagerEndToEndBatchExportWithXMPAndManifest() async throws {
        print("\n[8/9] Тест сквозного пакетного экспорта с генерацией XMP и манифеста...")
        
        let targetFolder = tempDir.appendingPathComponent("EndToEndExportFolder", isDirectory: true)
        try? fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        
        let raw1 = createDummyRAWAsset(name: "E2E_001", rating: 5, pickStatus: .picked)
        let raw2 = createDummyRAWAsset(name: "E2E_002", rating: 2, pickStatus: .unflagged)
        
        let sessionMeta = SessionMetadata(
            sessionName: "Commercial Studio Set",
            author: "Master Chief",
            copyright: "© 2026 Halo Media",
            comment: "Campaign hero shots"
        )
        
        let items = [ExportItem(asset: raw1), ExportItem(asset: raw2)]
        let job = ExportJob(
            items: items,
            destination: .directory(url: targetFolder),
            formatSelection: .rawOnly,
            includeXMPSidecars: true,
            sidecarNamingConvention: .standardBasename,
            includeSessionManifest: true,
            sessionMetadata: sessionMeta
        )
        
        let executedJob = await ExportManager.shared.executeJob(job)
        
        guard let result = executedJob.result else {
            fatalError("Результат экспорта отсутствует")
        }
        
        assert(result.successCount == 2, "Все 2 файла должны быть успешно экспортированы")
        assert(result.failedCount == 0, "Ошибок экспорта быть не должно")
        assert(result.exportedXMPURLs.count == 2, "Должно быть создано 2 XMP sidecar файла")
        
        // Проверяем наличие XMP на диске
        for xmpURL in result.exportedXMPURLs {
            assert(fileManager.fileExists(atPath: xmpURL.path), "XMP sidecar отсутствует на диске: \(xmpURL.path)")
            let content = try String(contentsOf: xmpURL, encoding: .utf8)
            assert(content.contains("Master Chief"), "Автор должен быть записан в экспортированном XMP")
        }
        
        // Проверяем наличие manifest и report
        guard let manifestURL = result.manifestURL, let reportURL = result.reportURL else {
            fatalError("URL манифеста или отчета отсутствует в результате экспорта")
        }
        
        assert(fileManager.fileExists(atPath: manifestURL.path), "session_manifest.json отсутствует на диске")
        assert(fileManager.fileExists(atPath: reportURL.path), "session_report.md отсутствует на диске")
        
        let manifestData = try Data(contentsOf: manifestURL)
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        let readManifest = try jsonDecoder.decode(SessionManifest.self, from: manifestData)
        assert(readManifest.session.sessionName == "Commercial Studio Set", "Имя сессии в манифесте не совпадает")
        assert(readManifest.statistics.pickedCount == 1, "В экспортированной сессии должен быть 1 отобранный кадр")
        
        let reportText = try String(contentsOf: reportURL, encoding: .utf8)
        assert(reportText.contains("Campaign hero shots"), "Комментарий к сессии должен присутствовать в отчете")
        
        print("✓ Сквозной пакетный экспорт с XMP sidecars и манифестом сессии успешно выполнен.")
    }
    
    // MARK: - 9. Миграция базы данных v3 и сохранение метаданных сессии
    
    func testCatalogDatabaseSessionMetadataMigrationV3() async throws {
        print("\n[9/9] Тест миграции базы данных v3 и сохранения метаданных сессии...")
        
        let dbURL = tempDir.appendingPathComponent("test_catalog_v3.sqlite")
        let db = CatalogDatabase(customDatabaseURL: dbURL)
        
        let sessionID = UUID()
        let sessionFolder = tempDir.appendingPathComponent("SessionV3Folder", isDirectory: true)
        try? fileManager.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        
        let initialSession = CaptureSession(
            id: sessionID,
            name: "Automotive Portfolio",
            folderURL: sessionFolder,
            author: "Dmitry Auto",
            copyright: "© 2026 Speed Magazine",
            comment: "Track testing day"
        )
        
        // Вставка сессии в БД
        await db.upsertSession(initialSession)
        
        // Считывание сессии из БД
        let allSessions = await db.getAllSessions()
        let loaded = allSessions.first { $0.id == sessionID }
        assert(loaded != nil, "Сессия не найдена в базе данных")
        assert(loaded?.author == "Dmitry Auto", "Автор сессии не совпадает с сохраненным в БД")
        assert(loaded?.copyright == "© 2026 Speed Magazine", "Копирайт сессии не совпадает с сохраненным в БД")
        assert(loaded?.comment == "Track testing day", "Комментарий сессии не совпадает с сохраненным в БД")
        
        // Обновление метаданных через updateSessionMetadata
        await db.updateSessionMetadata(
            id: sessionID,
            author: "Dmitry Updated",
            copyright: "© 2026 Updated Rights",
            comment: "Post-production complete"
        )
        
        let reloadedSessions = await db.getAllSessions()
        let updated = reloadedSessions.first { $0.id == sessionID }
        assert(updated?.author == "Dmitry Updated", "Обновленный автор сессии не совпадает")
        assert(updated?.copyright == "© 2026 Updated Rights", "Обновленный копирайт не совпадает")
        assert(updated?.comment == "Post-production complete", "Обновленный комментарий не совпадает")
        
        print("✓ Миграция v3 и сохранение метаданных сессии в базе данных работают корректно.")
    }
}
