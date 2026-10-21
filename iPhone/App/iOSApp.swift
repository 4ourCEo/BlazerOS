import BlazerActivity
import LightningDesk
import SwiftUI

@main
struct BlazerOSPhoneApp: App {
    @StateObject private var model = LightningDeskModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LightningDeskView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.handleAppForegrounded()
                    case .background: model.handleAppBackgrounded()
                    default: break
                    }
                }
                .onChange(of: model.frame) { _, next in
                    LiveActivityController.shared.update(with: next, trade: model.activeTrade)
                }
                .onChange(of: model.activeTrade) { _, trade in
                    LiveActivityController.shared.update(with: model.frame, trade: trade)
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["BLAZER_FM_SELFTEST"] == "1" {
                        await model.runAssistantSelfTestForTesting()
                    }
                    #endif
                }
        }
    }
}
