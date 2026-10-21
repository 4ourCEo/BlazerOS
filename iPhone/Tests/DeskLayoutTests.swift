import BlazerCore
import LightningDesk
import SwiftUI
import UIKit
import XCTest

@MainActor
final class DeskLayoutTests: XCTestCase {
    func testDeskFitsTheIPhone16Canvas() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-layout-\(UUID().uuidString)", isDirectory: true)
        let model = LightningDeskModel(storageRoot: root)
        let host = UIHostingController(rootView: LightningDeskView(model: model))
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(PhoneTarget.width), height: CGFloat(PhoneTarget.height))
        let window = UIWindow(frame: canvas)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = canvas
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        XCTAssertEqual(host.view.bounds.width, CGFloat(PhoneTarget.width), accuracy: 0.5)
        XCTAssertEqual(host.view.bounds.height, CGFloat(PhoneTarget.height), accuracy: 0.5)
        XCTAssertFalse(extendsOutside(host.view, of: host.view))
        try? FileManager.default.removeItem(at: root)
    }

    func testAllTabsFitIPhone16Canvas() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-layout-tabs-\(UUID().uuidString)", isDirectory: true)
        let model = LightningDeskModel(storageRoot: root)
        model.showingLaunch = false
        let host = UIHostingController(rootView: LightningDeskView(model: model))
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(PhoneTarget.width), height: CGFloat(PhoneTarget.height))
        let window = UIWindow(frame: canvas)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = canvas

        for tab in DeskTab.allCases {
            model.activeTab = tab
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let overflow = firstOverflow(host.view, of: host.view)
            XCTAssertNil(
                overflow,
                "Tab \(tab.rawValue) has views outside the canvas: \(overflow ?? "")"
            )
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testAllTabsFitAtLargestDynamicType() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-layout-large-type-\(UUID().uuidString)", isDirectory: true)
        let model = LightningDeskModel(storageRoot: root)
        model.showingLaunch = false
        let host = UIHostingController(rootView: LightningDeskView(model: model))
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(PhoneTarget.width), height: CGFloat(PhoneTarget.height))
        let window = UIWindow(frame: canvas)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = canvas
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        for tab in DeskTab.allCases {
            model.activeTab = tab
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let overflow = firstOverflow(host.view, of: host.view)
            XCTAssertNil(overflow, "Tab \(tab.rawValue) overflows at largest Dynamic Type: \(overflow ?? "")")
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func extendsOutside(_ view: UIView, of root: UIView) -> Bool {
        firstOverflow(view, of: root) != nil
    }

    private func firstOverflow(_ view: UIView, of root: UIView) -> String? {
        let frame = view.convert(view.bounds, to: root)
        let canvas = root.bounds.insetBy(dx: -1, dy: -1)
        if view !== root, !frame.isNull, !frame.isEmpty, !canvas.contains(frame) {
            return "\(type(of: view)) frame=\(frame) canvas=\(root.bounds)"
        }
        // Content inside a scroll view is intentionally larger than its viewport.
        if view is UIScrollView { return nil }
        for subview in view.subviews {
            if let found = firstOverflow(subview, of: root) { return found }
        }
        return nil
    }
}
