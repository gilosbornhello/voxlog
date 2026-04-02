import SwiftUI
import AppKit

struct SettingsEditor: View {
    @State private var config: [String: String] = [:]
    @State private var isLoading = true
    @State private var statusMessage = ""

    let fields: [(key: String, label: String, placeholder: String)] = [
        ("DASHSCOPE_API_KEY", "DashScope API Key", "sk-xxx"),
        ("DASHSCOPE_REGION", "DashScope Region", "us / cn / intl"),
        ("OPENAI_API_KEY", "OpenAI API Key", "sk-xxx"),
        ("SILICONFLOW_API_KEY", "SiliconFlow API Key", "sk-xxx"),
        ("SILICONFLOW_BASE_URL", "SiliconFlow Base URL", "https://api.siliconflow.cn/v1"),
        ("SILICONFLOW_MODEL", "SiliconFlow Model", "FunAudioLLM/SenseVoiceSmall"),
        ("VOXLOG_API_TOKEN", "VoxLog API Token", "voxlog-dev-token"),
        ("VOXLOG_ENV", "Default Environment", "home / office"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gear")
                Text("Settings").font(.headline)
                Spacer()
            }.padding()

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(fields, id: \.key) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                            HStack {
                                SecureFieldToggle(
                                    text: Binding(
                                        get: { config[field.key] ?? "" },
                                        set: { config[field.key] = $0 }
                                    ),
                                    placeholder: field.placeholder
                                )

                                // Copy button
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(config[field.key] ?? "", forType: .string)
                                    statusMessage = "Copied \(field.label)"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { statusMessage = "" }
                                }) {
                                    Image(systemName: "doc.on.doc").font(.caption)
                                }.buttonStyle(.plain).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundColor(.green)
                }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 450)
        .task { load() }
    }

    func load() {
        let envPath = NSHomeDirectory() + "/.voxlog/.env"
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            isLoading = false; return
        }
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                config[String(parts[0])] = String(parts[1])
            }
        }
        isLoading = false
    }

    func save() {
        let envPath = NSHomeDirectory() + "/.voxlog/.env"
        let dir = NSHomeDirectory() + "/.voxlog"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var lines: [String] = []
        for field in fields {
            let value = config[field.key] ?? ""
            lines.append("\(field.key)=\(value)")
        }
        try? lines.joined(separator: "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
        statusMessage = "Saved! Restart VoxLog to apply."
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusMessage = "" }
    }
}

// Toggle between visible and hidden field
struct SecureFieldToggle: View {
    @Binding var text: String
    let placeholder: String
    @State private var isRevealed = false

    var body: some View {
        HStack {
            if isRevealed {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            Button(action: { isRevealed.toggle() }) {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.caption).foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
    }
}
