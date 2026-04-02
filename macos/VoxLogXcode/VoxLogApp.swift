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
    var dictWindow: NSWindow?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build menu bar
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "VoxLog")
        appMenu.addItem(withTitle: "Dictionary...", action: #selector(openDictionary), keyEquivalent: "d")
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Sync to Obsidian", action: #selector(syncObsidian), keyEquivalent: "s")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit VoxLog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu

        let contentView = MainLayout().environmentObject(appState)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "VoxLog"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.minSize = NSSize(width: 420, height: 500)
        NSApp.activate(ignoringOtherApps: true)
        Task { await appState.start() }
    }

    @objc func openDictionary() {
        if let w = dictWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "VoxLog Dictionary"
        w.contentView = NSHostingView(rootView: DictionaryEditor().environmentObject(appState))
        w.center()
        w.makeKeyAndOrderFront(nil)
        dictWindow = w
    }

    var settingsWindow: NSWindow?

    @objc func openSettings() {
        if let w = settingsWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "VoxLog Settings"
        w.contentView = NSHostingView(rootView: SettingsEditor())
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
    }

    @objc func syncObsidian() { appState.syncToObsidian() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { appState.stop() }
}

// MARK: - Message Model

enum MessageRole: String { case me, other }

struct VoxMessage: Identifiable {
    let id = UUID()
    let text: String
    let time: String
    let role: MessageRole  // me = voice recording, other = pasted text
    let latencyMs: Int
}

// MARK: - Main Layout

struct MainLayout: View {
    @EnvironmentObject var appState: AppState
    @State private var showSidebar = true
    @State private var showPreview = false
    @State private var previewPath = ""

    private let previewWidth: CGFloat = 320

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Agents
            if showSidebar {
                SidebarView().environmentObject(appState).frame(width: 160)
                Divider()
            }

            // Center: Chat (fixed min width, never compressed)
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button(action: { toggleLeftSidebar() }) {
                        Image(systemName: "sidebar.left").foregroundColor(.secondary)
                    }.buttonStyle(.plain)

                    Text(appState.selectedDateLabel).font(.headline)
                    Spacer()
                    if !appState.modelLabel.isEmpty {
                        Text(appState.modelLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Circle().fill(appState.serverRunning ? .green : .red).frame(width: 6, height: 6)
                    Text(appState.envLabel).font(.caption).foregroundColor(.secondary)

                    Button(action: { togglePreview() }) {
                        Image(systemName: "sidebar.right").foregroundColor(showPreview ? .accentColor : .secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)

                Divider()

                ChatArea(onFileTap: { path in
                    previewPath = path
                    togglePreview(forceOpen: true)
                }).environmentObject(appState)
                .onAppear {
                    appState.previewFile = { path in
                        previewPath = path
                        togglePreview(forceOpen: true)
                    }
                }

                Divider()

                InputBar().environmentObject(appState)
            }
            .frame(minWidth: 380)

            // Right sidebar: Markdown preview
            if showPreview {
                Divider()
                MarkdownPreview(filePath: previewPath, onClose: { togglePreview() })
                    .frame(width: previewWidth)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    func toggleLeftSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
    }

    func togglePreview(forceOpen: Bool = false) {
        let willShow = forceOpen || !showPreview

        // Expand/shrink window width so chat area stays the same size
        if let window = NSApp.mainWindow {
            var frame = window.frame
            if willShow && !showPreview {
                // Opening: expand window to the right
                frame.size.width += previewWidth
            } else if !willShow && showPreview {
                // Closing: shrink window from the right
                frame.size.width -= previewWidth
            }
            window.setFrame(frame, display: true, animate: true)
        }

        withAnimation(.easeInOut(duration: 0.2)) { showPreview = willShow }
    }
}

// MARK: - Agent Sidebar

struct AgentInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let emoji: String
    let parent: String  // empty = top level
    var count: Int = 0
    var lastActive: String = ""
}

let DEFAULT_AGENTS: [AgentInfo] = [
    AgentInfo(id: "claude-code", name: "Claude Code", icon: "terminal", emoji: "👨‍💻", parent: ""),
    AgentInfo(id: "claude-code/office-hours", name: "Office Hours", icon: "person.2", emoji: "🧑‍💼", parent: "claude-code"),
    AgentInfo(id: "claude-code/ceo-review", name: "CEO Review", icon: "star", emoji: "👔", parent: "claude-code"),
    AgentInfo(id: "claude-code/eng-review", name: "Eng Review", icon: "wrench", emoji: "🔧", parent: "claude-code"),
    AgentInfo(id: "claude-code/design-review", name: "Design Review", icon: "paintbrush", emoji: "🎨", parent: "claude-code"),
    AgentInfo(id: "claude-mac", name: "Claude for Mac", icon: "desktopcomputer", emoji: "🖥️", parent: ""),
    AgentInfo(id: "claude-mac/chat", name: "Chat", icon: "bubble.left", emoji: "💬", parent: "claude-mac"),
    AgentInfo(id: "claude-mac/cowork", name: "Co-work", icon: "person.2.fill", emoji: "🤝", parent: "claude-mac"),
    AgentInfo(id: "openclaw", name: "OpenClaw", icon: "cpu", emoji: "🦞", parent: ""),
    AgentInfo(id: "general", name: "General", icon: "doc.text", emoji: "📝", parent: ""),
]

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Agents").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(topLevelAgents) { agent in
                        AgentRow(agent: agent, isSelected: agent.id == appState.selectedAgent)
                            .onTapGesture { appState.selectAgent(agent.id) }

