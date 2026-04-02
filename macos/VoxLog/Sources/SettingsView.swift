import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gear") }

            PermissionsView()
                .environmentObject(appState)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 350)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Network Environment") {
                Picker("Environment", selection: $appState.environment) {
                    ForEach(VoxEnvironment.allCases, id: \.self) { env in
                        Text(env.label).tag(env)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    if appState.environment == .home {
                        Text("ASR: Qwen (US) → OpenAI Whisper fallback")
                        Text("LLM: OpenAI GPT → Qwen fallback")
                    } else {
                        Text("ASR: Qwen (CN) → Local Whisper fallback")
                        Text("LLM: Qwen-turbo → Ollama fallback")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section("Hotkey") {
                HStack {
                    Text("Record key:")
                    Text("Left Alt (Option)")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                }
                Text("Hold to record, release to transcribe and paste")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Server") {
                HStack {
                    Circle()
                        .fill(appState.serverRunning ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.serverRunning ? "Running on localhost:7890" : "Not running")
                    Spacer()
                    if appState.serverRunning {
                        Button("Open Web UI") {
                            if let url = URL(string: "http://127.0.0.1:7890") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Data") {
                HStack {
                    Text("Voice history:")
                    Text("~/.voxlog/history.db")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Folder") {
                        let path = NSHomeDirectory() + "/.voxlog"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .controlSize(.small)
                }
                HStack {
                    Text("Dictionary:")
                    Text("~/voxlog/terms.json")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

struct PermissionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var accessibilityOK = false
    @State private var microphoneOK = false

    var body: some View {
        Form {
            Section("Required Permissions") {
                HStack {
                    Image(systemName: accessibilityOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(accessibilityOK ? .green : .red)
                    VStack(alignment: .leading) {
                        Text("Accessibility")
                            .font(.body)
                        Text("Needed for global hotkey and paste simulation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !accessibilityOK {
                        Button("Grant") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    Image(systemName: microphoneOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(microphoneOK ? .green : .red)
                    VStack(alignment: .leading) {
                        Text("Microphone")
                            .font(.body)
                        Text("Needed for voice recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !microphoneOK {
                        Button("Grant") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section {
                Button("Refresh Permission Status") {
                    checkPermissions()
                    appState.retryAfterPermissions()
                }

                Button("Open System Settings → Privacy") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding()
        .onAppear { checkPermissions() }
    }

    private func checkPermissions() {
        accessibilityOK = AXIsProcessTrusted()
        // Microphone check is async but we approximate
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneOK = true
        default: microphoneOK = false
        }
    }
}

import AVFoundation

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("VoxLog")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your mouth doesn't have a save button.\nVoxLog gives it one.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Text("v0.1.0")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Link("Web UI", destination: URL(string: "http://127.0.0.1:7890")!)
                Link("API Docs", destination: URL(string: "http://127.0.0.1:7890/static/api.html")!)
            }
            .font(.caption)
        }
        .padding(32)
    }
}
