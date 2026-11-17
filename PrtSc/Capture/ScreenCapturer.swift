import AppKit
import CoreGraphics
import CoreVideo
import PrtScCore
import ScreenCaptureKit

enum ScreenCapturerError: LocalizedError {
    case displayNotFound(UInt32)
    case windowNotFound(UInt32)
    case noDisplays
    case compositingFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: String(localized: "The display is no longer available.")
        case .windowNotFound: String(localized: "The window is no longer available.")
        case .noDisplays: String(localized: "No display could be found.")
        case .compositingFailed: String(localized: "The image could not be assembled.")
        }
    }
}

/// Wraps a ScreenCaptureKit object so it can cross task boundaries. SCK objects are immutable
/// descriptions that SCK itself consumes from any thread.
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// ScreenCaptureKit wrapper. Not MainActor-isolated.
///
/// - `freezeFrame(includeShadows:pointer:)`: every display, and every on-screen layer-0 window of the
///   current Space (excluding PrtSc's own windows, shadow per setting), each captured once without the
///   pointer; the pointer variants are composited from the one recorded pointer sample.
/// - `captureDisplay(_:showsPointer:)` and `captureWindow(_:attached:includeShadow:)` for Instant Captures.
/// - Stitching a cross-display Selection uses `DisplayGeometry.segments` (see `ImageOps.stitch`).
final class ScreenCapturer: Sendable {
    init() {}

    // MARK: Frozen Frame

