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
        let contentView = ChatView().environmentObject(appState)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "VoxLog"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.minSize = NSSize(width: 360, height: 480)
        NSApp.activate(ignoringOtherApps: true)

        Task { await appState.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { appState.stop() }
}

// MARK: - Chat View (ChatGPT style)

struct ChatView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Message history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }

                        // Listening indicator
                        if appState.isRecording {
                            HStack(spacing: 8) {
                                PulsingDot()
                                Text("Listening...")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .id("listening")
                        }

                        // Processing indicator
                        if appState.isProcessing {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Transcribing...")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .id("processing")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: appState.messages.count) {
                    withAnimation {
                        proxy.scrollTo(appState.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: appState.isRecording) {
                    if appState.isRecording {
                        withAnimation { proxy.scrollTo("listening", anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input bar (ChatGPT style)
            InputBar()
                .environmentObject(appState)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: VoxMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(16)

            HStack(spacing: 8) {
                Text(message.time)
                    .font(.caption2)
                if message.latencyMs > 0 {
                    Text("\(message.latencyMs)ms")
                        .font(.caption2)
                }
                if !message.targetApp.isEmpty {
                    Text(message.targetApp)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(appState.serverRunning ? .green : .red)
                .frame(width: 8, height: 8)

            Text(appState.envLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Mic button
            Button(action: {
                if appState.isRecording {
                    // Stop listening → start processing
                    Task { await appState.stopAndProcess() }
                } else {
                    appState.startRecording()
                }
            }) {
                Image(systemName: appState.isRecording ? "arrow.up.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(appState.isRecording ? .green : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(appState.isProcessing)
            .help(appState.isRecording ? "Send" : "Start recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        // Error bar
        if let error = appState.lastError {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }
}

// MARK: - Pulsing Dot Animation

struct PulsingDot: View {
    @State private var scale: CGFloat = 1.0
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .scaleEffect(scale)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.4 }
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

    private let processManager = ProcessManager()
    private let hotkeyManager = HotkeyManager()
    private var audioEngine: AVAudioEngine?
    private var audioData = Data()
    private let sampleRate: Double = 16000

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

        // Load today's history
        await loadHistory()

        if AXIsProcessTrusted() {
            hotkeyManager.onRecordStart = { [weak self] in Task { @MainActor in self?.startRecording() } }
            hotkeyManager.onRecordStop = { [weak self] in Task { @MainActor in await self?.stopAndProcess() } }
            hotkeyManager.register()
        }
    }

    func detectEnv() async {
        guard let url = URL(string: "http://127.0.0.1:7890/v1/detect") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let env = json["env"] as? String {
            envLabel = env == "home" ? "Home" : "Office"
        }
    }

    func loadHistory() async {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        guard let url = URL(string: "http://127.0.0.1:7890/v1/history?date=\(today)&limit=50") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            messages = items.compactMap { item in
                guard let text = item["polished_text"] as? String, !text.isEmpty,
                      let ts = item["created_at"] as? String else { return nil }
                let time = String(ts.dropFirst(11).prefix(5))
                let latency = item["latency_ms"] as? Int ?? 0
                let app = item["target_app"] as? String ?? ""
                return VoxMessage(text: text, time: time, latencyMs: latency, targetApp: app)
            }
        }
    }

    func toggleRecording() {
        if isRecording { Task { await stopAndProcess() } }
        else { startRecording() }
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
            try engine.start()
            audioEngine = engine
            isRecording = true
            lastError = nil
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
            req.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")

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
            let app = json["target_app"] as? String ?? ""

            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)

                let now = Date()
                let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
                messages.append(VoxMessage(text: text, time: fmt.string(from: now), latencyMs: latency, targetApp: app))
                lastError = nil
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
