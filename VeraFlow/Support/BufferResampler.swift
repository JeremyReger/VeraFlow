import AVFAudio
import Foundation

/// Converts PCM buffers (any rate/channel count) to a target format, one buffer at a time.
/// Used by the recorder's tap and by the transcriber's file reader; one owner per instance.
final class BufferResampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    init(converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        self.converter = converter
        self.outputFormat = outputFormat
        self.ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
    }

    /// Drains what the converter still holds after the last `convert`; call once at the end.
    func flush() -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else { return nil }
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return output.frameLength > 0 ? output : nil
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let pending = PendingInput(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if let buffer = pending.take() {
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        switch status {
        case .haveData, .inputRanDry:
            return output.frameLength > 0 ? output : nil
        case .endOfStream, .error:
            return nil
        @unknown default:
            return nil
        }
    }
}

/// Hands one input buffer to an `AVAudioConverter` input block exactly once. The block is
/// `@Sendable`, so the buffer travels in this box; it is only touched on the render thread.
final class PendingInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
