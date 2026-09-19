import Foundation

@main
struct StartupSessionVerificationTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = CatalogDatabase(customDatabaseURL: root.appendingPathComponent("catalog.sqlite"))
        let storage = StorageManager(customBaseURL: root)
        let original = TransferCoordinator(storageManager: storage, database: db)
        await original.bootstrap()
        let previous = await original.activeSession
        let photo = previous.folderURL.appendingPathComponent("DSC_0001.JPG")
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        try bytes.write(to: photo)
        await db.upsertAsset(MediaAsset(sessionID: previous.id, filename: photo.lastPathComponent,
                                       fileURL: photo, format: .jpeg, fileSize: 4))

        let resumed = TransferCoordinator(storageManager: storage, database: db)
        try await resumed.bootstrapForLaunch(resumeLastSession: true)
        let resumedID = await resumed.activeSession.id
        let resumedAssets = await resumed.assets
        assert(resumedID == previous.id && resumedAssets.count == 1)

        let fresh = TransferCoordinator(storageManager: storage, database: db)
        try await fresh.bootstrapForLaunch(resumeLastSession: false)
        let freshSession = await fresh.activeSession
        let freshAssets = await fresh.assets
        let freshGroups = await fresh.captureGroups
        let history = await fresh.allSessions
        assert(freshSession.id != previous.id && freshSession.folderURL != previous.folderURL)
        assert(freshAssets.isEmpty && freshGroups.isEmpty)
        assert(history.contains { $0.id == previous.id })
        let preserved = try Data(contentsOf: photo)
        assert(preserved == bytes)
        _ = await fresh.switchActiveSession(to: previous.id)
        let historicAssets = await fresh.assets
        assert(historicAssets.count == 1 && historicAssets[0].fileURL == photo)
        _ = await fresh.switchActiveSession(to: freshSession.id)

        let emptyRestart = TransferCoordinator(storageManager: storage, database: db)
        try await emptyRestart.bootstrapForLaunch(resumeLastSession: false)
        let reusedID = await emptyRestart.activeSession.id
        assert(reusedID == freshSession.id, "Empty sessions should be reused")
        await emptyRestart.closeSession(id: reusedID)
        let closedRestart = TransferCoordinator(storageManager: storage, database: db)
        try await closedRestart.bootstrapForLaunch(resumeLastSession: false)
        let newID = await closedRestart.activeSession.id
        assert(newID != reusedID, "Closed sessions should not be reused")
        print("PASS: fresh launch, resume, history preservation, empty reuse, closed session")
    }
}
