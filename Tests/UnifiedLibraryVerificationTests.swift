import Foundation

@main
struct UnifiedLibraryVerificationTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = StorageManager(customBaseURL: root)
        let db = CatalogDatabase(customDatabaseURL: root.appendingPathComponent("db.sqlite"))
        let source = CameraSource(id: "camera", model: "Nikon", transportType: .usb)
        var bytes = Data([0x49,0x49,0x2a,0]); bytes.append(Data(repeating: 0x20, count: 1020))
        var oldIDs: [UUID] = []
        for name in ["Shoot_A", "Shoot_B"] {
            let folder = storage.baseStorageURL.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let session = CaptureSession(name: name, folderURL: folder)
            await db.upsertSession(session)
            let file = folder.appendingPathComponent("DSC_0001.NEF")
            try bytes.write(to: file)
            let asset = MediaAsset(sessionID: session.id, filename: file.lastPathComponent, fileURL: file, format: .raw(fileExtension: "nef"), fileSize: 1024, rating: 4)
            oldIDs.append(asset.id)
            await db.upsertAsset(asset)
            let job = TransferJob(source: source, sourceFileID: name, destinationURL: file, sessionID: session.id, state: .completed(assetID: asset.id))
            await db.upsertJob(job)
        }
        // Simulate termination after moving a directory but before updating SQLite.
        let downloads = root.appendingPathComponent("Downloads")
        let migratedID = UUID().uuidString
        let movedFolder = downloads.appendingPathComponent("Imported").appendingPathComponent(migratedID)
        try FileManager.default.createDirectory(at: movedFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(["Shoot_A": migratedID]).write(to: downloads.appendingPathComponent(".legacy-migration.json"))
        try FileManager.default.moveItem(at: storage.baseStorageURL.appendingPathComponent("Shoot_A"), to: movedFolder)
        let coordinator = TransferCoordinator(storageManager: storage, database: db)
        try await coordinator.bootstrapLibrary()
        let imported = await coordinator.assets
        assert(imported.count == 2 && Set(imported.map(\.id)) == Set(oldIDs))
        assert(Set(imported.map(\.fileURL)).count == 2)
        for asset in imported {
            assert(asset.rating == 4)
            assert(asset.fileURL.path.hasPrefix(coordinator.libraryDirectory.path + "/"))
            let actual = try Data(contentsOf: asset.fileURL); assert(actual == bytes)
        }
        let historical = await db.getAllSessions()
        assert(historical.count == 2, "No new session rows")
        let sourceIDs = await coordinator.getImportedSourceFileIDs()
        assert(sourceIDs == ["Shoot_A", "Shoot_B"])
        let job = try await coordinator.createTransferJob(source: source, filename: "NEW.NEF", sourceFileID: "new", expectedSize: 1024)
        assert(job.destinationURL.deletingLastPathComponent() == coordinator.libraryDirectory)
        try bytes.write(to: job.stagingURL!)
        let asset = try await coordinator.finalizeTransfer(jobID: job.id, actualSize: 1024, duration: 1)
        assert(asset.fileURL == job.destinationURL)
        let count = await db.getAllAssets().count
        assert(count == 3)
        let restarted = TransferCoordinator(storageManager: storage, database: db)
        try await restarted.bootstrapLibrary()
        let all = await restarted.assets
        assert(all.count == 3)
        let ids = await restarted.getImportedSourceFileIDs()
        assert(ids.contains("new"))
        let sessionRows = await db.getAllSessions(); assert(sessionRows.count == 2)
        do { _ = try await restarted.startNewSession(); assertionFailure("Session creation must be blocked") } catch {}
        let retry = try await restarted.prepareJobForRetry(jobID: job.id)
        assert(retry.stagingURL != nil && retry.stagingURL != asset.fileURL)
        let originalBytes = try Data(contentsOf: asset.fileURL); assert(originalBytes == bytes)
        // Clean installation: no hidden session row is needed to save an asset.
        let clean = root.appendingPathComponent("clean")
        try FileManager.default.createDirectory(at: clean, withIntermediateDirectories: true)
        let cleanDB = CatalogDatabase(customDatabaseURL: clean.appendingPathComponent("db.sqlite"))
        let cleanCoordinator = TransferCoordinator(storageManager: StorageManager(customBaseURL: clean), database: cleanDB)
        try await cleanCoordinator.bootstrapLibrary()
        let cleanJob = try await cleanCoordinator.createTransferJob(source: source, filename: "FIRST.NEF", expectedSize: 1024)
        try bytes.write(to: cleanJob.stagingURL!)
        _ = try await cleanCoordinator.finalizeTransfer(jobID: cleanJob.id, actualSize: 1024, duration: 1)
        let cleanAssets = await cleanDB.getAllAssets(); let cleanSessions = await cleanDB.getAllSessions()
        assert(cleanAssets.count == 1 && cleanSessions.isEmpty)
        print("PASS: legacy collision migration, ratings, restart, global dedup, new imports without sessions, safe retry")
    }
    static func awaitValue(_ value: Int) -> Int { value }
}
