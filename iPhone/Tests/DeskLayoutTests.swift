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

    private func extendsOutside(_ view: UIView, of root: UIView) -> Bool {
        let frame = view.convert(view.bounds, to: root)
        let canvas = root.bounds.insetBy(dx: -1, dy: -1)
        if view !== root, !frame.isNull, !frame.isEmpty, !canvas.contains(frame) {
            return true
        }
        return view.subviews.contains { extendsOutside($0, of: root) }
    }
}
