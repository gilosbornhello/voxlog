import Foundation

final class ProcessManager: @unchecked Sendable {
    private var process: Process?
    private var restartCount = 0

    private var pythonPath: String {
        let venv = NSHomeDirectory() + "/voxlog/.venv/bin/python"
        if FileManager.default.fileExists(atPath: venv) { return venv }
        return "/opt/homebrew/bin/python3"
    }

    private var projectRoot: String {
        if let env = ProcessInfo.processInfo.environment["VOXLOG_ROOT"] { return env }
        return NSHomeDirectory() + "/voxlog"
    }

    func startServer() async throws {
        // Check if already running
        if await isServerRunning() {
            print("[VoxLog] Server already running")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments = ["-m", "uvicorn", "server.app:app", "--host", "127.0.0.1", "--port", "7890", "--log-level", "info"]
        p.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = projectRoot
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            if let str = String(data: handle.availableData, encoding: .utf8), !str.isEmpty {
                print("[VoxLog Server] \(str)", terminator: "")
            }
        }

        try p.run()
        process = p
        print("[VoxLog] Server started PID \(p.processIdentifier)")
    }

    func stopServer() {
        process?.terminate()
        process = nil
    }

    private func isServerRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:7890/health") else { return false }
        do {
            let (_, resp) = try await URLSession.shared.data(from: url)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}
