import Foundation

@main
struct TransferOnlyModeVerificationTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = TransferCoordinator(storageManager: StorageManager(customBaseURL: root), database: CatalogDatabase(customDatabaseURL: root.appendingPathComponent("catalog.sqlite")))
        await coordinator.bootstrap()
        let original = await coordinator.activeSession
        let file = original.folderURL.appendingPathComponent("test.JPG")
        try Data([0xff, 0xd8, 0xff, 0xe0]).write(to: file)
        let state = AppState(port: 39313, coordinator: coordinator, resumeLastSessionOnLaunch: false)
        await state.waitUntilReady()
        assert(!AppSection.visibleCases.contains(.sessions))
        assert(!SettingsTab.visibleCases.contains(.sessions))
        assert(state.currentSession == nil)
        assert(state.receivedFiles.count == 1)
        state.selectedSection = .sessions
        assert(state.selectedSection == .photos)
        state.isShowingSessionSheet = true
        assert(!state.isShowingSessionSheet)
        state.startNewSession(named: "Forbidden")
        state.renameSession(id: original.id, newName: "Forbidden")
        state.closeSession(id: original.id)
        var deletionBlocked = false
        state.deleteSession(id: original.id) { deletionBlocked = $0 != nil }
        assert(deletionBlocked)
        let sessions = await coordinator.allSessions
        assert(sessions.isEmpty)
        let assets = await coordinator.assets
        assert(assets.count == 1 && FileManager.default.fileExists(atPath: assets[0].fileURL.path))
        state.isUSBBrowserPresented = true
        assert(state.photoSource == .camera && state.selectedSection == .photos)
        print("PASS: sessions hidden and blocked, originals preserved, startup and import available")
    }
}