                        // Sub-agents
                        ForEach(subAgents(for: agent.id)) { sub in
                            AgentRow(agent: sub, isSelected: sub.id == appState.selectedAgent, indent: true)
                                .onTapGesture { appState.selectAgent(sub.id) }
                        }
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider()

            // Bottom toolbar: Sync + Dictionary + Settings
            HStack(spacing: 12) {
                Button(action: { appState.syncToObsidian() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14))
                        Text("Sync").font(.caption2)
                    }.foregroundColor(.secondary)
                }.buttonStyle(.plain).help("Sync to Obsidian")

                Button(action: { openDictionary() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "character.book.closed").font(.system(size: 14))
                        Text("Dict").font(.caption2)
                    }.foregroundColor(.secondary)
                }.buttonStyle(.plain).help("Personal Dictionary (Cmd+D)")

                Button(action: { openSettings() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "gear").font(.system(size: 14))
                        Text("Settings").font(.caption2)
                    }.foregroundColor(.secondary)
                }.buttonStyle(.plain).help("Settings (API keys, models)")
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    func openDictionary() {
        NSApp.sendAction(#selector(AppDelegate.openDictionary), to: nil, from: nil)
    }

    func openSettings() {
        NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
    }

    var topLevelAgents: [AgentInfo] {
        appState.agents.filter { $0.parent.isEmpty }
    }

    func subAgents(for parentId: String) -> [AgentInfo] {
        appState.agents.filter { $0.parent == parentId }
    }
}

struct AgentRow: View {
    let agent: AgentInfo
    let isSelected: Bool
    var indent: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Avatar (WeChat style rounded square)
            Text(agent.emoji)
                .font(.system(size: indent ? 16 : 20))
                .frame(width: indent ? 26 : 32, height: indent ? 26 : 32)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                .cornerRadius(indent ? 6 : 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(indent ? .caption : .callout)
                    .lineLimit(1)
                if agent.count > 0 && !indent {
                    Text("\(agent.count) messages")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if agent.count > 0 && indent {
                Text("\(agent.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, indent ? 16 : 6)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Chat Area (WeChat/WhatsApp style)

struct ChatArea: View {
    @EnvironmentObject var appState: AppState
    var onFileTap: ((String) -> Void)?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if appState.messages.isEmpty && !appState.isRecording {
                    VStack(spacing: 12) {
                        Spacer(minLength: 100)
                        Image(systemName: "waveform").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.2))
                        Text("Your mouth has a save button").font(.callout).foregroundColor(.secondary.opacity(0.5))
                    }.frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(appState.messages) { msg in
                            ChatBubble(message: msg, onFileTap: onFileTap).id(msg.id)
                        }
                        if appState.isRecording {
                            HStack { Spacer(); ListeningIndicator() }.padding(.horizontal, 16).id("listening")
                        }
                        if appState.isProcessing {
                            HStack { Spacer(); ProcessingIndicator() }.padding(.horizontal, 16).id("processing")
                        }
                    }.padding(.vertical, 8)
                }
            }
            .onChange(of: appState.messages.count) {
                withAnimation { proxy.scrollTo(appState.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: appState.isRecording) {
                if appState.isRecording { withAnimation { proxy.scrollTo("listening", anchor: .bottom) } }
            }
        }
    }
}

// MARK: - Chat Bubble (right = me, left = other)

struct ChatBubble: View {
    let message: VoxMessage
    var onFileTap: ((String) -> Void)?
    @State private var isHovered = false
    @State private var copied = false