    /// - Parameter pointer: the pointer position and glyph, sampled by the caller synchronously when the
    ///   capture was requested. Each display and window is captured once without the pointer and the
    ///   with-pointer variant is composited from this one sample, so toggling Show Pointer changes
    ///   nothing but the pointer.
    func freezeFrame(includeShadows: Bool, pointer: PointerSample) async throws -> FrozenFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = await Self.displayPairs(in: content)
        guard !displays.isEmpty else { throw ScreenCapturerError.noDisplays }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = SendableBox(content.applications.filter { $0.processID == ownPID })
        let order = Self.zOrder()
        let windows = SendableBox(Self.orderedWindows(content.windows, zOrder: order).filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.processID != ownPID
                && $0.frame.width >= 1 && $0.frame.height >= 1
        })

        async let displaySnapshots = Self.captureDisplaySnapshots(displays, excluding: ownApps, pointer: pointer)
        async let windowSnapshots = Self.captureWindowSnapshots(windows, includeShadows: includeShadows,
                                                                pointer: pointer)
        return try await FrozenFrame(displays: displaySnapshots, windows: windowSnapshots,
                                     pointer: pointer.location, pointerGlyph: pointer.glyph)
    }

    // MARK: Instant Captures

    /// Current displays as PrtScCore values.
    func currentDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return await Self.displayPairs(in: content).map(\.info)
    }

    /// On-screen windows of the current Space (layer ≥ 0), front to back.
    func onScreenWindowsFrontToBack() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return Self.orderedWindows(content.windows, zOrder: Self.zOrder())
            .filter { $0.isOnScreen && $0.windowLayer >= 0 && $0.frame.width >= 1 && $0.frame.height >= 1 }
            .map(Self.windowInfo)
    }

    func captureDisplay(_ display: DisplayInfo, showsPointer: Bool) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
            throw ScreenCapturerError.displayNotFound(display.displayID)
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = SendableBox(content.applications.filter { $0.processID == ownPID })
        let image = try await Self.captureDisplayImage(SendableBox(scDisplay), info: display,
                                                       showsCursor: showsPointer, excluding: ownApps)
        return CapturedImage(image: image, scale: display.scale)
    }

    /// Captures one window. When `attached` (sheets, popovers) is non-empty they're composited at their
    /// actual positions: every component is captured with the shadow when `includeShadow` is on and placed
    /// by the global bounds of its own image (window frame plus shadow margin, see `captureWindowImage`),
    /// so the pieces and their shadows line up.
    func captureWindow(_ window: WindowInfo, attached: [WindowInfo],
                       includeShadow: Bool) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        func find(_ info: WindowInfo) throws -> SCWindow {
            guard let found = content.windows.first(where: { $0.windowID == info.windowID }) else {
                throw ScreenCapturerError.windowNotFound(info.windowID)
            }
            return found
        }
        let parent = try find(window)

        if attached.isEmpty {
            let shot = try await Self.captureWindowImage(SendableBox(parent), includeShadow: includeShadow)
            return CapturedImage(image: shot.image, scale: shot.scale)
        }

        // Parent first, then attached windows from the back to the front (the resolver lists them front to back).
        let ordered = [window] + attached.reversed()
        let boxes = try ordered.map { SendableBox(try find($0)) }
        let shots: [WindowShot] = try await withThrowingTaskGroup(of: (Int, WindowShot).self) { group in
            for (index, box) in boxes.enumerated() {
                group.addTask { (index, try await Self.captureWindowImage(box, includeShadow: includeShadow)) }
            }
            var results: [(Int, WindowShot)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let scale = shots.map(\.scale).max() ?? 1
        let layers = shots.map { ImageOps.Layer(image: $0.image, bounds: $0.bounds, scale: $0.scale) }
        guard let composite = ImageOps.composite(layers, scale: scale, colorSpace: shots.first?.image.colorSpace) else {
            throw ScreenCapturerError.compositingFailed
        }
        return CapturedImage(image: composite, scale: scale)
    }

    // MARK: Stitching

    /// Cuts a global CG rect out of Frozen Frame displays (stitching across displays when needed).
    static func stitch(rect: CGRect, from displays: [DisplaySnapshot], showsPointer: Bool) -> CapturedImage? {
        ImageOps.stitch(rect: rect, snapshots: displays, showsPointer: showsPointer)
    }

    // MARK: Helpers

    /// Pointer location in global CG coordinates (top-left origin).
    static func pointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    @MainActor
    private static func backingScales() -> [UInt32: CGFloat] {
        var result: [UInt32: CGFloat] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                result[number.uint32Value] = screen.backingScaleFactor
            }
        }
        return result
    }

    private static func displayPairs(in content: SCShareableContent) async -> [(display: SendableBox<SCDisplay>, info: DisplayInfo)] {
        let scales = await backingScales()
        let mainID = CGMainDisplayID()
        return content.displays.map { display in
            let scale: CGFloat
            if let known = scales[display.displayID] {
                scale = known
            } else if let mode = CGDisplayCopyDisplayMode(display.displayID), mode.width > 0 {
                scale = CGFloat(mode.pixelWidth) / CGFloat(mode.width)
            } else {
                scale = 1
            }
            let info = DisplayInfo(displayID: display.displayID, frame: display.frame, scale: scale,
                                   isPrimary: display.displayID == mainID)
            return (SendableBox(display), info)
        }
    }

    private static func windowInfo(_ window: SCWindow) -> WindowInfo {
        WindowInfo(windowID: window.windowID,
                   ownerPID: window.owningApplication?.processID ?? 0,
                   ownerBundleID: window.owningApplication?.bundleIdentifier,
                   title: window.title,
                   frame: window.frame,
                   layer: window.windowLayer,
                   isOnScreen: window.isOnScreen)
    }

    /// Window IDs mapped to their front-to-back index (0 = front-most).
    private static func zOrder() -> [UInt32: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [UInt32: Int] = [:]
        for (index, entry) in list.enumerated() {
            if let number = entry[kCGWindowNumber as String] as? NSNumber {
                order[number.uint32Value] = index
            }
        }
        return order
    }

    private static func orderedWindows(_ windows: [SCWindow], zOrder: [UInt32: Int]) -> [SCWindow] {
        WindowOrdering.frontToBack(windows, windowID: \.windowID, zOrder: zOrder)
    }

    // MARK: Display capture

    private static func captureDisplayImage(_ display: SendableBox<SCDisplay>, info: DisplayInfo,
                                            showsCursor: Bool,
                                            excluding apps: SendableBox<[SCRunningApplication]>) async throws -> CGImage {
        let filter = SCContentFilter(display: display.value, excludingApplications: apps.value, exceptingWindows: [])
        let config = SCStreamConfiguration()
        // Native pixels. The colour space is left unset so ScreenCaptureKit keeps the display's own.
        config.width = Int((info.frame.width * info.scale).rounded())
        config.height = Int((info.frame.height * info.scale).rounded())
        config.showsCursor = showsCursor
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Each display once, without the pointer; the pointer variant is composited from `pointer`.
    private static func captureDisplaySnapshots(
        _ displays: [(display: SendableBox<SCDisplay>, info: DisplayInfo)],
        excluding apps: SendableBox<[SCRunningApplication]>,
        pointer: PointerSample
    ) async throws -> [DisplaySnapshot] {
        try await withThrowingTaskGroup(of: (Int, DisplaySnapshot).self) { group in
            for (index, pair) in displays.enumerated() {
                group.addTask {
                    let plain = try await captureDisplayImage(pair.display, info: pair.info,
                                                              showsCursor: false, excluding: apps)
                    let withPointer = pointer.glyph.flatMap {
                        ImageOps.compositePointer($0, onto: plain, scale: pair.info.scale,
                                                  imageOrigin: pair.info.frame.origin,
                                                  pointer: pointer.location)
                    } ?? plain
                    return (index, DisplaySnapshot(info: pair.info, image: plain, imageWithPointer: withPointer))
                }
            }
            var results: [(Int, DisplaySnapshot)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: Window capture

    private struct WindowShot: Sendable {
        let image: CGImage
        let scale: CGFloat
        /// Where `image` sits in global CG points (the window frame, plus the shadow margin with shadows).
        let bounds: CGRect
    }

    /// An unobscured image of one window via a desktop-independent filter.
    ///
    /// `ignoreGlobalClipSingleWindow` is on so the image is the whole window even when it extends past
    /// the display it is mostly on (or spans displays).
    ///
    /// With the shadow the image is larger than the window frame. ScreenCaptureKit reports that extent as
    /// the filter's `contentRect`. When `contentRect` is in global coordinates (it contains the frame) its
    /// origin gives the exact shadow margins; otherwise the margin is assumed to be the same on every side
    /// (the extra size split evenly around the frame), which is exact only for symmetric shadows.
    private static func captureWindowImage(_ window: SendableBox<SCWindow>,
                                           includeShadow: Bool) async throws -> WindowShot {
        let filter = SCContentFilter(desktopIndependentWindow: window.value)
        let info = SCShareableContent.info(for: filter)
        let scale = max(CGFloat(info.pointPixelScale), 1)
        let frame = window.value.frame
        let content = info.contentRect
        let withShadow = includeShadow && content.width > 0 && content.height > 0
        let size = withShadow ? content.size : frame.size

        let config = SCStreamConfiguration()
        config.width = Int((size.width * scale).rounded(.up))
        config.height = Int((size.height * scale).rounded(.up))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = !includeShadow
        config.ignoreGlobalClipSingleWindow = true
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        var origin = frame.origin
        if withShadow {
            if content.insetBy(dx: -1, dy: -1).contains(frame) {
                origin = content.origin
            } else {
                origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
            }
        }
        let bounds = CGRect(origin: origin, size: CGSize(width: CGFloat(image.width) / scale,
                                                         height: CGFloat(image.height) / scale))
        return WindowShot(image: image, scale: scale, bounds: bounds)
    }

    private static func captureWindowSnapshots(_ windows: SendableBox<[SCWindow]>, includeShadows: Bool,
                                               pointer: PointerSample) async -> [WindowSnapshot] {
        await withTaskGroup(of: (Int, WindowSnapshot?).self) { group in
            for (index, window) in windows.value.enumerated() {
                let box = SendableBox(window)
                group.addTask {
                    // One window failing (it closed, or can't be captured) shouldn't lose the rest.
                    guard let shot = try? await captureWindowImage(box, includeShadow: includeShadows) else {
                        return (index, nil)
                    }
                    let info = windowInfo(box.value)
                    // The pointer is shown on a window it was over, at its recorded spot in the window image.
                    let withPointer = info.frame.contains(pointer.location)
                        ? pointer.glyph.flatMap {
                            ImageOps.compositePointer($0, onto: shot.image, scale: shot.scale,
                                                      imageOrigin: shot.bounds.origin, pointer: pointer.location)
                        } ?? shot.image
                        : shot.image
                    let snapshot = WindowSnapshot(info: info, image: shot.image, imageWithPointer: withPointer,
                                                  scale: shot.scale, bounds: shot.bounds)
                    return (index, snapshot)
                }
            }
            var results: [(Int, WindowSnapshot)] = []
            for await (index, snapshot) in group {
                if let snapshot { results.append((index, snapshot)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
