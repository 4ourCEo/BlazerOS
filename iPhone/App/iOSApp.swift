import BlazerActivity
import LightningDesk
import SwiftUI

@main
struct BlazerOSPhoneApp: App {
    @StateObject private var model = LightningDeskModel()

    var body: some Scene {
        WindowGroup {
            LightningDeskView(model: model)
                .onChange(of: model.frame) { _, next in
                    LiveActivityController.shared.update(with: next)
                }
        }
    }
}
