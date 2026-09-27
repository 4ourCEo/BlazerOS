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

    var body: some Scene {
        WindowGroup {
            LightningDeskView(model: model)
                #if os(macOS)
                .frame(width: PhoneTarget.width, height: PhoneTarget.height)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: PhoneTarget.width, height: PhoneTarget.height)
        .windowResizability(.contentSize)
        #endif
    }
}
