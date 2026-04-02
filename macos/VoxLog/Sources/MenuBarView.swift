import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header
            HStack {
                Image(systemName: appState.statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title3)
                Text(statusText)
                    .font(.headline)
                Spacer()
                Text(appState.environment.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(appState.environment == .home ?
                        Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.horizontal)

            // Permissions warning
            if !appState.permissionsOK {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VoxLog needs permissions to work:")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("1. Accessibility (global hotkey + paste)")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("2. Microphone (recording)")
                        .font(.caption2).foregroundColor(.secondary)

                    HStack {
                        Button("Grant Permissions") {
                            appState.requestPermissions()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Retry") {
                            appState.retryAfterPermissions()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)

                Divider()
            }

            // Recording status
            if appState.isRecording {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording... release Left Alt to stop")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            } else if appState.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            // Last result
            if let result = appState.lastResult {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(result)
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                .padding(.horizontal)
            }

            // Error display
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            Divider()

            // Stats
            HStack {
                Label("\(appState.totalRecordings) today", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Label(appState.serverRunning ? "Server OK" : "Server off",
                      systemImage: appState.serverRunning ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption)
                    .foregroundColor(appState.serverRunning ? .green : .red)
            }
            .padding(.horizontal)

            Divider()

            // Environment switch
            Picker("Environment", selection: $appState.environment) {
                ForEach(VoxEnvironment.allCases, id: \.self) { env in
                    Text(env.label).tag(env)
                }
            }
            .pickerStyle(.inline)
            .padding(.horizontal)

            Divider()

            // Quick actions
            Button {
                if let url = URL(string: "http://127.0.0.1:7890") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Web UI", systemImage: "globe")
            }
            .padding(.horizontal)

            Button {
                if let url = URL(string: "http://127.0.0.1:7890/static/api.html") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("API Reference", systemImage: "doc.text")
            }
            .padding(.horizontal)

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .padding(.horizontal)

            Divider()

            Button(role: .destructive) {
                appState.stop()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit VoxLog", systemImage: "power")
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .frame(width: 300)
        .task {
            await appState.start()
        }
    }

    private var statusColor: Color {
        if !appState.permissionsOK { return .orange }
        if appState.isRecording { return .red }
        if appState.lastError != nil { return .orange }
        if appState.serverRunning { return .green }
        return .gray
    }

    private var statusText: String {
        if !appState.permissionsOK { return "Needs Permissions" }
        if appState.isRecording { return "Recording" }
        if appState.isProcessing { return "Processing" }
        if appState.lastError != nil { return "Error" }
        if appState.serverRunning { return "Ready — hold Left Alt" }
        return "Starting..."
    }
}
