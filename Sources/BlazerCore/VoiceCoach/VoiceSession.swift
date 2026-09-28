import Foundation
#if canImport(Speech)
import Speech
import AVFoundation

/// Manages a single ask-and-answer voice exchange for the coach.
///
/// STT: `SFSpeechRecognizer` with on-device recognition preferred.
/// TTS: `AVSpeechSynthesizer` with the system voice.
///
/// Rules:
/// - A live quote is never an input.
/// - The session does not score or choose a side.
/// - The same question about the same seal always returns the same sealed card
///   when the on-device model is unavailable.
@MainActor
public final class VoiceSession: NSObject, ObservableObject {
    public enum State: Equatable, Sendable {
        case idle
        case requestingPermission
        case listening
        case thinking
        case speaking(text: String)
        case denied                 // mic or speech recognition denied
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var transcript: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Ask the coach a spoken question about a sealed scan.
    /// `seal` — frozen fingerprint, score, and side only.
    /// `evidence` — the engine's plain-text rationale from the journal entry.
    /// `service` — the coach; no live quote ever enters this call.
    public func start(seal: ParitySeal, evidence: String, using service: FoundationCoachService) {
        guard state == .idle || state == .denied else { return }
        Task { await requestPermissionsAndListen(seal: seal, evidence: evidence, service: service) }
    }

    /// Cancel listening or stop speaking immediately.
    public func cancel() {
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        transcript = ""
        state = .idle
    }

    /// Announce a debriefing or settlement message aloud.
    public func speakAnnouncement(_ text: String) {
        cancel()
        speak(text)
    }

    // MARK: - Permission

    private func requestPermissionsAndListen(
        seal: ParitySeal,
        evidence: String,
        service: FoundationCoachService
    ) async {
        state = .requestingPermission

        let micStatus = await requestMicrophonePermission()
        let speechStatus = await requestSpeechRecognitionPermission()

        guard micStatus, speechStatus else {
            state = .denied
            return
        }
        beginListening(seal: seal, evidence: evidence, service: service)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Listening

    private func beginListening(seal: ParitySeal, evidence: String, service: FoundationCoachService) {
        transcript = ""
        state = .listening

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Microphone setup failed.")
            return
        }
        #endif

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            state = .error("Speech recognition unavailable.")
            return
        }
        self.recognizer = recognizer
        recognizer.defaultTaskHint = .search

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .error("Invalid audio format.")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            state = .error("Microphone unavailable.")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopListening()
                        let question = result.bestTranscription.formattedString
                        Task { await self.think(question: question, seal: seal, evidence: evidence, service: service) }
                    }
                }
            }
            if let error, (error as NSError).code != 301 /* cancelled */ {
                Task { @MainActor in
                    let question = self.transcript
                    self.stopListening()
                    if !question.isEmpty {
                        Task { await self.think(question: question, seal: seal, evidence: evidence, service: service) }
                    } else {
                        self.state = .idle
                    }
                }
            }
        }
    }

    private func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Thinking

    private func think(
        question: String,
        seal: ParitySeal,
        evidence: String,
        service: FoundationCoachService
    ) async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }
        state = .thinking
        do {
            let answer = try await service.explain(seal: seal, evidence: evidence, question: question)
            speak(answer)
        } catch {
            state = .error("Coach unavailable.")
        }
    }

    // MARK: - Speaking

    private func speak(_ text: String) {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {}
        #endif

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9
        state = .speaking(text: text)
        synthesizer.speak(utterance)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceSession: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        Task { @MainActor in self.state = .idle }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        Task { @MainActor in self.state = .idle }
    }
}

#else
// Non-Speech platforms (macOS without Speech framework linked).
@MainActor
public final class VoiceSession: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle, requestingPermission, listening, thinking
        case speaking(text: String)
        case denied, error(String)
    }
    @Published public private(set) var state: State = .idle
    @Published public private(set) var transcript: String = ""
    public init() {}
    public func start(seal: ParitySeal, evidence: String, using service: FoundationCoachService) {}
    public func cancel() {}
    public func speakAnnouncement(_ text: String) {}
}
#endif
