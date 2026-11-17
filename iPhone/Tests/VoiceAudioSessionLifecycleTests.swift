import XCTest
@testable import BlazerCore

final class VoiceAudioSessionLifecycleTests: XCTestCase {
    @MainActor
    func testReleaseWaitsForActivationThenCompletesBeforeNextLease() async throws {
        let driver = GatedAudioDriver()
        await driver.holdNextActivation()
        let coordinator = VoiceAudioSessionCoordinator(driver: driver)
        let first = UUID()
        let second = UUID()

        let acquireFirst = Task { try await coordinator.acquire(first, mode: .listening) }
        await driver.waitUntilActivationStarts()
        let releaseFirst = Task { try await coordinator.release(first) }
        let acquireSecond = Task { try await coordinator.acquire(second, mode: .speech) }

        let beforeResume = await driver.events
        XCTAssertEqual(beforeResume, ["activate-listening"])
        await driver.finishHeldActivation()
        try await acquireFirst.value
        try await releaseFirst.value
        try await acquireSecond.value

        let afterSecondAcquire = await driver.events
        XCTAssertEqual(afterSecondAcquire, [
            "activate-listening", "deactivate", "activate-speech"
        ])
        try await coordinator.release(second)
        let finalEvents = await driver.events
        XCTAssertEqual(finalEvents, [
            "activate-listening", "deactivate", "activate-speech", "deactivate"
        ])
        let maximum = await driver.maximumConcurrentOperations
        XCTAssertEqual(maximum, 1)
    }

    @MainActor
    func testStaleReleaseCannotDeactivateNewOwner() async throws {
        let driver = GatedAudioDriver()
        let coordinator = VoiceAudioSessionCoordinator(driver: driver)
        let old = UUID()
        let current = UUID()
        try await coordinator.acquire(old, mode: .listening)
        try await coordinator.release(old)
        try await coordinator.acquire(current, mode: .speech)
        try await coordinator.release(old)

        let afterStaleRelease = await driver.events
        XCTAssertEqual(afterStaleRelease, ["activate-listening", "deactivate", "activate-speech"])
        try await coordinator.release(current)
        let events = await driver.events
        XCTAssertEqual(events, ["activate-listening", "deactivate", "activate-speech", "deactivate"])
    }

    @MainActor
    func testActivationFailureRequiresRecoveryBeforeNextLease() async throws {
        let driver = GatedAudioDriver()
        await driver.failNextActivation()
        let coordinator = VoiceAudioSessionCoordinator(driver: driver)
        do {
            try await coordinator.acquire(UUID(), mode: .listening)
            XCTFail("activation should fail")
        } catch {}

        let next = UUID()
        try await coordinator.acquire(next, mode: .speech)
        try await coordinator.release(next)
        let events = await driver.events
        XCTAssertEqual(events, ["activate-listening", "deactivate", "activate-speech", "deactivate"])
    }

    @MainActor
    func testAcquireEnqueuesBeforeCancellationCanRelease() async throws {
        let driver = GatedAudioDriver()
        let coordinator = VoiceAudioSessionCoordinator(driver: driver)
        await driver.holdNextActivation()
        let token = UUID()
        let acquire = Task { try await coordinator.acquire(token, mode: .listening) }
        await driver.waitUntilActivationStarts()
        let release = Task { try await coordinator.release(token) }
        await driver.finishHeldActivation()
        try await acquire.value
        try await release.value
        let events = await driver.events
        XCTAssertEqual(events, ["activate-listening", "deactivate"])
    }

    @MainActor
    func testNextLeaseWaitsForSuccessfulRecoveryAfterDeactivationFailure() async throws {
        let driver = GatedAudioDriver()
        let coordinator = VoiceAudioSessionCoordinator(driver: driver)
        let first = UUID()
        let next = UUID()
        try await coordinator.acquire(first, mode: .listening)
        await driver.failNextDeactivation()
        do {
            try await coordinator.release(first)
            XCTFail("deactivation should fail")
        } catch {}

        await driver.holdNextDeactivation()
        let acquireNext = Task { try await coordinator.acquire(next, mode: .speech) }
        await driver.waitUntilDeactivationStarts(count: 2)
        let whileRecoveryPending = await driver.events
        XCTAssertEqual(whileRecoveryPending, [
            "activate-listening", "deactivate", "deactivate"
        ])

        await driver.finishHeldDeactivation()
        try await acquireNext.value
        let afterRecovery = await driver.events
        XCTAssertEqual(afterRecovery, [
            "activate-listening", "deactivate", "deactivate", "activate-speech"
        ])
        try await coordinator.release(next)
    }
}

private actor GatedAudioDriver: VoiceAudioSessionDriving {
    private(set) var events: [String] = []
    private(set) var maximumConcurrentOperations = 0
    private var concurrentOperations = 0
    private var holdActivation = false
    private var activationContinuation: CheckedContinuation<Void, any Error>?
    private var activationStarted = false
    private var failActivation = false
    private var holdDeactivation = false
    private var deactivationContinuation: CheckedContinuation<Void, any Error>?
    private var deactivationCount = 0
    private var failDeactivation = false

    func holdNextActivation() { holdActivation = true }
    func failNextActivation() { failActivation = true }
    func holdNextDeactivation() { holdDeactivation = true }
    func failNextDeactivation() { failDeactivation = true }

    func activate(_ mode: VoiceAudioSessionCoordinator.Mode) async throws {
        beginOperation()
        defer { endOperation() }
        events.append(mode == .listening ? "activate-listening" : "activate-speech")
        activationStarted = true
        if holdActivation {
            holdActivation = false
            try await withCheckedThrowingContinuation { activationContinuation = $0 }
        }
        if failActivation {
            failActivation = false
            throw TestFailure.activation
        }
    }

    func deactivate() async throws {
        beginOperation()
        defer { endOperation() }
        events.append("deactivate")
        deactivationCount += 1
        if failDeactivation {
            failDeactivation = false
            throw TestFailure.deactivation
        }
        if holdDeactivation {
            holdDeactivation = false
            try await withCheckedThrowingContinuation { deactivationContinuation = $0 }
        }
    }

    func waitUntilActivationStarts() async {
        while !activationStarted { try? await Task.sleep(for: .milliseconds(1)) }
    }

    func finishHeldActivation() {
        activationContinuation?.resume()
        activationContinuation = nil
    }

    func waitUntilDeactivationStarts(count: Int) async {
        while deactivationCount < count { try? await Task.sleep(for: .milliseconds(1)) }
    }

    func finishHeldDeactivation() {
        deactivationContinuation?.resume()
        deactivationContinuation = nil
    }

    private func beginOperation() {
        concurrentOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, concurrentOperations)
    }

    private func endOperation() { concurrentOperations -= 1 }

    private enum TestFailure: Error { case activation, deactivation }
}
