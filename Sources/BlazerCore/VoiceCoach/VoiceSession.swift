import Foundation
#if canImport(Speech)
import Speech
import AVFoundation

/// Serialized owner for AVAudioSession. Every ownership mutation and every full
/// activation/deactivation completion runs in the same task chain.
@MainActor
final class VoiceAudioSessionCoordinator {
    enum Mode: Sendable, Equatable { case listening, speech }
    enum CoordinatorError: Error { case alreadyOwned }

    private enum Ownership {
        case active(UUID)
        case uncertain(UUID)
    }

    private let driver: any VoiceAudioSessionDriving
    private var ownership: Ownership?
    private var transitionTail: Task<Void, Never>?

    init(driver: any VoiceAudioSessionDriving = SystemVoiceAudioSessionDriver()) {
        self.driver = driver
    }

    func acquire(_ token: UUID, mode: Mode) async throws {
        try await enqueue { try await self.acquireSerial(token, mode: mode) }
    }

    func release(_ token: UUID) async throws {
        try await enqueue { try await self.releaseSerial(token) }
    }

    private func acquireSerial(_ token: UUID, mode: Mode) async throws {
        if case .uncertain = ownership {
            // The previous release did not confirm that AVAudioSession became inactive.
            // Recover successfully before changing category or activating a new mode.
            try await driver.deactivate()
            ownership = nil
        }
        guard ownership == nil else { throw CoordinatorError.alreadyOwned }
        ownership = .active(token)
        do {
            try await driver.activate(mode)
        } catch {
            if case let .active(ownerToken)? = ownership, ownerToken == token {
                ownership = .uncertain(token)
            }
            throw error
        }
    }

    private func releaseSerial(_ token: UUID) async throws {
        guard case let .active(ownerToken)? = ownership, ownerToken == token else {
            return
        }
        do {
            try await driver.deactivate()
            if case let .active(ownerToken)? = ownership, ownerToken == token { ownership = nil }
        } catch {
            if case let .active(ownerToken)? = ownership, ownerToken == token {
                ownership = .uncertain(token)
            }
            throw error
        }
    }

    private func enqueue<T: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        let previous = transitionTail
        let job = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        transitionTail = Task { _ = await job.result }
        return try await job.value
    }
}

protocol VoiceAudioSessionDriving: Sendable {
    func activate(_ mode: VoiceAudioSessionCoordinator.Mode) async throws
    func deactivate() async throws
}

private struct SystemVoiceAudioSessionDriver: VoiceAudioSessionDriving {
    private static let queue = DispatchQueue(label: "com.blazer.voice-audio-session")

