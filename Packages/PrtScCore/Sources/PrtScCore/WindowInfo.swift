import CoreGraphics
import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public var windowID: UInt32
    public var ownerPID: Int32
    public var ownerBundleID: String?
    public var title: String?
    /// Global CG points.
    public var frame: CGRect
    /// 0 = normal app window
    public var layer: Int
    public var isOnScreen: Bool

    public init(windowID: UInt32, ownerPID: Int32, ownerBundleID: String?, title: String?,
                frame: CGRect, layer: Int, isOnScreen: Bool) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerBundleID = ownerBundleID
        self.title = title
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}