    var filePaths: [String] { extractFilePaths(from: message.text) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .me { Spacer(minLength: 60) }

            VStack(alignment: message.role == .me ? .trailing : .leading, spacing: 3) {
                ZStack(alignment: message.role == .me ? .topTrailing : .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text)
                            .font(.body)
                            .textSelection(.enabled)

                        // File path links
                        ForEach(filePaths, id: \.self) { path in
                            Button(action: { onFileTap?(path) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text.fill").font(.caption2)
                                    Text((path as NSString).lastPathComponent)
                                        .font(.caption).lineLimit(1)
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(message.role == .me ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
                    .cornerRadius(16)

                    if isHovered {
                        Button(action: { copyText() }) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                                .foregroundColor(copied ? .green : .secondary)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
                .onHover { isHovered = $0 }

                HStack(spacing: 4) {
                    if message.role == .other {
                        Image(systemName: "person.fill").font(.system(size: 8))
                    }
                    Text(message.time)
                    if message.latencyMs > 0 { Text("· \(message.latencyMs)ms") }
                    if message.role == .me {
                        Image(systemName: "mic.fill").font(.system(size: 8))
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
            }

            if message.role == .other { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
    }

    func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Listening Indicator

struct ListeningIndicator: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text("Listening...").font(.callout).foregroundColor(.red.opacity(0.8))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .cornerRadius(16)
    }
}

struct ProcessingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.6)
            Text("Transcribing...").font(.callout).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Input Bar (Claude for Mac style)

struct AttachedFile: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
}

struct InputBar: View {
    @EnvironmentObject var appState: AppState
    @State private var pasteText = ""
    @State private var attachedFiles: [AttachedFile] = []

    var body: some View {
        VStack(spacing: 0) {
            if let error = appState.lastError {
                Text(error).font(.caption).foregroundColor(.red)
                    .padding(.horizontal, 16).padding(.top, 4)
            }

            // Attached files row
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedFiles) { file in
                            HStack(spacing: 4) {
                                Image(systemName: file.icon).font(.caption2)
                                Text(file.name).font(.caption).lineLimit(1)
                                Button(action: { attachedFiles.removeAll { $0.id == file.id } }) {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }.buttonStyle(.plain)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                            .onTapGesture { appState.previewFile?(file.path) }
                        }
                    }.padding(.horizontal, 12).padding(.top, 6)
                }
            }

            if appState.isRecording {
                HStack(spacing: 20) {
                    Button(action: { appState.cancelRecording() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.secondary)
                    }.buttonStyle(.plain).help("Cancel")
                    Spacer()
                    ListeningIndicator()
                    Spacer()
                    Button(action: { Task { await appState.stopAndProcess() } }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.green)
                    }.buttonStyle(.plain).help("Transcribe & send")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

            } else if appState.isProcessing {
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                    Text("Transcribing...").font(.callout).foregroundColor(.secondary)
                    Spacer()
                }.padding(.vertical, 10)

            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    // + Add file (left)
                    Menu {
                        Button(action: { pickFiles(types: ["public.image"]) }) {
                            Label("Image", systemImage: "photo")
                        }
                        Button(action: { pickFiles(types: ["com.adobe.pdf"]) }) {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                        Button(action: { pickFiles(types: ["net.daringfireball.markdown", "public.plain-text"]) }) {
                            Label("Markdown / Text", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24)).foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .help("Add file")

                    // Text input (center)
                    TextField("Paste AI response...", text: $pasteText, axis: .vertical)
                        .textFieldStyle(.plain).font(.body).lineLimit(1...4)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(10)

                    // Model/agent selector (left of mic)
                    Menu {
                        ForEach(appState.agents.filter { $0.parent.isEmpty }, id: \.id) { agent in
                            Button(agent.emoji + " " + agent.name) { appState.selectAgent(agent.id) }
                        }
                    } label: {
                        Image(systemName: "cpu").font(.system(size: 18)).foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("Switch agent")

                    // Mic or Send (right)
                    if pasteText.isEmpty && attachedFiles.isEmpty {
                        Button(action: { appState.startRecording() }) {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 28)).foregroundColor(.accentColor)
                        }.buttonStyle(.plain).help("Record voice")
                    } else {
                        Button(action: { sendAll() }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28)).foregroundColor(.orange)
                        }.buttonStyle(.plain).help("Send")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
    }

    func pickFiles(types: [String]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types.compactMap { .init($0) }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                let ext = url.pathExtension.lowercased()
                let icon = ["png","jpg","jpeg","gif","webp"].contains(ext) ? "photo" :
                           ext == "pdf" ? "doc.richtext" :
                           ["md","markdown"].contains(ext) ? "doc.text" : "doc"
                attachedFiles.append(AttachedFile(name: url.lastPathComponent, path: url.path, icon: icon))
            }
        }
    }

    func sendAll() {
        var text = pasteText
        for file in attachedFiles {
            if !text.isEmpty { text += "\n" }
            text += file.path
        }
        if !text.isEmpty {
            Task { await appState.saveText(text, role: .other) }
        }
        pasteText = ""
        attachedFiles = []
    }
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
    @Published var modelLabel = ""
    @Published var agents: [AgentInfo] = DEFAULT_AGENTS
    @Published var selectedAgent: String = "claude-code"
    @Published var totalRecordings = 0
    var previewFile: ((String) -> Void)?

    var selectedDateLabel: String {
        agents.first(where: { $0.id == selectedAgent })?.name ?? "VoxLog"
    }

    private let processManager = ProcessManager()
    private let hotkeyManager = HotkeyManager()
    private var audioEngine: AVAudioEngine?
    private var audioData = Data()
    private let sampleRate: Double = 16000
    private let token = "voxlog-dev-token"

    // MARK: - Lifecycle

    func start() async {
        do {
            try await processManager.startServer(); serverRunning = true
            for _ in 0..<15 {
                if let url = URL(string: "http://127.0.0.1:7890/health"),
                   let (_, r) = try? await URLSession.shared.data(from: url),
                   (r as? HTTPURLResponse)?.statusCode == 200 { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        } catch { lastError = "Server failed"; return }

        await detectEnv()
        await loadAgentCounts()
        await loadMessages(for: selectedAgent)

        if AXIsProcessTrusted() {
            hotkeyManager.onRecordStart = { [weak self] in Task { @MainActor in self?.startRecording() } }
            hotkeyManager.onRecordStop = { [weak self] in Task { @MainActor in await self?.stopAndProcess() } }
            hotkeyManager.register()
        }
    }

    func stop() {
        hotkeyManager.unregister()
        if let e = audioEngine { e.inputNode.removeTap(onBus: 0); e.stop() }
        processManager.stopServer()
    }

    // MARK: - Network

    func detectEnv() async {
        guard let url = URL(string: "http://127.0.0.1:7890/v1/detect") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let env = json["env"] as? String,
           let route = json["route"] as? [String: Any] {
            envLabel = env == "home" ? "Home" : "Office"
            let asr = (route["asr_main"] as? String ?? "").replacingOccurrences(of: "_", with: " ")
            let llm = (route["llm_main"] as? String ?? "").replacingOccurrences(of: "_", with: " ")
            modelLabel = "\(asr) · \(llm)"
        }
    }

    // MARK: - History

    func loadAgentCounts() async {
        guard let url = URL(string: "http://127.0.0.1:7890/v1/agents") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Update counts in existing agents
            for item in items {
                if let agentId = item["agent"] as? String,
                   let count = item["count"] as? Int {
                    if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                        agents[idx].count = count
                    }
                }
            }
        }
    }

    func selectAgent(_ agentId: String) {
        selectedAgent = agentId
        Task { await loadMessages(for: agentId) }
    }

    func loadMessages(for agentId: String) async {
        let encoded = agentId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? agentId
        guard let url = URL(string: "http://127.0.0.1:7890/v1/history/agent?agent=\(encoded)&limit=500") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            messages = items.reversed().compactMap { item in
                guard let text = item["polished_text"] as? String, !text.isEmpty,
                      let ts = item["created_at"] as? String else { return nil }
                let app = item["target_app"] as? String ?? ""
                let role: MessageRole = app.contains("paste") ? .other : .me
                return VoxMessage(
                    text: text, time: String(ts.dropFirst(11).prefix(5)),
                    role: role, latencyMs: item["latency_ms"] as? Int ?? 0
                )
            }
            totalRecordings = messages.count
        }
    }

