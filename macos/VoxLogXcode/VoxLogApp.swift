import SwiftUI
import AppKit
import AVFoundation

@main
struct VoxLogApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("VoxLog", id: "main") {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 400, minHeight: 600)
                .task { await appState.start() }
        }
        .defaultSize(width: 400, height: 600)
    }
}

// MARK: - Main View

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()

            // Permission warning
            if !appState.permissionsOK {
                permissionBanner
                Divider()
            }

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    recordSection
                    if let result = appState.lastResult { resultSection(result) }
                    if let error = appState.lastError { errorSection(error) }
                    statusSection
                    toolsSection
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            Image(systemName: appState.isRecording ? "mic.fill" : "waveform")
                .font(.title2)
                .foregroundColor(appState.isRecording ? .red : .accentColor)
            Text("VoxLog")
                .font(.title2).fontWeight(.bold)
            Spacer()
            Picker("", selection: $appState.environment) {
                ForEach(VoxEnvironment.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding()
    }

    // MARK: - Permission Banner

    var permissionBanner: some View {
        VStack(spacing: 8) {
            Label("Needs Accessibility Permission", systemImage: "lock.shield")
                .font(.headline).foregroundColor(.orange)
            Text("Required for global hotkey and paste. Add VoxLog in System Settings → Privacy → Accessibility.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Open Settings") { appState.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                Button("Retry") { appState.retryPermissions() }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Record

    var recordSection: some View {
        GroupBox("Record") {
            VStack(spacing: 12) {
                if appState.isRecording {
                    HStack {
                        Circle().fill(.red).frame(width: 12, height: 12)
                        Text("Recording... click again to stop")
                            .foregroundColor(.red)
                    }
                } else if appState.isProcessing {
                    HStack { ProgressView().scaleEffect(0.8); Text("Processing...") }
                } else {
                    Text("Click mic to record. Or hold Left Alt key.")
                        .foregroundColor(.secondary).font(.callout)
                }

                Button(action: { appState.toggleRecording() }) {
                    ZStack {
                        Circle()
                            .fill(appState.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                            .frame(width: 72, height: 72)
                        Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(appState.isRecording ? .red : .accentColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(appState.isProcessing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Result

    func resultSection(_ result: AppState.VoiceResultData) -> some View {
        GroupBox("Last Result") {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("\(result.asr) → \(result.llm)")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("\(result.latencyMs)ms")
                        .font(.caption2).foregroundColor(.secondary)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.text, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Error

    func errorSection(_ error: String) -> some View {
        GroupBox {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundColor(.red).font(.caption)
        }
    }

    // MARK: - Status

    var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle().fill(appState.serverRunning ? .green : .red).frame(width: 8, height: 8)
                    Text("Server: \(appState.serverRunning ? "Running" : "Off")")
                    Spacer()
                    Text("Today: \(appState.totalRecordings)")
                }
                .font(.caption)
                HStack {
                    Text("Hotkey: Left Alt")
                    Spacer()
                    Text("Permissions: \(appState.permissionsOK ? "OK" : "Needed")")
                        .foregroundColor(appState.permissionsOK ? .green : .orange)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Tools

    var toolsSection: some View {
        GroupBox("Tools") {
            HStack {
                Button("Web UI") { NSWorkspace.shared.open(URL(string: "http://localhost:7890")!) }
                Button("API Docs") { NSWorkspace.shared.open(URL(string: "http://localhost:7890/static/api.html")!) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .foregroundColor(.red)
            }
            .font(.caption)
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    struct VoiceResultData {
        let text: String
        let asr: String
        let llm: String
        let latencyMs: Int
    }

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var lastResult: VoiceResultData?
    @Published var serverRunning = false
    @Published var environment: VoxEnvironment = .home
    @Published var totalRecordings = 0
    @Published var permissionsOK = false

    private let processManager = ProcessManager()
    private let hotkeyManager = HotkeyManager()
    private var audioRecorder: AVAudioEngine?
    private var audioData = Data()
    private let sampleRate: Double = 16000

    func start() async {
        permissionsOK = AXIsProcessTrusted()

        // Start server
        do {
            try await processManager.startServer()
            serverRunning = true
            // Wait for health
            for _ in 0..<15 {
                if let url = URL(string: "http://127.0.0.1:7890/health"),
                   let (_, resp) = try? await URLSession.shared.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode == 200 {
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            print("[VoxLog] Server ready")
        } catch {
            lastError = "Server: \(error.localizedDescription)"
            serverRunning = false
        }

        if permissionsOK { setupHotkey() }
    }

    func setupHotkey() {
        hotkeyManager.onRecordStart = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onRecordStop = { [weak self] in
            Task { @MainActor in await self?.stopAndProcess() }
        }
        hotkeyManager.register()
    }

    func toggleRecording() {
        if isRecording {
            Task { await stopAndProcess() }
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        audioData = Data()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            lastError = "Audio format error"
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let ch = converted.int16ChannelData {
                let data = Data(bytes: ch[0], count: Int(converted.frameLength) * 2)
                DispatchQueue.main.async { self.audioData.append(data) }
            }
        }

        do {
            try engine.start()
            audioRecorder = engine
            isRecording = true
            lastError = nil; lastResult = nil
        } catch {
            lastError = "Mic: \(error.localizedDescription)"
        }
    }

    func stopAndProcess() async {
        guard isRecording, let engine = audioRecorder else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioRecorder = nil
        isRecording = false
        isProcessing = true

        let wavData = makeWav(from: audioData)
        audioData = Data()

        do {
            let result = try await sendToServer(wav: wavData)
            lastResult = result
            totalRecordings += 1
            lastError = nil
        } catch {
            lastError = "\(error.localizedDescription)"
        }
        isProcessing = false
    }

    func sendToServer(wav: Data) async throws -> VoiceResultData {
        let url = URL(string: "http://127.0.0.1:7890/v1/voice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")

        var body = Data()
        // Audio
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"rec.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        // Fields
        for (k, v) in [("source", "macos_app"), ("env", environment.rawValue), ("target_app", NSWorkspace.shared.frontmostApplication?.localizedName ?? "")] {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "VoxLog", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return VoiceResultData(
            text: json["polished_text"] as? String ?? json["raw_text"] as? String ?? "",
            asr: json["asr_provider"] as? String ?? "unknown",
            llm: json["llm_provider"] as? String ?? "none",
            latencyMs: json["latency_ms"] as? Int ?? 0
        )
    }

    func openAccessibilitySettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    func retryPermissions() {
        permissionsOK = AXIsProcessTrusted()
        if permissionsOK { setupHotkey(); lastError = nil }
        else { lastError = "Add VoxLog in System Settings → Privacy → Accessibility" }
    }

    private func makeWav(from pcm: Data) -> Data {
        let sr = UInt32(sampleRate)
        let dataSize = UInt32(pcm.count)
        var h = Data(capacity: 44)
        h.append(contentsOf: "RIFF".utf8)
        h.append(contentsOf: withUnsafeBytes(of: (dataSize + 36).littleEndian) { Array($0) })
        h.append(contentsOf: "WAVEfmt ".utf8)
        h.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        h.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        h.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        h.append(contentsOf: withUnsafeBytes(of: sr.littleEndian) { Array($0) })
        h.append(contentsOf: withUnsafeBytes(of: (sr * 2).littleEndian) { Array($0) })
        h.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        h.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        h.append(contentsOf: "data".utf8)
        h.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        h.append(pcm)
        return h
    }
}

// MARK: - Environment

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
