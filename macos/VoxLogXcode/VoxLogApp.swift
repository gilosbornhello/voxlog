import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

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

enum MessageContent {
    case text(String)
    case image(String)  // file path to image
    case file(String)   // file path to document
}

struct VoxMessage: Identifiable {
    let id: String
    let text: String
    let time: String
    let role: MessageRole
    let latencyMs: Int
    let createdAt: Date
    var attachments: [MessageAttachment] = []
}

struct MessageAttachment: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let type: AttachmentType

    enum AttachmentType { case image, pdf, markdown, other }

    static func detect(path: String) -> MessageAttachment {
        let ext = (path as NSString).pathExtension.lowercased()
        let name = (path as NSString).lastPathComponent
        let type: AttachmentType = ["png","jpg","jpeg","gif","webp","heic"].contains(ext) ? .image :
                                   ext == "pdf" ? .pdf :
                                   ["md","markdown"].contains(ext) ? .markdown : .other
        return MessageAttachment(path: path, name: name, type: type)
    }
}

// MARK: - Main Layout

struct MainLayout: View {
    @EnvironmentObject var appState: AppState
    @State private var showSidebar = true
    @State private var showPreview = false
    @State private var previewPath = ""
    @State private var showSearchSheet = false

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

                    // Three-dot menu
                    Menu {
                        Button(action: { showSearchSheet = true }) {
                            Label("Search...", systemImage: "magnifyingglass")
                        }
                        Divider()
                        Menu("Status") {
                            Text("Server: \(appState.serverRunning ? "Running" : "Off")")
                            Text("Env: \(appState.envLabel)")
                            Text("ASR: \(appState.currentASRLabel)")
                            Text("Model: \(appState.modelLabel)")
                        }
                        Divider()
                        Button(action: { NSApp.sendAction(#selector(AppDelegate.openDictionary), to: nil, from: nil) }) {
                            Label("Dictionary", systemImage: "character.book.closed")
                        }
                        Button(action: { NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil) }) {
                            Label("Settings", systemImage: "gear")
                        }
                        Button(action: { appState.syncToObsidian() }) {
                            Label("Sync Obsidian", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 16)).foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)

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

struct AgentInfo: Identifiable, Hashable, Equatable, Codable {
    var id: String
    var name: String
    var icon: String
    var emoji: String
    var parent: String  // empty = top level
    var count: Int = 0
    var lastActive: String = ""
}

// MARK: - Agent Persistence

struct AgentStore {
    static let path = NSHomeDirectory() + "/.voxlog/agents.json"

    static func load() -> [AgentInfo] {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let agents = try? JSONDecoder().decode([AgentInfo].self, from: data),
           !agents.isEmpty {
            return agents
        }
        // First time — use defaults and save
        save(DEFAULT_AGENTS)
        return DEFAULT_AGENTS
    }

    static func save(_ agents: [AgentInfo]) {
        let dir = NSHomeDirectory() + "/.voxlog"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(agents) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
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
    @State private var showAddAgent = false
    @State private var newAgentName = ""
    @State private var newAgentEmoji = "🤖"
    @State private var draggingAgent: AgentInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with + button
            HStack {
                Text("Agents").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                Spacer()
                Button(action: { showAddAgent.toggle() }) {
                    Image(systemName: "plus").font(.caption).foregroundColor(.secondary)
                }.buttonStyle(.plain).help("Add agent")
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            // Add agent inline form
            if showAddAgent {
                HStack(spacing: 4) {
                    TextField("🤖", text: $newAgentEmoji)
                        .textFieldStyle(.roundedBorder).frame(width: 36)
                    TextField("Name", text: $newAgentName)
                        .textFieldStyle(.roundedBorder).font(.caption)
                    Button("Add") { addAgent() }
                        .controlSize(.small).disabled(newAgentName.isEmpty)
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(topLevelAgents) { agent in
                        AgentRow(agent: agent, isSelected: agent.id == appState.selectedAgent)
                            .onTapGesture { appState.selectAgent(agent.id) }
                            .onDrag {
                                draggingAgent = agent
                                return NSItemProvider(object: agent.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: AgentDropDelegate(
                                item: agent, agents: $appState.agents, dragging: $draggingAgent
                            ))

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

    func addAgent() {
        let id = newAgentName.lowercased().replacingOccurrences(of: " ", with: "-")
        let emoji = newAgentEmoji.isEmpty ? "🤖" : String(newAgentEmoji.prefix(2))
        appState.agents.append(AgentInfo(id: id, name: newAgentName, icon: "person", emoji: emoji, parent: ""))
        AgentStore.save(appState.agents)
        newAgentName = ""
        newAgentEmoji = "🤖"
        showAddAgent = false
    }

    var topLevelAgents: [AgentInfo] {
        appState.agents.filter { $0.parent.isEmpty }
    }

    func subAgents(for parentId: String) -> [AgentInfo] {
        appState.agents.filter { $0.parent == parentId }
    }
}

// MARK: - Drag & Drop Reorder

struct AgentDropDelegate: DropDelegate {
    let item: AgentInfo
    @Binding var agents: [AgentInfo]
    @Binding var dragging: AgentInfo?

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        AgentStore.save(agents)
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = dragging, dragging.id != item.id,
              // Only reorder top-level agents
              dragging.parent.isEmpty && item.parent.isEmpty else { return }

        guard let fromIdx = agents.firstIndex(where: { $0.id == dragging.id }),
              let toIdx = agents.firstIndex(where: { $0.id == item.id }) else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            agents.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
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
    @State private var showForwardPicker = false
    @State private var forwardingMessage: VoxMessage?
    @State private var showBatchForward = false
    var body: some View {
        VStack(spacing: 0) {
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
                            HStack(spacing: 6) {
                                // Multi-select checkbox
                                if appState.isMultiSelectMode {
                                    Button(action: { appState.toggleMessageSelection(msg.id) }) {
                                        Image(systemName: appState.selectedMessageIds.contains(msg.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(appState.selectedMessageIds.contains(msg.id) ? .accentColor : .secondary.opacity(0.4))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.leading, 4)
                                }

                                ChatBubble(message: msg, onFileTap: onFileTap, onRecall: {
                                    Task { await appState.recallMessage(msg.id) }
                                }, onForward: {
                                    forwardingMessage = msg
                                    showForwardPicker = true
                                })
                            }
                            .id(msg.id)
                            .onLongPressGesture {
                                if !appState.isMultiSelectMode {
                                    appState.isMultiSelectMode = true
                                    appState.toggleMessageSelection(msg.id)
                                }
                            }
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
        .sheet(isPresented: $showForwardPicker) {
            ForwardPicker(agents: appState.agents) { targetAgent in
                if let msg = forwardingMessage {
                    Task { await appState.forwardMessage(msg, to: targetAgent) }
                }
                showForwardPicker = false
            }
        }
        .sheet(isPresented: $showBatchForward) {
            ForwardPicker(agents: appState.agents) { targetAgent in
                Task { await appState.forwardSelected(to: targetAgent) }
                showBatchForward = false
            }
        }

        // Multi-select bottom bar
        if appState.isMultiSelectMode {
            Divider()
            HStack {
                Button("Cancel") { appState.toggleMultiSelect() }
                    .controlSize(.small)
                Spacer()
                Text("\(appState.selectedMessageIds.count) selected")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Forward") { showBatchForward = true }
                    .controlSize(.small)
                    .disabled(appState.selectedMessageIds.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        } // close VStack
    }
}

// MARK: - Forward Picker

struct ForwardPicker: View {
    let agents: [AgentInfo]
    let onPick: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Forward to").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.controlSize(.small)
            }.padding()

            Divider()

            List {
                ForEach(agents, id: \.id) { agent in
                    Button(action: { onPick(agent.id) }) {
                        HStack(spacing: 8) {
                            Text(agent.emoji)
                                .font(.system(size: 20))
                                .frame(width: 32, height: 32)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(8)
                            VStack(alignment: .leading) {
                                Text(agent.name).font(.callout)
                                if !agent.parent.isEmpty {
                                    Text(agent.parent).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 280, height: 350)
    }
}

// MARK: - Chat Bubble (right = me, left = other)

struct ChatBubble: View {
    let message: VoxMessage
    var onFileTap: ((String) -> Void)?
    var onRecall: (() -> Void)?
    var onForward: (() -> Void)?
    @State private var isHovered = false
    @State private var copied = false
    @State private var forwarded = false

    var canRecall: Bool {
        Date().timeIntervalSince(message.createdAt) < 120
    }

    var filePaths: [String] { extractFilePaths(from: message.text) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .me { Spacer(minLength: 60) }

            VStack(alignment: message.role == .me ? .trailing : .leading, spacing: 3) {
                ZStack(alignment: message.role == .me ? .topTrailing : .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Text content (hide if only attachments)
                        let cleanText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let isOnlyPaths = filePaths.count > 0 && filePaths.allSatisfy { cleanText.contains($0) } &&
                            cleanText.split(separator: "\n").allSatisfy { line in
                                let l = line.trimmingCharacters(in: .whitespaces)
                                return l.hasPrefix("/") || l.hasPrefix("~") || l.isEmpty
                            }

                        if !isOnlyPaths && !cleanText.isEmpty {
                            Text(message.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        // Image thumbnails
                        ForEach(message.attachments.filter { $0.type == .image }, id: \.id) { att in
                            let expanded = (att.path as NSString).expandingTildeInPath
                            if let nsImage = NSImage(contentsOfFile: expanded) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .cornerRadius(8)
                                    .onTapGesture { onFileTap?(att.path) }
                            }
                        }

                        // File links (non-image)
                        ForEach(filePaths, id: \.self) { path in
                            let ext = (path as NSString).pathExtension.lowercased()
                            if !["png","jpg","jpeg","gif","webp","heic"].contains(ext) {
                                Button(action: { onFileTap?(path) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: ext == "pdf" ? "doc.richtext.fill" : "doc.text.fill").font(.caption2)
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
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(message.role == .me ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
                    .cornerRadius(16)

                    // Hover action buttons
                    if isHovered {
                        HStack(spacing: 2) {
                            // Forward (left)
                            Button(action: { onForward?() }) {
                                Image(systemName: forwarded ? "checkmark" : "arrowshape.turn.up.right")
                                    .font(.caption2)
                                    .foregroundColor(forwarded ? .green : .secondary)
                            }.buttonStyle(.plain).help("Forward")

                            // Copy (right)
                            Button(action: { copyText() }) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundColor(copied ? .green : .secondary)
                            }.buttonStyle(.plain).help("Copy")

                            // Recall (if within 2 min)
                            if canRecall {
                                Button(action: { onRecall?() }) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.caption2)
                                        .foregroundColor(.red.opacity(0.6))
                                }.buttonStyle(.plain).help("Recall")
                            }
                        }
                        .padding(3)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
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
                    Button(action: { pickAnyFile() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add files or photos")

                    // Text input (center)
                    TextField("Paste AI response...", text: $pasteText, axis: .vertical)
                        .textFieldStyle(.plain).font(.body).lineLimit(1...4)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(10)
                        .onChange(of: pasteText) { detectFilePath() }
                        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                            handleDrop(providers)
                            return true
                        }

                    // ASR model selector (left of mic)
                    Menu {
                        Text("Speech Recognition").font(.caption)
                        Button("🇺🇸 Qwen ASR (US) — qwen3-asr-flash-us") { appState.switchASR("qwen-us") }
                        Button("🇨🇳 Qwen ASR (CN) — qwen3-asr-flash") { appState.switchASR("qwen-cn") }
                        Button("🌐 OpenAI Whisper — whisper-1") { appState.switchASR("openai") }
                        Button("🇨🇳 SiliconFlow — SenseVoiceSmall") { appState.switchASR("siliconflow") }
                        Divider()
                        Text("Current: \(appState.currentASRLabel)").font(.caption)
                    } label: {
                        Text(appState.currentASRShort)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(minWidth: 40)
                    .help("Switch ASR model")

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

    func pasteFilePath() {
        guard let str = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return }

        // Expand ~ and check if it looks like a file path
        let expanded = (str as NSString).expandingTildeInPath
        let path = str.hasPrefix("/") || str.hasPrefix("~") ? str : expanded

        if FileManager.default.fileExists(atPath: expanded) {
            let ext = (expanded as NSString).pathExtension.lowercased()
            let icon = ["png","jpg","jpeg","gif","webp"].contains(ext) ? "photo" :
                       ext == "pdf" ? "doc.richtext" :
                       ["md","markdown"].contains(ext) ? "doc.text" : "doc"
            attachedFiles.append(AttachedFile(name: (path as NSString).lastPathComponent, path: path, icon: icon))
        } else {
            // Even if file not found locally, still attach (might be on another machine)
            attachedFiles.append(AttachedFile(name: (path as NSString).lastPathComponent, path: path, icon: "doc.text"))
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    let icon = ["png","jpg","jpeg","gif","webp","heic"].contains(ext) ? "photo" :
                               ext == "pdf" ? "doc.richtext" :
                               ["md","markdown","txt"].contains(ext) ? "doc.text" : "doc"
                    DispatchQueue.main.async {
                        attachedFiles.append(AttachedFile(name: url.lastPathComponent, path: url.path, icon: icon))
                    }
                }
            }
        }
    }

    func detectFilePath() {
        let text = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (text.hasPrefix("~/") || text.hasPrefix("/")), !text.contains("\n") else { return }
        let knownExts = ["md","pdf","png","jpg","jpeg","gif","webp","heic","txt"]
        let ext = (text as NSString).pathExtension.lowercased()
        guard knownExts.contains(ext) else { return }

        let expanded = (text as NSString).expandingTildeInPath
        let icon = ["png","jpg","jpeg","gif","webp","heic"].contains(ext) ? "photo" :
                   ext == "pdf" ? "doc.richtext" : "doc.text"
        attachedFiles.append(AttachedFile(name: (text as NSString).lastPathComponent, path: text, icon: icon))
        pasteText = ""
    }

    func pickAnyFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Add files or photos"
        if panel.runModal() == .OK {
            for url in panel.urls {
                let ext = url.pathExtension.lowercased()
                let icon = ["png","jpg","jpeg","gif","webp","heic"].contains(ext) ? "photo" :
                           ext == "pdf" ? "doc.richtext" :
                           ["md","markdown","txt"].contains(ext) ? "doc.text" : "doc"
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
    @Published var agents: [AgentInfo] = AgentStore.load()
    @Published var selectedAgent: String = "claude-code"
    @Published var totalRecordings = 0
    @Published var currentASRLabel = "Qwen ASR (US)"
    @Published var currentASRShort = "Qwen US"
    @Published var isMultiSelectMode = false
    @Published var selectedMessageIds: Set<String> = []
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
                let recordId = item["id"] as? String ?? UUID().uuidString
                let isoFmt = ISO8601DateFormatter()
                let createdAt = isoFmt.date(from: ts) ?? Date.distantPast
                let attachments = extractFilePaths(from: text).map { MessageAttachment.detect(path: $0) }
                return VoxMessage(
                    id: recordId, text: text, time: String(ts.dropFirst(11).prefix(5)),
                    role: role, latencyMs: item["latency_ms"] as? Int ?? 0,
                    createdAt: createdAt, attachments: attachments
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

    // MARK: - Recall Message

    func recallMessage(_ id: String) async {
        // Delete from server
        guard let url = URL(string: "http://127.0.0.1:7890/v1/history/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)

        // Remove from local list
        messages.removeAll { $0.id == id }
    }

    // MARK: - Multi-Select

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode { selectedMessageIds.removeAll() }
    }

    func toggleMessageSelection(_ id: String) {
        if selectedMessageIds.contains(id) {
            selectedMessageIds.remove(id)
        } else if selectedMessageIds.count < 50 {
            selectedMessageIds.insert(id)
        }
    }

    func forwardSelected(to targetAgent: String) async {
        let selected = messages.filter { selectedMessageIds.contains($0.id) }
        let combined = selected.map { "[\($0.time)] \($0.text)" }.joined(separator: "\n\n")
        let text = "[Forwarded \(selected.count) messages]\n\n" + combined

        let url = URL(string: "http://127.0.0.1:7890/v1/save")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        req.httpBody = "text=\(encoded)&source=forward&target_app=forward&agent=\(targetAgent)".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)

        isMultiSelectMode = false
        selectedMessageIds.removeAll()
    }

    // MARK: - Forward Message

    func forwardMessage(_ msg: VoxMessage, to targetAgent: String) async {
        // Save a copy of the message to the target agent
        let text = "[Forwarded] " + msg.text
        let url = URL(string: "http://127.0.0.1:7890/v1/save")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        req.httpBody = "text=\(encoded)&source=forward&target_app=forward&agent=\(targetAgent)".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - ASR Model Switch

    func switchASR(_ model: String) {
        let labels: [String: (String, String)] = [
            "qwen-us": ("Qwen ASR (US) — qwen3-asr-flash-us", "Qwen US"),
            "qwen-cn": ("Qwen ASR (CN) — qwen3-asr-flash", "Qwen CN"),
            "openai": ("OpenAI Whisper — whisper-1", "Whisper"),
            "siliconflow": ("SiliconFlow — SenseVoiceSmall", "SenseVoice"),
        ]
        if let (full, short) = labels[model] {
            currentASRLabel = full
            currentASRShort = short
        }
        // TODO: send to server to actually switch the ASR provider at runtime
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
        let attachments = extractFilePaths(from: text).map { MessageAttachment.detect(path: $0) }
        messages.append(VoxMessage(id: UUID().uuidString, text: text, time: fmt.string(from: Date()), role: role, latencyMs: latency, createdAt: Date(), attachments: attachments))
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
