import Foundation
import Speech
import AVFoundation

/// Production transcription service using Apple SpeechAnalyzer + SpeechTranscriber (§9)
public final class SpeechTranscriptionService: TranscriptionServiceProtocol, Sendable {
    private let paragraphingService: ParagraphingService
    
    public init(paragraphingService: ParagraphingService = ParagraphingService()) {
        self.paragraphingService = paragraphingService
    }
    
    public func isAvailable() async -> Bool {
        return SpeechTranscriber.isAvailable
    }
    
    public func checkAndRequestAssets(locale: Locale) async throws -> Bool {
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return true
    }
    
    public func transcribeAudio(
        fileURL: URL,
        locale: Locale,
        progress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> TranscriptionResult {
        // 1. Verify audio file
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.fileNotFound
        }
        
        let audioFile = try AVAudioFile(forReading: fileURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let fileDuration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
        
        // 2. Resolve engine and locale (§9.1)
        let isPrimaryAvailable = SpeechTranscriber.isAvailable
        let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let engineName: String
        
        var words: [TimedWord] = []
        
        if isPrimaryAvailable {
            engineName = "SpeechTranscriber (\(resolvedLocale.identifier))"
            
            // Check & install speech assets if needed
            _ = try? await checkAndRequestAssets(locale: resolvedLocale)
            
            let transcriber = SpeechTranscriber(
                locale: resolvedLocale,
                preset: .transcription
            )
            
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            
            // Start collecting results before starting file pass
            let collectorTask = Task { () -> [TimedWord] in
                var collected: [TimedWord] = []
                do {
                    for try await result in transcriber.results {
                        let attr = result.text
                        for run in attr.runs {
                            let wordText = String(attr.characters[run.range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !wordText.isEmpty else { continue }
                            
                            if let range = run.audioTimeRange {
                                let start = CMTimeGetSeconds(range.start)
                                let duration = CMTimeGetSeconds(range.duration)
                                let end = start + duration
                                collected.append(TimedWord(text: wordText, start: start, end: end))
                                
                                if fileDuration > 0 {
                                    let fraction = min(1.0, end / fileDuration)
                                    progress?(TranscriptionProgress(
                                        fractionCompleted: fraction,
                                        currentTime: end,
                                        totalDuration: fileDuration
                                    ))
                                }
                            }
                        }
                    }
                } catch {}
                return collected
            }
            
            // Feed file sequence into analyzer (§9.2)
            if let lastTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastTime)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            
            words = await collectorTask.value
        } else {
            // Fallback to DictationTranscriber (§9.1)
            engineName = "DictationTranscriber (\(resolvedLocale.identifier))"
            let dictationTranscriber = DictationTranscriber(locale: resolvedLocale, preset: .timeIndexedLongDictation)
            let analyzer = SpeechAnalyzer(modules: [dictationTranscriber])
            
            let collectorTask = Task { () -> [TimedWord] in
                var collected: [TimedWord] = []
                do {
                    for try await result in dictationTranscriber.results {
                        let attr = result.text
                        for run in attr.runs {
                            let wordText = String(attr.characters[run.range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !wordText.isEmpty else { continue }
                            if let range = run.audioTimeRange {
                                let start = CMTimeGetSeconds(range.start)
                                let dur = CMTimeGetSeconds(range.duration)
                                collected.append(TimedWord(text: wordText, start: start, end: start + dur))
                            }
                        }
                    }
                } catch {}
                return collected
            }
            
            if let lastTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastTime)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            
            words = await collectorTask.value
        }
        
        progress?(TranscriptionProgress(fractionCompleted: 1.0, currentTime: fileDuration, totalDuration: fileDuration))
        
        // 3. Build provisional segments from timed words (§9.3)
        let segments = paragraphingService.buildSegments(from: words)
        
        return TranscriptionResult(
            words: words,
            segments: segments,
            engineUsed: engineName
        )
    }
}

public enum TranscriptionError: LocalizedError, Sendable {
    case fileNotFound
    case analysisFailed(String)
    case unsupportedLocale(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound: "The audio file to transcribe could not be found."
        case .analysisFailed(let msg): "Speech analysis failed: \(msg)"
        case .unsupportedLocale(let id): "The language locale '\(id)' is not supported for on-device transcription."
        }
    }
}
