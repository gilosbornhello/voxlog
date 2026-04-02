import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: appState.statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
                Text("VoxLog")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Picker("", selection: $appState.environment) {
                    ForEach(VoxEnvironment.allCases, id: \.self) { env in
                        Text(env.label).tag(env)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()

            Divider()

            // Permissions warning
            if !appState.permissionsOK {
                VStack(spacing: 8) {
                    Label("Needs Accessibility Permission", systemImage: "lock.shield")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("VoxLog needs Accessibility to detect hotkeys and paste text.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack {
                        Button("Grant Permissions") {
                            appState.requestPermissions()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Retry") {
                            appState.retryAfterPermissions()
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))

                Divider()
            }

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Record section
                    GroupBox("Record") {
                        VStack(spacing: 12) {
                            if appState.isRecording {
                                HStack {
                                    Circle().fill(.red).frame(width: 12, height: 12)
                                    Text("Recording... release Left Alt to stop")
                                        .foregroundColor(.red)
                                }
                                .font(.body)
                            } else if appState.isProcessing {
                                HStack {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Processing...")
                                }
                            } else {
                                Text("Hold Left Alt key to record, release to paste")
                                    .foregroundColor(.secondary)
                            }

                            // Manual record button (for testing without hotkey)
                            Button(action: {
                                if appState.isRecording {
                                    Task { await appState.stopRecordingAndProcess() }
                                } else {
                                    appState.startRecording()
                                }
                            }) {
                                Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(appState.isRecording ? .red : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    // Last result
                    if let result = appState.lastResult {
                        GroupBox("Last Result") {
                            Text(result)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Error
                    if let error = appState.lastError {
                        GroupBox {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }

                    // Status
                    GroupBox("Status") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle()
                                    .fill(appState.serverRunning ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text("Server: \(appState.serverRunning ? "Running" : "Off")")
                                Spacer()
                                Text("Recordings: \(appState.totalRecordings)")
                            }
                            .font(.caption)

                            HStack {
                                Text("Hotkey: Left Alt (hold to record)")
                                Spacer()
                                Text("Permissions: \(appState.permissionsOK ? "OK" : "Needed")")
                                    .foregroundColor(appState.permissionsOK ? .green : .orange)
                            }
                            .font(.caption)
                        }
                    }

                    // Quick actions
                    GroupBox("Tools") {
                        HStack {
                            Button("Web UI") {
                                if let url = URL(string: "http://127.0.0.1:7890") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Button("API Docs") {
                                if let url = URL(string: "http://127.0.0.1:7890/static/api.html") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Button("Voice History") {
                                if let url = URL(string: "http://127.0.0.1:7890") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding()
            }
        }
    }

    private var statusColor: Color {
        if !appState.permissionsOK { return .orange }
        if appState.isRecording { return .red }
        if appState.lastError != nil { return .orange }
        if appState.serverRunning { return .green }
        return .gray
    }
}
