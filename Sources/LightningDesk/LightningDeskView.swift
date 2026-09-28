import SwiftUI
import BlazerCore
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// Main native desk container for iPhone 16.
/// Features a hero-first execution screen, 5-screen navigation, and a floating bottom bar.
public struct LightningDeskView: View {
    public init(model: LightningDeskModel) {
        self.model = model
    }
    @ObservedObject var model: LightningDeskModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Active Screen Content
                ZStack {
                    switch model.activeTab {
                    case .desk:
                        DeskScreen(model: model, reduceMotion: reduceMotion)
                            .transition(.opacity)
                    case .markets:
                        MarketsScreen(model: model)
                            .transition(.opacity)
                    case .replay:
                        ReplayScreen(model: model)
                            .transition(.opacity)
                    case .coach:
                        CoachScreen(model: model)
                            .transition(.opacity)
                    case .journal:
                        JournalScreen(model: model)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating Navigation Bar
                FloatingNavBar(activeTab: $model.activeTab)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            .modifier(ReferencePhoneInset())

            // Launch Cover
            if model.showingLaunch {
                LaunchCover(
                    status: launchWord,
                    markLit: reduceMotion || model.launchMarkLit,
                    wordLit: reduceMotion || model.launchWordLit
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // Credential Settings / Missing Cover
            if model.showingCredentials || (!model.showingLaunch && model.keychainState == .missing) {
                CredentialCover(model: model)
                    .modifier(ReferencePhoneInset())
                    .transition(.opacity)
            }

            // Full Replay Inspector Modal
            if let entry = model.journal.first(where: { $0.id == model.openReplayID }) {
                ReplayCover(
                    entry: entry,
                    coach: model.coachExplanation,
                    voiceSession: model.voiceSession,
                    onAsk: { model.askCoach(for: entry) },
                    onStopVoice: { model.stopVoice() }
                ) {
                    model.closeReplay()
                }
                .modifier(ReferencePhoneInset())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.showingLaunch)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: model.heroLift)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: model.activeTab)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.showingCredentials)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.openReplayID)
        .onChange(of: model.frame?.fingerprint) { previous, next in
            guard let next, next != previous else { return }
            DeskHaptics.commit()
        }
        .onChange(of: model.frame?.veto) { previous, next in
            guard let next, !next.isEmpty, next != previous else { return }
            DeskHaptics.veto()
        }
        .task { await model.run() }
        .task { await model.settleLaunch() }
    }

    private var launchWord: String {
        switch model.feed {
        case .live:                     return "LIVE"
        case .connecting:               return "CONNECTING"
        case .stale, .disconnected, .error: return "OFFLINE"
        }
    }
}

#Preview("iPhone 16 Desk") {
    LightningDeskView(model: LightningDeskModel())
}

