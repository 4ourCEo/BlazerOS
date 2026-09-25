import LightningDesk
import SwiftUI

@main
struct BlazerOSMain: App {
    @StateObject private var model = LightningDeskModel()

    var body: some Scene {
        WindowGroup {
            LightningDeskView(model: model)
                .frame(width: 390, height: 780)
        }
        #if os(macOS)
        .defaultSize(width: 390, height: 780)
        .windowResizability(.contentSize)
        #endif
    }
}
