import Foundation

@main
struct InlineImportNavigationVerificationTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = TransferCoordinator(
            storageManager: StorageManager(customBaseURL: root),
            database: CatalogDatabase(customDatabaseURL: root.appendingPathComponent("catalog.sqlite")))
        let state = AppState(port: 39312, coordinator: coordinator, resumeLastSessionOnLaunch: true)
        await state.waitUntilReady()
        let sessionID = state.currentSession?.id
        state.selectedSection = .camera
        state.viewMode = .viewer
        state.isUserInspecting = true
        state.selectedCameraFileIDs = ["camera-file"]
        state.handleMainScreenAction(.selectCardFiles)
        assert(state.selectedSection == .photos)
        assert(state.photoSource == .camera)
        assert(!state.isUserInspecting)
        assert(state.currentSession?.id == sessionID)
        state.photoSource = .session
        assert(state.selectedCameraFileIDs == ["camera-file"])
        state.selectedSection = .sessions
        state.isUSBBrowserPresented = true
        assert(state.selectedSection == .photos && state.photoSource == .camera)
        assert(state.selectedCameraFileIDs == ["camera-file"])
        print("PASS: inline import routing, target session and selection preservation")
    }
}
