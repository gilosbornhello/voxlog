import SwiftUI
import AppKit
import AVFoundation

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
        let contentView = MainLayout().environmentObject(appState)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "VoxLog"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.minSize = NSSize(width: 400, height: 480)
        NSApp.activate(ignoringOtherApps: true)

        Task { await appState.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { appState.stop() }
}

// MARK: - Main Layout (Sidebar + Content)

struct MainLayout: View {
    @EnvironmentObject var appState: AppState
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (collapsible)
            if showSidebar {
                SidebarView()
                    .environmentObject(appState)
                    .frame(width: 180)
                    .transition(.move(edge: .leading))

                Divider()
            }

            // Main content
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() } }) {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle sidebar")

                    Text(appState.selectedDateLabel)
                        .font(.headline)

                    Spacer()

                    Circle()
                        .fill(appState.serverRunning ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(appState.envLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Chat timeline
                ChatTimeline()
                    .environmentObject(appState)

                Divider()

                // Input bar
                InputBar()
                    .environmentObject(appState)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("History")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Date list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.availableDates, id: \.self) { date in
                        SidebarDateRow(date: date, isSelected: date == appState.selectedDate)
                            .onTapGesture { appState.selectDate(date) }
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()

            // Sync to Obsidian button
            Button(action: { appState.syncToObsidian() }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync to Obsidian")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

struct SidebarDateRow: View {
    let date: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(formatDate(date))
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }

    func formatDate(_ d: String) -> String {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        if d == String(today) { return "Today" }

        let yesterday = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400)).prefix(10)
        if d == String(yesterday) { return "Yesterday" }

        // Show like "Apr 1"
        let parts = d.split(separator: "-")
        if parts.count == 3 {
            let months = ["","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            let m = Int(parts[1]) ?? 0
            let day = Int(parts[2]) ?? 0
            if m > 0 && m < 13 { return "\(months[m]) \(day)" }
        }
        return d
    }
}

// MARK: - Chat Timeline

struct ChatTimeline: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if appState.messages.isEmpty && !appState.isRecording {
                    VStack(spacing: 12) {
                        Spacer(minLength: 80)
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No recordings yet")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("Click the mic to start")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }

                        if appState.isRecording {
                            HStack(spacing: 8) {
                                PulsingDot()
                                Text("Listening...")
                                    .font(.callout)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .padding(.horizontal, 16)
                            .id("listening")
                        }

                        if appState.isProcessing {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Transcribing...")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .id("processing")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: appState.messages.count) {
                withAnimation { proxy.scrollTo(appState.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: appState.isRecording) {
                if appState.isRecording {
                    withAnimation { proxy.scrollTo("listening", anchor: .bottom) }
                }
            }
        }
    }
}

struct MessageRow: View {
    let message: VoxMessage
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.trailing, isHovered ? 28 : 0)
                    .background(Color.accentColor.opacity(isHovered ? 0.12 : 0.06))
                    .cornerRadius(12)

                // Copy button (appears on hover)
                if isHovered {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(copied ? .green : .secondary)
                            .padding(6)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            HStack(spacing: 6) {
                Text(message.time)
                if message.latencyMs > 0 { Text("· \(message.latencyMs)ms") }
                if !message.targetApp.isEmpty { Text("· \(message.targetApp)") }
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            HStack(spacing: 16) {
                Spacer()

                Button(action: {
                    if appState.isRecording {
                        Task { await appState.stopAndProcess() }
                    } else {
                        appState.startRecording()
                    }
                }) {
                    Image(systemName: appState.isRecording ? "arrow.up.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(appState.isRecording ? .green : .accentColor)
                        .symbolEffect(.pulse, isActive: appState.isRecording)
                }
                .buttonStyle(.plain)
                .disabled(appState.isProcessing)
                .help(appState.isRecording ? "Stop and transcribe" : "Start recording")

                Spacer()
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(.red).frame(width: 8, height: 8).opacity(on ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Message Model

struct VoxMessage: Identifiable {
    let id = UUID()
    let text: String
    let time: String
    let latencyMs: Int
    let targetApp: String
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var messages: [VoxMessage] = []
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var serverRunning = false
    @Published var envLabel = ""
    @Published var availableDates: [String] = []
    @Published var selectedDate: String = ""
    @Published var totalRecordings = 0

    var selectedDateLabel: String {
        if selectedDate.isEmpty { return "Today" }
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if selectedDate == today { return "Today" }
        return selectedDate
    }

    private let processManager = ProcessManager()
    private let hotkeyManager = HotkeyManager()
    private var audioEngine: AVAudioEngine?
    private var audioData = Data()
    private let sampleRate: Double = 16000
    private let token = "voxlog-dev-token"

    func start() async {
        do {
            try await processManager.startServer()
            serverRunning = true
            for _ in 0..<15 {
                if let url = URL(string: "http://127.0.0.1:7890/health"),
                   let (_, r) = try? await URLSession.shared.data(from: url),
                   (r as? HTTPURLResponse)?.statusCode == 200 { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        } catch { lastError = "Server failed"; return }

        await detectEnv()
        await loadAvailableDates()

        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        selectedDate = today
        await loadMessages(for: today)

        if AXIsProcessTrusted() {
            hotkeyManager.onRecordStart = { [weak self] in Task { @MainActor in self?.startRecording() } }
            hotkeyManager.onRecordStop = { [weak self] in Task { @MainActor in await self?.stopAndProcess() } }
            hotkeyManager.register()
        }
    }

    func detectEnv() async {
        guard let url = URL(string: "http://127.0.0.1:7890/v1/detect") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let env = json["env"] as? String {
            envLabel = env == "home" ? "Home" : "Office"
        }
    }

    func loadAvailableDates() async {
        // Get dates that have recordings
        guard let url = URL(string: "http://127.0.0.1:7890/v1/history?limit=200") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var dates = Set<String>()
            for item in items {
                if let ts = item["created_at"] as? String {
                    dates.insert(String(ts.prefix(10)))
                }
            }
            availableDates = dates.sorted().reversed()
        }
    }

    func selectDate(_ date: String) {
        selectedDate = date
        Task { await loadMessages(for: date) }
    }

    func loadMessages(for date: String) async {
        guard let url = URL(string: "http://127.0.0.1:7890/v1/history?date=\(date)&limit=200") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            messages = items.compactMap { item in
                guard let text = item["polished_text"] as? String, !text.isEmpty,
                      let ts = item["created_at"] as? String else { return nil }
                return VoxMessage(
                    text: text,
                    time: String(ts.dropFirst(11).prefix(5)),
                    latencyMs: item["latency_ms"] as? Int ?? 0,
                    targetApp: item["target_app"] as? String ?? ""
                )
            }
            totalRecordings = messages.count
        }
    }

    func syncToObsidian() {
        // Trigger export via server
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            let voxlogRoot = ProcessInfo.processInfo.environment["VOXLOG_ROOT"] ?? NSHomeDirectory() + "/voxlog"
            let python = voxlogRoot + "/.venv/bin/python"
            process.arguments = [python, voxlogRoot + "/export_cron.py"]
            process.currentDirectoryURL = URL(fileURLWithPath: voxlogRoot)
            try? process.run()
            process.waitUntilExit()
        }
    }

    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        audioData = Data()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: target) else {
            lastError = "Audio format error"; return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let count = AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / format.sampleRate)
            guard let conv = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: count) else { return }
            var err: NSError?
            converter.convert(to: conv, error: &err) { _, s in s.pointee = .haveData; return buffer }
            if let ch = conv.int16ChannelData {
                let d = Data(bytes: ch[0], count: Int(conv.frameLength) * 2)
                DispatchQueue.main.async { self.audioData.append(d) }
            }
        }

        do {
            try engine.start(); audioEngine = engine; isRecording = true; lastError = nil
        } catch { lastError = "Mic: \(error.localizedDescription)" }
    }

    func stopAndProcess() async {
        guard isRecording, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0); engine.stop()
        audioEngine = nil; isRecording = false; isProcessing = true

        let wav = makeWav(from: audioData); audioData = Data()

        do {
            let url = URL(string: "http://127.0.0.1:7890/v1/voice")!
            var req = URLRequest(url: url); req.httpMethod = "POST"
            let b = UUID().uuidString
            req.setValue("multipart/form-data; boundary=\(b)", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            var body = Data()
            body.append("--\(b)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"r.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(wav); body.append("\r\n".data(using: .utf8)!)
            for (k, v) in [("source","app"),("env","auto"),("target_app",NSWorkspace.shared.frontmostApplication?.localizedName ?? "")] {
                body.append("--\(b)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
            }
            body.append("--\(b)--\r\n".data(using: .utf8)!)
            req.httpBody = body

            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let text = json["polished_text"] as? String ?? ""
            let latency = json["latency_ms"] as? Int ?? 0

            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)

                let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
                messages.append(VoxMessage(text: text, time: fmt.string(from: Date()), latencyMs: latency, targetApp: ""))
                totalRecordings += 1; lastError = nil

                // Refresh sidebar dates
                if !availableDates.contains(selectedDate) {
                    availableDates.insert(selectedDate, at: 0)
                }
            }
        } catch { lastError = "\(error.localizedDescription)" }

        isProcessing = false
    }

    func stop() {
        hotkeyManager.unregister()
        if let e = audioEngine { e.inputNode.removeTap(onBus: 0); e.stop() }
        processManager.stopServer()
    }

    private func makeWav(from pcm: Data) -> Data {
        let sr = UInt32(sampleRate), sz = UInt32(pcm.count)
        var h = Data(capacity: 44)
        h.append(contentsOf: "RIFF".utf8)
        h.append(contentsOf: withUnsafeBytes(of: (sz+36).littleEndian){Array($0)})
        h.append(contentsOf: "WAVEfmt ".utf8)
        h.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian){Array($0)})
        h.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian){Array($0)})
        h.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian){Array($0)})
        h.append(contentsOf: withUnsafeBytes(of: sr.littleEndian){Array($0)})
        h.append(contentsOf: withUnsafeBytes(of: (sr*2).littleEndian){Array($0)})
        h.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian){Array($0)})
        h.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian){Array($0)})
        h.append(contentsOf: "data".utf8)
        h.append(contentsOf: withUnsafeBytes(of: sz.littleEndian){Array($0)})
        h.append(pcm); return h
    }
}
