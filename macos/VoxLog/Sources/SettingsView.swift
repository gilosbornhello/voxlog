import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 300)
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
                Text("Home: OpenAI/Qwen via US exit. Office: Qwen/local via China.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Hotkey") {
                Text("Hold Right Option key to record")
                    .font(.body)
                Text("Release to stop and process")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Server") {
                HStack {
                    Circle()
                        .fill(appState.serverRunning ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.serverRunning ? "Running on localhost:7890" : "Not running")
                }
            }

            Section("Permissions") {
                Text("Required: Microphone, Input Monitoring, Accessibility")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("VoxLog")
                .font(.title)

            Text("Your mouth doesn't have a save button.\nVoxLog gives it one.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Text("v0.1.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Link("MIT License", destination: URL(string: "https://opensource.org/licenses/MIT")!)
                .font(.caption)
        }
        .padding()
    }
}
