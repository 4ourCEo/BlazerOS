import CoreGraphics
import Foundation

/// Shipping device for BlazerOS.
/// iPhone 16: 393×852 pt, @3x, 1179×2556 px.
/// This is not iPhone 14/15 (390×844), iPhone 16 Pro (402×874), or iPhone 16 Plus (430×932).
/// The base iPhone 16 has a Dynamic Island, a 60Hz display, and no always-on display.
public enum PhoneTarget {
    public static let model = "iPhone 16"
    public static let systemVersion = "26.0"
    public static let width: CGFloat = 393
    public static let height: CGFloat = 852
    public static let scale: CGFloat = 3
    public static let pixelWidth: CGFloat = 1179
    public static let pixelHeight: CGFloat = 2556
    /// Portrait safe area under the Dynamic Island.
    public static let topInset: CGFloat = 59
    /// Portrait safe area above the home indicator.
    public static let bottomInset: CGFloat = 34
    public static let hasDynamicIsland = true
    public static let hasAlwaysOnDisplay = false
    public static let hasProMotion = false
    public static let bundleIdentifier = "com.blazer.os"
    public static let appGroup = "group.com.blazer.os"
    /// Set by the Scan intent. The desk consumes it once credentials are ready.
    public static let pendingScanKey = "blazer.pendingScan"
}
