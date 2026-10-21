import BlazerCore
import LightningDesk
import SwiftUI
#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

@main
struct BlazerOSMain: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var model = LightningDeskModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("BlazerOS — Lightning Desk") {
            LightningDeskView(model: model)
                #if os(macOS)
                .frame(width: PhoneTarget.width, height: PhoneTarget.height)
                #endif
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.handleAppForegrounded()
                    case .background: model.handleAppBackgrounded()
                    default: break
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: PhoneTarget.width, height: PhoneTarget.height)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Desk") {
                Button("Scan Now") {
                    Task { await model.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Lock In Trade") {
                    Task { await model.lockInTrade() }
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

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
                    model.activeTab = .intel
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Coach Intelligence") {
                    model.activeTab = .coach
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Journal & Ledger") {
                    model.activeTab = .journal
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
        #endif
    }
}
