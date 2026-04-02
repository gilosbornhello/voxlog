import SwiftUI
import AppKit

// Manual entry point — SPM executables need explicit NSApplication setup
@main
enum VoxLogEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the window
        let contentView = MainWindowView().environmentObject(appState)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxLog"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Also add menu bar icon
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoxLog")
        }

        // Activate app (bring to front)
        NSApp.activate(ignoringOtherApps: true)

        // Start
        Task {
            await appState.start()
        }

        print("[VoxLog] Window opened")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
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
        permissionsOK = AXIsProcessTrusted()
        if !permissionsOK {
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
            lastError = "Needs Accessibility permission. Grant it and click Retry."
        }

        do {
            try await processManager.startServer()
            serverRunning = true
            try await coreBridge.waitForHealth(maxRetries: 15, delayMs: 500)
            print("[VoxLog] Server connected")
        } catch {
            lastError = "Server: \(error.localizedDescription)"
            serverRunning = false
            return
        }

        if permissionsOK { setupHotkey() }
    }

    func setupHotkey() {
        hotkeyManager.onRecordStart = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onRecordStop = { [weak self] in
            Task { @MainActor in await self?.stopRecordingAndProcess() }
        }
        hotkeyManager.register()
        lastError = nil
    }

    func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }

    func retryAfterPermissions() {
        permissionsOK = AXIsProcessTrusted()
        if permissionsOK { setupHotkey(); lastError = nil }
        else { lastError = "Still needs Accessibility. Add VoxLog in System Settings." }
    }

    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        do {
            try audioRecorder.start()
            isRecording = true
            lastError = nil; lastResult = nil
        } catch { lastError = "Mic: \(error.localizedDescription)" }
    }

    func stopRecordingAndProcess() async {
        guard isRecording else { return }
        isRecording = false; isProcessing = true
        do {
            let audioData = try audioRecorder.stop()
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            let result = try await coreBridge.voice(audio: audioData, env: environment, targetApp: frontApp)
            pasteManager.pasteText(result.polishedText)
            totalRecordings += 1; lastResult = result.polishedText; lastError = nil
        } catch { lastError = "\(error.localizedDescription)" }
        isProcessing = false
    }

    func stop() {
        hotkeyManager.unregister(); audioRecorder.stopIfNeeded()
        processManager.stopServer(); serverRunning = false
    }
}

enum VoxEnvironment: String, CaseIterable {
    case home = "home"
    case office = "office"
    var label: String {
        switch self {
        case .home: return "Home (US)"
        case .office: return "Office (CN)"
        }
    }
}
