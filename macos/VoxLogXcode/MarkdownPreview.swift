import SwiftUI
import AppKit

// MARK: - Markdown Preview Sidebar

struct MarkdownPreview: View {
    let filePath: String
    let onClose: () -> Void
    @State private var content = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                Text(fileName)
                    .font(.caption).fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Button(action: { copyPath() }) {
                    Image(systemName: "doc.on.doc").font(.caption)
                }.buttonStyle(.plain).foregroundColor(.secondary).help("Copy path")
                Button(action: { openInFinder() }) {
                    Image(systemName: "folder").font(.caption)
                }.buttonStyle(.plain).foregroundColor(.secondary).help("Open in Finder")
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.caption)
                }.buttonStyle(.plain).foregroundColor(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            Divider()

            // Full path
            Text(filePath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if content.isEmpty {
                Spacer()
                Text("File not found or empty")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    MarkdownText(content: content)
                        .padding(10)
                        .textSelection(.enabled)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .task { loadFile() }
        .onChange(of: filePath) { loadFile() }
    }

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    func loadFile() {
        isLoading = true
        let expanded = (filePath as NSString).expandingTildeInPath
        if let text = try? String(contentsOfFile: expanded, encoding: .utf8) {
            content = text
        } else {
            content = ""
        }
        isLoading = false
    }

    func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filePath, forType: .string)
    }

    func openInFinder() {
        let expanded = (filePath as NSString).expandingTildeInPath
        NSWorkspace.shared.selectFile(expanded, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Simple Markdown Renderer

struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(content.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                let str = String(line)
                if str.hasPrefix("# ") {
                    Text(str.dropFirst(2)).font(.title2).fontWeight(.bold).padding(.top, 8)
                } else if str.hasPrefix("## ") {
                    Text(str.dropFirst(3)).font(.title3).fontWeight(.semibold).padding(.top, 6)
                } else if str.hasPrefix("### ") {
                    Text(str.dropFirst(4)).font(.headline).padding(.top, 4)
                } else if str.hasPrefix("---") {
                    Divider()
                } else if str.hasPrefix("> ") {
                    Text(str.dropFirst(2))
                        .font(.callout).italic().foregroundColor(.secondary)
                        .padding(.leading, 8)
                        .overlay(Rectangle().fill(Color.accentColor.opacity(0.3)).frame(width: 3), alignment: .leading)
                } else if str.hasPrefix("- ") || str.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 4) {
                        Text("•").foregroundColor(.secondary)
                        Text(str.dropFirst(2)).font(.body)
                    }
                } else if str.hasPrefix("```") {
                    // Skip code fence markers
                } else if str.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    Text(str).font(.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - File Path Detection

func extractFilePaths(from text: String) -> [String] {
    // Match file paths: .md, .pdf, .png, .jpg, .jpeg, .gif, .txt
    let exts = "md|pdf|png|jpg|jpeg|gif|webp|heic|txt"
    let patterns = [
        "~[/\\w.-]+\\.(?:\(exts))",
        "/Users/[/\\w.-]+\\.(?:\(exts))",
        "/[\\w.-]+(?:/[\\w.-]+)+\\.(?:\(exts))",
    ]

    var paths: [String] = []
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    paths.append(String(text[range]))
                }
            }
        }
    }
    return Array(Set(paths)) // deduplicate
}