    func activate(_ mode: VoiceAudioSessionCoordinator.Mode) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    do {
                        try Self.configure(session, mode: mode)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                session.activate(options: []) { activated, error in
                    if let error { continuation.resume(throwing: error) }
                    else if activated { continuation.resume() }
                    else { continuation.resume(throwing: AudioSessionOperationError.activationFailed) }
                }
            }
        } else {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    do {
                        try Self.configure(session, mode: mode)
                        try session.setActive(true, options: .notifyOthersOnDeactivation)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        #endif
    }

    func deactivate() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                session.deactivate(options: .notifyOthersOnDeactivation) { deactivated, error in
                    if let error { continuation.resume(throwing: error) }
                    else if deactivated { continuation.resume() }
                    else { continuation.resume(throwing: AudioSessionOperationError.deactivationFailed) }
                }
            }
        } else {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    do {
                        try session.setActive(false, options: .notifyOthersOnDeactivation)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private static func configure(_ session: AVAudioSession, mode: VoiceAudioSessionCoordinator.Mode) throws {
        switch mode {
        case .listening:
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        case .speech:
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
    }
    #endif
}

private enum AudioSessionOperationError: Error {
    case activationFailed
    case deactivationFailed
}

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

    public enum RecognitionAvailability: Equatable, Sendable {
        case checking
        case onDevice
        case network
        case permissionDenied
        case unavailable(String)

        public var label: String {
            switch self {
            case .checking: return "Speech: checking"
            case .onDevice: return "Speech: on-device"
            case .network: return "Speech: network"
            case .permissionDenied: return "Speech: permission denied"
            case .unavailable(let reason): return "Speech: \(reason)"
            }
        }
    }

    public enum SynthesisAvailability: Equatable, Sendable {
        case checking
        case available
        case unavailable

        public var label: String {
            switch self {
            case .checking: return "Voice: checking"
            case .available: return "Voice: ready"
            case .unavailable: return "Voice: unavailable"
            }
        }
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var recognitionAvailability: RecognitionAvailability = .checking
    @Published public private(set) var synthesisAvailability: SynthesisAvailability = .checking

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let audioCoordinator = VoiceAudioSessionCoordinator()
    private var generation: UInt64 = 0
    private var permissionTask: Task<Void, Never>?
    private var audioLease: UUID?
    private var currentUtteranceID: ObjectIdentifier?
    private var cleanupTask: Task<Void, Never>?

    public override init() {
        super.init()
        synthesizer.delegate = self
        synthesisAvailability = AVSpeechSynthesisVoice(language: "en-US") == nil ? .unavailable : .available
        if SFSpeechRecognizer.authorizationStatus() == .denied {
            recognitionAvailability = .permissionDenied
        } else if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable {
            recognitionAvailability = recognizer.supportsOnDeviceRecognition ? .onDevice : .unavailable("on-device speech unavailable")
        } else {
            recognitionAvailability = .unavailable("recognizer unavailable")
        }
    }

    // MARK: - Public API

    public func start(seal: ParitySeal, evidence: String, using service: FoundationCoachService) {
        guard state == .idle || state == .denied else { return }
        generation &+= 1
        let current = generation
        state = .requestingPermission
        permissionTask = Task { await requestPermissionsAndListen(
            seal: seal, evidence: evidence, service: service, generation: current) }
    }

    public func cancel() {
        generation &+= 1
        permissionTask?.cancel()
        permissionTask = nil
        stopListeningIO()
        synthesizer.stopSpeaking(at: .immediate)
        currentUtteranceID = nil
        transcript = ""
        state = .idle
        let lease = audioLease
        audioLease = nil
        if let lease {
            cleanupTask = enqueueRelease(lease)
        }
    }

    public func speakAnnouncement(_ text: String) {
        cancel()
        guard synthesisAvailability == .available else { return }
        generation &+= 1
        let current = generation
        Task { await speak(text, generation: current) }
    }

    // MARK: - Permission

    private func requestPermissionsAndListen(
        seal: ParitySeal,
        evidence: String,
        service: FoundationCoachService,
        generation current: UInt64
    ) async {
        let micStatus = await requestMicrophonePermission()
        guard current == generation, !Task.isCancelled else { return }
        let speechStatus = await requestSpeechRecognitionPermission()
        guard current == generation, !Task.isCancelled else { return }

        guard micStatus, speechStatus else {
            recognitionAvailability = .permissionDenied
            state = .denied
            return
        }
        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable {
            recognitionAvailability = recognizer.supportsOnDeviceRecognition ? .onDevice : .unavailable("on-device speech unavailable")
        } else {
            recognitionAvailability = .unavailable("recognizer unavailable")
        }
        await beginListening(seal: seal, evidence: evidence, service: service, generation: current)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Listening

    private func beginListening(
        seal: ParitySeal, evidence: String, service: FoundationCoachService,
        generation current: UInt64
    ) async {
        guard current == generation else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            state = .error("Speech recognition unavailable.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            recognitionAvailability = .unavailable("on-device speech unavailable")
            state = .error("On-device speech recognition is unavailable. Type your question instead.")
            return
        }
        await cleanupTask?.value
        guard current == generation else { return }

        let lease = UUID()
        audioLease = lease
        do { try await audioCoordinator.acquire(lease, mode: .listening) }
        catch {
            if audioLease == lease { audioLease = nil }
            guard current == generation else { return }
            state = .error("Microphone setup failed.")
            return
        }
        guard current == generation else {
            await releaseLease(lease)
            return
        }

        self.recognizer = recognizer
        recognizer.defaultTaskHint = .search
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            await failListening("Invalid audio format.", lease: lease)
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() }
        catch {
            await failListening("Microphone unavailable.", lease: lease)
            return
        }
        guard current == generation else {
            await stopListening()
            return
        }
        transcript = ""
        state = .listening
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == current else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        let question = result.bestTranscription.formattedString
                        await self.stopListening()
                        guard self.generation == current else { return }
                        if case .error = self.state { return }
                        await self.think(question: question, seal: seal, evidence: evidence, service: service)
                        return
                    }
                }
                if let error, (error as NSError).code != 301, self.generation == current {
                    let question = self.transcript
                    await self.stopListening()
                    guard self.generation == current else { return }
                    if case .error = self.state { return }
                    if !question.isEmpty {
                        await self.think(question: question, seal: seal, evidence: evidence, service: service)
                    } else { self.state = .idle }
                }
            }
        }
    }

    private func stopListeningIO() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func stopListening() async {
        stopListeningIO()
        if let lease = audioLease { await releaseLease(lease) }
    }

    private func releaseLease(_ lease: UUID) async {
        if audioLease == lease { audioLease = nil }
        await enqueueRelease(lease).value
    }

    private func enqueueRelease(_ lease: UUID) -> Task<Void, Never> {
        let previous = cleanupTask
        let releaseGeneration = generation
        let task = Task {
            await previous?.value
            do { try await audioCoordinator.release(lease) }
            catch where self.generation == releaseGeneration {
                self.state = .error("Audio session could not be released.")
            } catch {}
        }
        cleanupTask = task
        return task
    }

    private func failListening(_ message: String, lease: UUID) async {
        let failedGeneration = generation
        stopListeningIO()
        await releaseLease(lease)
        guard generation == failedGeneration else { return }
        if case .error = state { return }
        state = .error(message)
    }

    // MARK: - Thinking

    private func think(
        question: String,
        seal: ParitySeal,
        evidence: String,
        service: FoundationCoachService
    ) async {
        let current = generation
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }
        state = .thinking
        do {
            let answer = try await service.explain(seal: seal, evidence: evidence, question: question)
            guard current == generation else { return }
            await speak(answer, generation: current)
        } catch {
            guard current == generation else { return }
            state = .error("Coach unavailable.")
        }
    }

    // MARK: - Speaking

    private func speak(_ text: String, generation current: UInt64) async {
        await cleanupTask?.value
        guard current == generation, synthesisAvailability == .available else { return }
        let lease = UUID()
        audioLease = lease
        do { try await audioCoordinator.acquire(lease, mode: .speech) }
        catch {
            if audioLease == lease { audioLease = nil }
            guard current == generation else { return }
            state = .error("Audio playback setup failed.")
            return
        }
        guard current == generation else { await releaseLease(lease); return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9
        currentUtteranceID = ObjectIdentifier(utterance)
        state = .speaking(text: text)
        synthesizer.speak(utterance)
    }

    private func finishUtterance(_ utteranceID: ObjectIdentifier) async {
        guard currentUtteranceID == utteranceID else { return }
        currentUtteranceID = nil
        state = .idle
        if let lease = audioLease { await releaseLease(lease) }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceSession: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in await self.finishUtterance(utteranceID) }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in await self.finishUtterance(utteranceID) }
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
    public enum RecognitionAvailability: Equatable, Sendable {
        case checking, onDevice, network, permissionDenied, unavailable(String)
        public var label: String {
            switch self {
            case .checking: return "Speech: checking"
            case .onDevice: return "Speech: on-device"
            case .network: return "Speech: network"
            case .permissionDenied: return "Speech: permission denied"
            case .unavailable(let reason): return "Speech: \(reason)"
            }
        }
    }
    public enum SynthesisAvailability: Equatable, Sendable {
        case checking, available, unavailable
        public var label: String {
            switch self {
            case .checking: return "Voice: checking"
            case .available: return "Voice: ready"
            case .unavailable: return "Voice: unavailable"
            }
        }
    }
    @Published public private(set) var state: State = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var recognitionAvailability: RecognitionAvailability = .unavailable("Speech framework unavailable")
    @Published public private(set) var synthesisAvailability: SynthesisAvailability = .unavailable
    public init() {}
    public func start(seal: ParitySeal, evidence: String, using service: FoundationCoachService) {}
    public func cancel() {}
    public func speakAnnouncement(_ text: String) {}
}
#endif