    // MARK: - Recording

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
                DispatchQueue.main.async { self.audioData.append(Data(bytes: ch[0], count: Int(conv.frameLength) * 2)) }
            }
        }

        do { try engine.start(); audioEngine = engine; isRecording = true; lastError = nil }
        catch { lastError = "Mic: \(error.localizedDescription)" }
    }

    /// Transcribe audio but return text to input box (don't send to timeline)
    func transcribeOnly() async -> String? {
        guard isRecording, let engine = audioEngine else { return nil }
        engine.inputNode.removeTap(onBus: 0); engine.stop()
        audioEngine = nil; isRecording = false; isProcessing = true

        let wav = makeWav(from: audioData); audioData = Data()

        defer { isProcessing = false }

        do {
            let url = URL(string: "http://127.0.0.1:7890/v1/voice")!
            var req = URLRequest(url: url); req.httpMethod = "POST"
            let b = UUID().uuidString
            req.setValue("multipart/form-data; boundary=\(b)", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            var body = Data()
            body.append("--\(b)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"r.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(wav); body.append("\r\n".data(using: .utf8)!)
            for (k, v) in [("source","voice"),("env","auto"),("target_app","voice"),("agent",selectedAgent)] {
                body.append("--\(b)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
            }
            body.append("--\(b)--\r\n".data(using: .utf8)!)
            req.httpBody = body

            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            lastError = nil
            return json["polished_text"] as? String ?? json["raw_text"] as? String ?? ""
        } catch {
            lastError = "\(error.localizedDescription)"
            return nil
        }
    }

    func cancelRecording() {
        guard isRecording, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0); engine.stop()
        audioEngine = nil; isRecording = false; audioData = Data()
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
            for (k, v) in [("source","voice"),("env","auto"),("target_app","voice"),("agent",selectedAgent)] {
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
                appendMessage(text: text, role: .me, latency: latency)
            }
        } catch { lastError = "\(error.localizedDescription)" }
        isProcessing = false
    }

    // MARK: - Save Text (paste AI response)

    func saveText(_ text: String, role: MessageRole = .other) async {
        isProcessing = true
        do {
            let url = URL(string: "http://127.0.0.1:7890/v1/save")!
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            req.httpBody = "text=\(encoded)&source=paste&target_app=paste&agent=\(selectedAgent)".data(using: .utf8)

            let (_, _) = try await URLSession.shared.data(for: req)
            appendMessage(text: text, role: role, latency: 0)
        } catch { lastError = "\(error.localizedDescription)" }
        isProcessing = false
    }

    // MARK: - Obsidian Sync

    func syncToObsidian() {
        Task {
            let p = Process()
            let root = ProcessInfo.processInfo.environment["VOXLOG_ROOT"] ?? NSHomeDirectory() + "/voxlog"
            p.executableURL = URL(fileURLWithPath: root + "/.venv/bin/python")
            p.arguments = [root + "/export_cron.py"]
            p.currentDirectoryURL = URL(fileURLWithPath: root)
            try? p.run(); p.waitUntilExit()
        }
    }

    // MARK: - Helpers

    private func appendMessage(text: String, role: MessageRole, latency: Int) {
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        messages.append(VoxMessage(text: text, time: fmt.string(from: Date()), role: role, latencyMs: latency))
        totalRecordings += 1; lastError = nil
        // Update agent count
        if let idx = agents.firstIndex(where: { $0.id == selectedAgent }) {
            agents[idx].count += 1
        }
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
