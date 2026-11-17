import BlazerCore
import LightningDesk
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct BlazerOSMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model: LightningDeskModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let promotionConfiguration = StrategyPromotionRuntime.load(from: .main)
        _model = StateObject(wrappedValue: LightningDeskModel(
            liveStrategyProfiles: promotionConfiguration.profiles,
            strategyPromotionRecords: promotionConfiguration.promotions,
            macResearchSourceAttestationVerified: promotionConfiguration.sourceAttestationVerified))
    }

    var body: some Scene {
        WindowGroup("BlazerOS — Lightning Desk") {
            LightningDeskView(model: model)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: model.handleAppForegrounded()
                case .background: model.handleAppBackgrounded()
                default: break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: MarketNotificationService.orbNotificationReceived)) { event in
                if let link = event.object as? String {
                    model.handleORBDeepLink(link)
                }
            }
        }
        .defaultSize(width: 1440, height: 920)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Desk") {
                Button("Scan Now") {
                    Task { await model.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Select 60s Horizon") {
                    model.selectedHorizonSec = 60
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Select 3m Horizon") {
                    model.selectedHorizonSec = 180
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("Select 5m Horizon") {
                    model.selectedHorizonSec = 300
                }
                .keyboardShortcut("5", modifiers: [.command, .option])

                Button("Select 10m Horizon") {
                    model.selectedHorizonSec = 600
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }

            CommandMenu("Navigation") {
                Button("Live Desk") {
                    model.activeTab = .desk
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Radar Markets") {
                    model.activeTab = .radar
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Edge Intel") {
                    model.activeTab = .review
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Coach Intelligence") {
                    model.activeTab = .review
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Journal & Ledger") {
                    model.activeTab = .review
                }
                .keyboardShortcut("5", modifiers: [.command])
            }

            CommandMenu("Watchlist") {
                ForEach(Array(model.pairs.enumerated()), id: \.element) { index, pair in
                    Button("Switch to \(pair)") {
                        model.selectAndNavigate(pair: pair)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control])
                }
            }
        }
    }
}
