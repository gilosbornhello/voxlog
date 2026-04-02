import Foundation

/// Manages the VoxLog Python server subprocess.
/// Spawns on app launch, health-checks every 5s, auto-restarts up to 3 times.
final class ProcessManager: @unchecked Sendable {
    private var process: Process?
    private var healthTimer: Timer?
    private var restartCount = 0
    private let maxRestarts = 3
    private let healthCheckInterval: TimeInterval = 5.0

    /// Path to the Python executable (in venv or system).
    private var pythonPath: String {
        // Look for venv first, then system python
        let venvPython = projectRoot + "/.venv/bin/python"
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        // Fallback to system python3
        return "/opt/homebrew/bin/python3"
    }

    private var projectRoot: String {
        if let envRoot = ProcessInfo.processInfo.environment["VOXLOG_ROOT"] {
            return envRoot
        }
        // Default: assume voxlog is in home directory
        return NSHomeDirectory() + "/voxlog"
    }

    func startServer() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "uvicorn", "server.app:app",
                             "--host", "127.0.0.1", "--port", "7890",
                             "--log-level", "info"]
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = projectRoot
        process.environment = env

        // Pipe stdout/stderr for debugging
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Log output asynchronously
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                print("[VoxLog Python] \(str)", terminator: "")
            }
        }

        process.terminationHandler = { [weak self] proc in
            print("[VoxLog] Python server exited with code \(proc.terminationStatus)")
            DispatchQueue.main.async {
                self?.handleTermination()
            }
        }

        try process.run()
        self.process = process
        restartCount = 0
        print("[VoxLog] Python server started (PID: \(process.processIdentifier))")

        // Start health check timer
        startHealthCheck()
    }

    func stopServer() {
        healthTimer?.invalidate()
        healthTimer = nil

        if let process = process, process.isRunning {
            process.terminate()
            // Give it 2 seconds to clean up
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    process.interrupt() // SIGINT
                }
            }
        }
        process = nil
        print("[VoxLog] Python server stopped")
    }

    private func startHealthCheck() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }

    private func checkHealth() {
        guard let process = process, process.isRunning else { return }

        let url = URL(string: "http://127.0.0.1:7890/health")!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("[VoxLog] Health check failed: \(error.localizedDescription)")
            }
        }
        task.resume()
    }

    private func handleTermination() {
        guard restartCount < maxRestarts else {
            print("[VoxLog] Max restarts reached (\(maxRestarts)). Giving up.")
            return
        }

        restartCount += 1
        let delay = Double(restartCount) * 2.0 // Exponential-ish backoff: 2s, 4s, 6s
        print("[VoxLog] Restarting in \(delay)s (attempt \(restartCount)/\(maxRestarts))...")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task {
                try? await self?.startServer()
            }
        }
    }
}
