import SwiftUI

@main
struct VoxLogApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("VoxLog", systemImage: appState.statusIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var serverRunning = false
    @Published var environment: VoxEnvironment = .home
    @Published var totalRecordings: Int = 0

    let processManager = ProcessManager()
    let audioRecorder = AudioRecorder()
    let coreBridge = CoreBridge()
    let pasteManager = PasteManager()
    let hotkeyManager = HotkeyManager()

    var statusIcon: String {
        if isRecording { return "mic.fill" }
        if isProcessing { return "ellipsis.circle" }
        if lastError != nil { return "exclamationmark.triangle.fill" }
        if serverRunning { return "waveform" }
        return "waveform.slash"
    }

    func start() async {
        // Start Python server
        do {
            try await processManager.startServer()
            serverRunning = true

            // Wait for server to be ready
            try await coreBridge.waitForHealth(maxRetries: 10, delayMs: 500)

            // Set up hotkey callback
            hotkeyManager.onRecordStart = { [weak self] in
                Task { @MainActor in
                    self?.startRecording()
                }
            }
            hotkeyManager.onRecordStop = { [weak self] in
                Task { @MainActor in
                    await self?.stopRecordingAndProcess()
                }
            }
            hotkeyManager.register()

            lastError = nil
        } catch {
            lastError = "Failed to start: \(error.localizedDescription)"
            serverRunning = false
        }
    }

    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        do {
            try audioRecorder.start()
            isRecording = true
            lastError = nil
        } catch {
            lastError = "Recording failed: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndProcess() async {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        do {
            let audioData = try audioRecorder.stop()
            let result = try await coreBridge.voice(
                audio: audioData,
                env: environment,
                targetApp: NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            )
            pasteManager.pasteText(result.polishedText)
            totalRecordings += 1
            lastError = nil
        } catch {
            lastError = "Processing failed: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func stop() {
        hotkeyManager.unregister()
        audioRecorder.stopIfNeeded()
        processManager.stopServer()
        serverRunning = false
    }
}

enum VoxEnvironment: String, CaseIterable {
    case home = "home"
    case office = "office"

    var label: String {
        switch self {
        case .home: return "Home (US exit)"
        case .office: return "Office (China)"
        }
    }
}
