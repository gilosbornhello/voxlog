import SwiftUI
import AppKit

// MARK: - Model Provider Config

struct ProviderConfig: Identifiable, Codable {
    var id = UUID()
    var name: String          // display name: "Qwen ASR (US)", "OpenAI Whisper"
    var type: String          // "asr" or "llm"
    var apiKey: String
    var baseURL: String
    var model: String
    var region: String        // "us", "cn", "intl"
}

struct RegionConfig: Codable {
    var mainASR: String       // provider id
    var fallbackASR: String
    var mainLLM: String
    var fallbackLLM: String
}

// MARK: - Settings Editor

struct SettingsEditor: View {
    @State private var providers: [ProviderConfig] = []
    @State private var usConfig = RegionConfig(mainASR: "", fallbackASR: "", mainLLM: "", fallbackLLM: "")
    @State private var cnConfig = RegionConfig(mainASR: "", fallbackASR: "", mainLLM: "", fallbackLLM: "")
    @State private var statusMessage = ""
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gear")
                Text("Settings").font(.headline)
                Spacer()
            }.padding()

            Divider()

            // Tabs
            Picker("", selection: $selectedTab) {
                Text("🇺🇸 US / Home").tag(0)
                Text("🇨🇳 China / Office").tag(1)
                Text("Providers").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            // Content
            ScrollView {
                switch selectedTab {
                case 0: regionView(title: "Home (US Network)", config: $usConfig, region: "us")
                case 1: regionView(title: "Office (China Network)", config: $cnConfig, region: "cn")
                case 2: providersView
                default: EmptyView()
                }
            }

            Divider()

            // Footer
            HStack {
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundColor(.green)
                }
                Spacer()
                Button("Save & Apply") { save() }
                    .buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(minWidth: 560, minHeight: 520)
        .task { load() }
    }

    // MARK: - Region View (US or CN)

    func regionView(title: String, config: Binding<RegionConfig>, region: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3).fontWeight(.semibold).padding(.top, 8)

            // ASR
            GroupBox("Speech Recognition (ASR)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Main:").frame(width: 60, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                        Picker("", selection: config.mainASR) {
                            Text("Select...").tag("")
                            ForEach(asrProviders(for: region)) { p in
                                Text(p.name).tag(p.id.uuidString)
                            }
                        }.labelsHidden()
                    }
                    HStack {
                        Text("Fallback:").frame(width: 60, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                        Picker("", selection: config.fallbackASR) {
                            Text("None").tag("")
                            ForEach(asrProviders(for: region)) { p in
                                Text(p.name).tag(p.id.uuidString)
                            }
                        }.labelsHidden()
                    }
                }
            }

            // LLM
            GroupBox("Text Polish (LLM)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Main:").frame(width: 60, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                        Picker("", selection: config.mainLLM) {
                            Text("Select...").tag("")
                            ForEach(llmProviders(for: region)) { p in
                                Text(p.name).tag(p.id.uuidString)
                            }
                        }.labelsHidden()
                    }
                    HStack {
                        Text("Fallback:").frame(width: 60, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                        Picker("", selection: config.fallbackLLM) {
                            Text("None").tag("")
                            ForEach(llmProviders(for: region)) { p in
                                Text(p.name).tag(p.id.uuidString)
                            }
                        }.labelsHidden()
                    }
                }
            }
        }
        .padding()
    }

    func asrProviders(for region: String) -> [ProviderConfig] {
        providers.filter { $0.type == "asr" && ($0.region == region || $0.region == "any") }
    }

    func llmProviders(for region: String) -> [ProviderConfig] {
        providers.filter { $0.type == "llm" && ($0.region == region || $0.region == "any") }
    }

    // MARK: - Providers View

    var providersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Providers").font(.title3).fontWeight(.semibold)
                Spacer()
                Button(action: { addProvider() }) {
                    HStack { Image(systemName: "plus"); Text("Add") }
                }.controlSize(.small)
            }.padding(.top, 8)

            ForEach($providers) { $provider in
                ProviderCard(provider: $provider, onDelete: { deleteProvider(provider.id) })
            }

            if providers.isEmpty {
                Text("No providers configured. Click + Add to get started.")
                    .foregroundColor(.secondary).padding()
            }
        }
        .padding()
    }

    // MARK: - Actions

    func addProvider() {
        providers.append(ProviderConfig(
            name: "New Provider",
            type: "asr",
            apiKey: "",
            baseURL: "",
            model: "",
            region: "us"
        ))
    }

    func deleteProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
    }

    // MARK: - Load / Save

    func load() {
        let path = NSHomeDirectory() + "/.voxlog/settings.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let settings = try? JSONDecoder().decode(SettingsData.self, from: data) {
            providers = settings.providers
            usConfig = settings.us
            cnConfig = settings.cn
            return
        }

        // First time — create defaults from .env
        loadDefaults()
    }

    func loadDefaults() {
        var env: [String: String] = [:]
        let envPath = NSHomeDirectory() + "/.voxlog/.env"
        if let content = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
            }
        }

        let dashKey = env["DASHSCOPE_API_KEY"] ?? ""
        let openaiKey = env["OPENAI_API_KEY"] ?? ""
        let sfKey = env["SILICONFLOW_API_KEY"] ?? ""

        providers = [
            ProviderConfig(name: "Qwen ASR (US)", type: "asr", apiKey: dashKey,
                          baseURL: "https://dashscope-us.aliyuncs.com/api/v1",
                          model: "qwen3-asr-flash-us", region: "us"),
            ProviderConfig(name: "Qwen ASR (CN)", type: "asr", apiKey: dashKey,
                          baseURL: "https://dashscope.aliyuncs.com/api/v1",
                          model: "qwen3-asr-flash", region: "cn"),
            ProviderConfig(name: "OpenAI Whisper", type: "asr", apiKey: openaiKey,
                          baseURL: "https://api.openai.com/v1",
                          model: "whisper-1", region: "any"),
            ProviderConfig(name: "SiliconFlow SenseVoice", type: "asr", apiKey: sfKey,
                          baseURL: env["SILICONFLOW_BASE_URL"] ?? "https://api.siliconflow.cn/v1",
                          model: env["SILICONFLOW_MODEL"] ?? "FunAudioLLM/SenseVoiceSmall", region: "cn"),
            ProviderConfig(name: "OpenAI GPT", type: "llm", apiKey: openaiKey,
                          baseURL: "https://api.openai.com/v1",
                          model: "gpt-4o-mini", region: "any"),
            ProviderConfig(name: "Qwen Turbo", type: "llm", apiKey: dashKey,
                          baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                          model: "qwen-turbo", region: "any"),
        ]

        // Set defaults
        usConfig = RegionConfig(
            mainASR: providers[0].id.uuidString,   // Qwen US
            fallbackASR: providers[2].id.uuidString, // OpenAI Whisper
            mainLLM: providers[4].id.uuidString,   // OpenAI GPT
            fallbackLLM: providers[5].id.uuidString  // Qwen Turbo
        )
        cnConfig = RegionConfig(
            mainASR: providers[1].id.uuidString,   // Qwen CN
            fallbackASR: providers[3].id.uuidString, // SiliconFlow
            mainLLM: providers[5].id.uuidString,   // Qwen Turbo
            fallbackLLM: providers[4].id.uuidString  // OpenAI GPT
        )
    }

    func save() {
        let settings = SettingsData(providers: providers, us: usConfig, cn: cnConfig)
        let path = NSHomeDirectory() + "/.voxlog/settings.json"
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        // Also write .env for backward compatibility
        writeEnv()

        statusMessage = "Saved! Restart VoxLog to apply."
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusMessage = "" }
    }

    func writeEnv() {
        // Extract unique keys from providers
        var dashKey = "", openaiKey = "", sfKey = "", sfURL = "", sfModel = "", region = "us"

        for p in providers {
            if p.name.contains("Qwen") && !p.apiKey.isEmpty { dashKey = p.apiKey }
            if p.name.contains("OpenAI") && !p.apiKey.isEmpty { openaiKey = p.apiKey }
            if p.name.contains("SiliconFlow") {
                sfKey = p.apiKey; sfURL = p.baseURL; sfModel = p.model
            }
            if p.name.contains("Qwen ASR (US)") { region = "us" }
        }

        let lines = [
            "DASHSCOPE_API_KEY=\(dashKey)",
            "DASHSCOPE_REGION=\(region)",
            "OPENAI_API_KEY=\(openaiKey)",
            "SILICONFLOW_API_KEY=\(sfKey)",
            "SILICONFLOW_BASE_URL=\(sfURL)",
            "SILICONFLOW_MODEL=\(sfModel)",
            "VOXLOG_API_TOKEN=voxlog-dev-token",
            "VOXLOG_ENV=home",
        ]
        let envPath = NSHomeDirectory() + "/.voxlog/.env"
        try? lines.joined(separator: "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Provider Card

struct ProviderCard: View {
    @Binding var provider: ProviderConfig
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                // Header (always visible)
                HStack {
                    Image(systemName: provider.type == "asr" ? "waveform" : "text.bubble")
                        .foregroundColor(provider.type == "asr" ? .blue : .purple)
                    TextField("Name", text: $provider.name)
                        .font(.callout).fontWeight(.medium)

                    Picker("", selection: $provider.type) {
                        Text("ASR").tag("asr")
                        Text("LLM").tag("llm")
                    }.frame(width: 70)

                    Picker("", selection: $provider.region) {
                        Text("🇺🇸 US").tag("us")
                        Text("🇨🇳 CN").tag("cn")
                        Text("🌐 Any").tag("any")
                    }.frame(width: 80)

                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundColor(.secondary)
                    }.buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.caption).foregroundColor(.red.opacity(0.5))
                    }.buttonStyle(.plain)
                }

                // Detail (expandable)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("API Key:").frame(width: 65, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                            SecureFieldToggle(text: $provider.apiKey, placeholder: "sk-xxx")
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(provider.apiKey, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc").font(.caption2)
                            }.buttonStyle(.plain).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Base URL:").frame(width: 65, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                            TextField("https://...", text: $provider.baseURL)
                                .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                        }
                        HStack {
                            Text("Model:").frame(width: 65, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                            TextField("model-name", text: $provider.model)
                                .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Secure Field Toggle

struct SecureFieldToggle: View {
    @Binding var text: String
    let placeholder: String
    @State private var isRevealed = false

    var body: some View {
        HStack {
            if isRevealed {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            } else {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
            Button(action: { isRevealed.toggle() }) {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.caption2).foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Persistence

struct SettingsData: Codable {
    var providers: [ProviderConfig]
    var us: RegionConfig
    var cn: RegionConfig
}
