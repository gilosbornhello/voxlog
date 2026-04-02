import SwiftUI
import AppKit

struct DictionaryEditor: View {
    @EnvironmentObject var appState: AppState
    @State private var corrections: [(wrong: String, right: String)] = []
    @State private var newWrong = ""
    @State private var newRight = ""
    @State private var isLoading = true
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "character.book.closed")
                Text("Personal Dictionary")
                    .font(.headline)
                Spacer()
                Text("\(corrections.count) terms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Add new term
            HStack(spacing: 8) {
                TextField("Wrong (e.g. osborne)", text: $newWrong)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                TextField("Correct (e.g. OSBORN)", text: $newRight)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addTerm() }
                    .disabled(newWrong.isEmpty || newRight.isEmpty)
            }
            .padding(.horizontal).padding(.vertical, 8)

            Divider()

            // Term list
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                List {
                    ForEach(Array(corrections.enumerated()), id: \.offset) { idx, item in
                        HStack {
                            Text(item.wrong)
                                .foregroundColor(.red.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(item.right)
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(action: { deleteTerm(item.wrong) }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Status
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .task { await loadDictionary() }
    }

    func loadDictionary() async {
        isLoading = true
        guard let url = URL(string: "http://127.0.0.1:7890/v1/dictionary") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")

        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let corr = json["corrections"] as? [String: String] {
            corrections = corr.map { (wrong: $0.key, right: $0.value) }
                .sorted { $0.wrong.lowercased() < $1.wrong.lowercased() }
        }
        isLoading = false
    }

    func addTerm() {
        guard !newWrong.isEmpty, !newRight.isEmpty else { return }
        Task {
            guard let url = URL(string: "http://127.0.0.1:7890/v1/dictionary") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["action": "add", "wrong": newWrong, "right": newRight]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)

            statusMessage = "Added: \(newWrong) → \(newRight)"
            newWrong = ""; newRight = ""
            await loadDictionary()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = "" }
        }
    }

    func deleteTerm(_ wrong: String) {
        Task {
            guard let url = URL(string: "http://127.0.0.1:7890/v1/dictionary") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer voxlog-dev-token", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "delete", "wrong": wrong])
            _ = try? await URLSession.shared.data(for: req)

            statusMessage = "Deleted: \(wrong)"
            await loadDictionary()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = "" }
        }
    }
}
