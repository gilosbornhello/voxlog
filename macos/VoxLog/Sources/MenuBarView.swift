import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header
            HStack {
                Image(systemName: appState.statusIcon)
                    .foregroundColor(statusColor)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            // Recording status
            if appState.isRecording {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording... release key to stop")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

            // Error display
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // Stats
            HStack {
                Text("Recordings today: \(appState.totalRecordings)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(appState.environment.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Divider()

            // Environment switch
            Picker("Environment", selection: $appState.environment) {
                ForEach(VoxEnvironment.allCases, id: \.self) { env in
                    Text(env.label).tag(env)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)

            Divider()

            // Actions
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .padding(.horizontal)

            Button("Quit VoxLog") {
                appState.stop()
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .frame(width: 280)
        .task {
            await appState.start()
        }
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.lastError != nil { return .orange }
        if appState.serverRunning { return .green }
        return .gray
    }

    private var statusText: String {
        if appState.isRecording { return "Recording" }
        if appState.isProcessing { return "Processing" }
        if appState.lastError != nil { return "Error" }
        if appState.serverRunning { return "Ready" }
        return "Starting..."
    }
}
