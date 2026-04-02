import SwiftUI
import ServiceManagement

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
    @Published var lastResult: String?
    @Published var serverRunning = false
    @Published var environment: VoxEnvironment = .home
    @Published var totalRecordings: Int = 0
    @Published var permissionsOK = false

    let processManager = ProcessManager()
    let audioRecorder = AudioRecorder()
    let coreBridge = CoreBridge()
    let pasteManager = PasteManager()
    let hotkeyManager = HotkeyManager()

    var statusIcon: String {
        if !permissionsOK { return "exclamationmark.lock.fill" }
        if isRecording { return "mic.fill" }
        if isProcessing { return "ellipsis.circle" }
        if lastError != nil { return "exclamationmark.triangle.fill" }
        if serverRunning { return "waveform" }
        return "waveform.slash"
    }

    func start() async {
        // Check permissions first
        permissionsOK = checkPermissions()
        if !permissionsOK {
            lastError = "Needs permissions. Click 'Grant Permissions' in menu."
            return
        }

        // Start Python server
        do {
            try await processManager.startServer()
            serverRunning = true

            // Wait for server ready
            try await coreBridge.waitForHealth(maxRetries: 15, delayMs: 500)

            // Register hotkey
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
            lastError = "Server start failed: \(error.localizedDescription)"
            serverRunning = false
        }
    }

    func checkPermissions() -> Bool {
        // Check Accessibility (needed for global hotkey + paste simulation)
        let accessibilityOK = AXIsProcessTrusted()
        if !accessibilityOK {
            // Trigger the system prompt to add the app
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
        }
        return accessibilityOK
    }

    func requestPermissions() {
        // Trigger the Accessibility permission dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Open System Settings to Input Monitoring
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func retryAfterPermissions() {
        permissionsOK = AXIsProcessTrusted()
        if permissionsOK {
            lastError = nil
            Task {
                await start()
            }
        } else {
            lastError = "Still needs Accessibility permission. Add VoxLog in System Settings."
        }
    }

    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        do {
            try audioRecorder.start()
            isRecording = true
            lastError = nil
            lastResult = nil
        } catch {
            lastError = "Mic error: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndProcess() async {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        do {
            let audioData = try audioRecorder.stop()
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            let result = try await coreBridge.voice(
                audio: audioData,
                env: environment,
                targetApp: frontApp
            )
            pasteManager.pasteText(result.polishedText)
            totalRecordings += 1
            lastResult = result.polishedText
            lastError = nil
        } catch {
            lastError = "\(error.localizedDescription)"
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
