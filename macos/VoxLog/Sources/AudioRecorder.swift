import AVFoundation
import Foundation

/// Records audio via AVAudioEngine, outputs WAV 16kHz mono PCM.
/// No ffmpeg needed — records directly in the ASR-optimal format.
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioData = Data()
    private var isRecording = false
    private let sampleRate: Double = 16000.0
    private let maxSeconds: Double = 60.0

    /// Start recording. Throws if microphone permission denied.
    func start() throws {
        guard !isRecording else { return }

        // Request microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw RecorderError.permissionRequired
        default:
            throw RecorderError.permissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.formatError
        }

        audioData = Data()
        let maxBytes = Int(sampleRate * 2 * maxSeconds) // 16-bit = 2 bytes per sample

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert to target format
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let channelData = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * 2
                let data = Data(bytes: channelData[0], count: byteCount)
                self.audioData.append(data)

                // Hard limit: stop if exceeding max duration
                if self.audioData.count >= maxBytes {
                    print("[VoxLog] Max recording duration reached (\(self.maxSeconds)s)")
                    // Will be handled by the caller
                }
            }
        }

        try engine.start()
        self.engine = engine
        isRecording = true
        print("[VoxLog] Recording started (16kHz mono PCM)")
    }

    /// Stop recording and return WAV data.
    func stop() throws -> Data {
        guard isRecording, let engine = engine else {
            throw RecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isRecording = false

        let wavData = makeWav(from: audioData)
        let duration = Double(audioData.count) / (sampleRate * 2)
        print("[VoxLog] Recording stopped: \(String(format: "%.1f", duration))s")

        audioData = Data()
        return wavData
    }

    func stopIfNeeded() {
        if isRecording {
            _ = try? stop()
        }
    }

    /// Wrap raw PCM data in a WAV header.
    private func makeWav(from pcmData: Data) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateInt = UInt32(sampleRate)
        let byteRate = sampleRateInt * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var header = Data(capacity: 44)
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // subchunk1 size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)

        return header
    }
}

enum RecorderError: LocalizedError {
    case permissionRequired
    case permissionDenied
    case formatError
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionRequired: return "Microphone permission required. Check System Settings > Privacy > Microphone."
        case .permissionDenied: return "Microphone access denied. Enable in System Settings > Privacy > Microphone."
        case .formatError: return "Audio format initialization failed."
        case .notRecording: return "Not currently recording."
        }
    }
}
