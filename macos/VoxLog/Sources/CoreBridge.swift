import Foundation

/// HTTP bridge to the VoxLog Python server running on localhost.
final class CoreBridge {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    struct VoiceResponse: Codable {
        let id: String
        let rawText: String
        let polishedText: String
        let asrProvider: String
        let llmProvider: String?
        let polished: Bool
        let durationSeconds: Double
        let latencyMs: Int
        let targetApp: String
        let env: String

        enum CodingKeys: String, CodingKey {
            case id
            case rawText = "raw_text"
            case polishedText = "polished_text"
            case asrProvider = "asr_provider"
            case llmProvider = "llm_provider"
            case polished
            case durationSeconds = "duration_seconds"
            case latencyMs = "latency_ms"
            case targetApp = "target_app"
            case env
        }
    }

    init(port: Int = 7890, token: String = "") {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Wait for the Python server to be ready.
    func waitForHealth(maxRetries: Int = 10, delayMs: Int = 500) async throws {
        for i in 0..<maxRetries {
            do {
                let url = baseURL.appendingPathComponent("health")
                let (_, response) = try await session.data(from: url)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    print("[VoxLog] Server healthy after \(i + 1) attempts")
                    return
                }
            } catch {
                // Server not ready yet
            }
            try await Task.sleep(for: .milliseconds(delayMs))
        }
        throw BridgeError.serverNotReady
    }

    /// Send audio to /v1/voice and get polished text back.
    func voice(audio: Data, env: VoxEnvironment, targetApp: String) async throws -> VoiceResponse {
        let url = baseURL.appendingPathComponent("v1/voice")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Audio file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)

        // Form fields
        for (key, value) in [("source", "macos"), ("env", env.rawValue), ("target_app", targetApp)] {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw BridgeError.invalidResponse
        }

        switch httpResp.statusCode {
        case 200:
            return try JSONDecoder().decode(VoiceResponse.self, from: data)
        case 401:
            throw BridgeError.unauthorized
        case 413:
            throw BridgeError.audioTooLong
        case 422:
            throw BridgeError.invalidFormat
        case 502:
            throw BridgeError.asrFailed
        default:
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw BridgeError.serverError(httpResp.statusCode, body)
        }
    }
}

enum BridgeError: LocalizedError {
    case serverNotReady
    case invalidResponse
    case unauthorized
    case audioTooLong
    case invalidFormat
    case asrFailed
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .serverNotReady: return "VoxLog server not responding. Check Python process."
        case .invalidResponse: return "Invalid server response."
        case .unauthorized: return "Authentication failed. Check API token."
        case .audioTooLong: return "Recording too long (max 60s)."
        case .invalidFormat: return "Unsupported audio format."
        case .asrFailed: return "Speech recognition failed. Both providers down."
        case .serverError(let code, let body): return "Server error \(code): \(body)"
        }
    }
}
