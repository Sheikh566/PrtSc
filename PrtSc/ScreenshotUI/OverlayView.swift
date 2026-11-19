import AppKit
import PrtScCore
import SwiftUI

/// The content of one overlay panel: the display's Frozen Frame image plus the mode-specific layer
/// (Selection dimming and handles, Screen outline, Window Picker). Flipped, so view coordinates are
/// the display's CG coordinates offset by its frame origin.
final class OverlayView: NSView {
    private let model: ScreenshotUIModel
    private let snapshot: DisplaySnapshot
    private let plainImage: NSImage
    private let pointerImage: NSImage
    /// Window Picker thumbnails per window ID, without and with the pointer (both variants cached).
    private var windowImages: [UInt32: NSImage] = [:]
    private var windowImagesWithPointer: [UInt32: NSImage] = [:]

    private var capsuleHost: ControlHostingView<CapturePanelView>?
    private var closeHost: ControlHostingView<CloseButtonView>?
    private var tooltipHost: PassthroughHostingView<PanelTooltipView>?
    private let badgeHost = NSHostingView(rootView: WindowBadgeView())

    private var isDragging = false
    private var dragHandle: SelectionHandle = .none

    private static let handleDiameter: CGFloat = 10

    private var info: DisplayInfo { snapshot.info }
    private var isPanelDisplay: Bool { info.displayID == model.panelDisplayID }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(model: ScreenshotUIModel, snapshot: DisplaySnapshot) {
        self.model = model
        self.snapshot = snapshot
        let size = snapshot.info.frame.size
        self.plainImage = NSImage(cgImage: snapshot.image, size: size)
        self.pointerImage = NSImage(cgImage: snapshot.imageWithPointer, size: size)
        super.init(frame: CGRect(origin: .zero, size: size))

        autoresizingMask = [.width, .height]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Screenshot area"))
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        if isPanelDisplay {
            let capsule = ControlHostingView(rootView: CapturePanelView(model: model) { [weak self] frame in
                self?.capsuleHost?.controlFrame = frame
                self?.refresh()
            })
            capsuleHost = capsule
            addSubview(capsule)
            let close = ControlHostingView(rootView: CloseButtonView(model: model) { [weak self] frame in
                self?.closeHost?.controlFrame = frame
                self?.refresh()
            })
            close.controlShape = AnyShape(Circle())
            closeHost = close
            addSubview(close)
            // Added last so it draws above the capsule and the close button.
            let tooltip = PassthroughHostingView(rootView: PanelTooltipView(model: model))
            tooltip.isHidden = true
            addSubview(tooltip)
            tooltipHost = tooltip
        }
        addSubview(badgeHost)
        badgeHost.isHidden = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Updates

    /// Redraws after a model change and repositions the hosted SwiftUI accessories.
    func refresh() {
        needsDisplay = true
        needsLayout = true
    }

    @objc private func accessibilityDisplayOptionsChanged(_ notification: Notification) {
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if let capsuleHost {
            let size = capsuleHost.fittingSize
            capsuleHost.frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(),
                                       y: bounds.height - size.height - 24,
                                       width: size.width, height: size.height)
        }
        if let closeHost {
            let size = closeHost.fittingSize
            closeHost.frame = CGRect(x: 8, y: 8, width: size.width, height: size.height)
        }
        if isPanelDisplay {
            let frames = [capsuleHost?.visibleControlFrame, closeHost?.visibleControlFrame]
                .compactMap { $0 }.filter { !$0.isEmpty }
                .map { $0.offsetBy(dx: info.frame.minX, dy: info.frame.minY) }
            model.setChromeFrames(frames)
        }
        layoutTooltip()
        if model.mode == .window, let id = model.selectedWindowID,
           let cell = model.cells(on: info).first(where: { $0.windowID == id }) {
            let size = badgeHost.fittingSize
            let rect = localRect(cell.rect)
            badgeHost.frame = CGRect(x: rect.maxX - size.width - 4, y: rect.minY + 4,
                                     width: size.width, height: size.height)
            badgeHost.isHidden = false
        } else {
            badgeHost.isHidden = true
        }
    }

    /// Places the hover tooltip centred on its control, above the capsule or below the close button.
    private func layoutTooltip() {
        guard let tooltipHost else { return }
        guard let tooltip = model.tooltip,
              let host: NSView = tooltip.source == .capturePanel ? capsuleHost : closeHost else {
            tooltipHost.isHidden = true
            return
        }
        let size = tooltipHost.fittingSize
        let gap: CGFloat = 4
        // Hosting views are flipped like this view, so the anchor offsets straight from the host's origin.
        let anchor = tooltip.anchor.offsetBy(dx: host.frame.minX, dy: host.frame.minY)
        let x = min(max(anchor.midX - size.width / 2, 8), bounds.width - size.width - 8)
        let y: CGFloat
        if tooltip.source == .capturePanel {
            guard let capsule = capsuleHost?.visibleControlFrame, !capsule.isEmpty else {
                tooltipHost.isHidden = true
                return
            }
            y = capsule.minY - size.height - gap
        } else {
            y = anchor.maxY + gap
        }
        tooltipHost.frame = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        tooltipHost.isHidden = false
    }

    // MARK: Coordinates

    private func localRect(_ globalRect: CGRect) -> CGRect {
        globalRect.offsetBy(dx: -info.frame.minX, dy: -info.frame.minY)
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        return CoordinateSpace.globalCGPoint(fromAppKit: screenPoint)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        (model.showPointer ? pointerImage : plainImage)
            .draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        switch model.mode {
        case .selection: drawSelection(in: context)
        case .screen: drawScreenOutline(in: context)
        case .window: drawWindowPicker(in: context)
        }
    }

    private func drawSelection(in context: CGContext) {
        let selection = localRect(model.editor.rect)

        let dim = CGMutablePath()
        dim.addRect(bounds)
        dim.addRect(selection)
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fillPath(using: .evenOdd)

        // A crisp 1-pt white border just outside the captured pixels.
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))

        for point in handlePoints(of: selection) {
            let rect = CGRect(x: point.x - Self.handleDiameter / 2, y: point.y - Self.handleDiameter / 2,
                              width: Self.handleDiameter, height: Self.handleDiameter)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
        }

        drawSizeLabel()
    }

    private func handlePoints(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.midY),
         CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.maxY),
         CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    private func drawSizeLabel() {
        let selection = model.editor.rect
        let text = "\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let pill = CGSize(width: textSize.width + 20, height: textSize.height + 8)
        let available = model.editor.bounds.insetBy(dx: 4, dy: 4)
        let x = min(max(selection.midX - pill.width / 2, available.minX), available.maxX - pill.width)
        let chrome = model.chromeFrames

        // Below the selection, else above, else inside — decided in global coordinates so every display agrees.
        let below = selection.maxY + 14
        let above = selection.minY - 14 - pill.height
        let inside = max(selection.maxY - pill.height - 12, available.minY)
        // If all three collide, try just outside the chrome, closest to the selection first.
        let edges: [CGFloat] = chrome.flatMap { [$0.minY - pill.height - 4, $0.maxY + 4] }
        let centredY = selection.midY - pill.height / 2
        let alternatives = edges.sorted { abs($0 - centredY) < abs($1 - centredY) }
        let candidates = ([below, above, inside] + alternatives).map {
            CGRect(x: x, y: $0, width: pill.width, height: pill.height)
        }
        guard let position = candidates.first(where: { candidate in
            available.contains(candidate) && !chrome.contains(where: { $0.intersects(candidate) })
        }) else { return }

        let rect = localRect(position)
        guard rect.intersects(bounds) else { return }
        let workspace = NSWorkspace.shared
        let solid = workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.black.withAlphaComponent(solid ? 1 : 0.65).setFill()
        shape.fill()
        if solid {
            NSColor.white.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        text.draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 4), withAttributes: attributes)
    }

    private func drawScreenOutline(in context: CGContext) {
        let selected = info.displayID == model.selectedDisplayID
        let accent = NSColor.controlAccentColor
        if selected {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), xRadius: 16, yRadius: 16)
            accent.withAlphaComponent(0.12).setFill()
            outline.fill()
            accent.setStroke()
            outline.lineWidth = 5
            outline.stroke()
        } else {
            NSColor.black.withAlphaComponent(0.45).setFill()
            bounds.fill()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), xRadius: 16, yRadius: 16)
            NSColor.white.withAlphaComponent(0.6).setStroke()
            outline.lineWidth = 2
            let dash: [CGFloat] = [8, 6]
            outline.setLineDash(dash, count: dash.count, phase: 0)
            outline.stroke()
        }
    }

    /// The thumbnail for `window`, from the same pointer variant the final capture will deliver.
    private func windowImage(for window: WindowSnapshot, size: CGSize) -> NSImage {
        let id = window.info.windowID
        if model.showPointer {
            if let cached = windowImagesWithPointer[id] { return cached }
            let created = NSImage(cgImage: window.imageWithPointer, size: size)
            windowImagesWithPointer[id] = created
            return created
        }
        if let cached = windowImages[id] { return cached }
        let created = NSImage(cgImage: window.image, size: size)
        windowImages[id] = created
        return created
    }

    private func drawWindowPicker(in context: CGContext) {
        NSColor.black.withAlphaComponent(0.6).setFill()
        bounds.fill()
        let accent = NSColor.controlAccentColor
        for cell in model.cells(on: info) {
            guard let window = model.snapshot(forWindow: cell.windowID) else { continue }
            let rect = localRect(cell.rect)
            let image = windowImage(for: window, size: rect.size)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                              color: NSColor.black.withAlphaComponent(0.5).cgColor)
            NSColor.black.setFill()
            shape.fill()
            context.restoreGState()

            context.saveGState()
            shape.addClip()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            context.restoreGState()

            if cell.windowID == model.selectedWindowID {
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 13, yRadius: 13)
                accent.setStroke()
                border.lineWidth = 4
                border.stroke()
            } else {
                NSColor.white.withAlphaComponent(0.25).setStroke()
                shape.lineWidth = 1
                shape.stroke()
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        beginInteraction(event, forceNew: event.modifierFlags.contains(.control))
    }

    override func rightMouseDown(with event: NSEvent) {
        beginInteraction(event, forceNew: true)
    }

    override func mouseDragged(with event: NSEvent) { continueDrag(event) }
    override func rightMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func mouseUp(with event: NSEvent) { endDrag(event) }
    override func rightMouseUp(with event: NSEvent) { endDrag(event) }

    private func beginInteraction(_ event: NSEvent, forceNew: Bool) {
        let point = globalPoint(for: event)
        switch model.mode {
        case .selection:
            dragHandle = forceNew ? .none : model.handle(at: point)
            isDragging = true
            model.dragBegan(at: point, forceNew: forceNew)
            applyCursor()
        case .screen:
            model.selectDisplay(info.displayID)
        case .window:
            model.selectWindow(at: point)
        }
    }

    private func continueDrag(_ event: NSEvent) {
        guard isDragging, model.mode == .selection else { return }
        model.dragMoved(to: globalPoint(for: event))
        applyCursor()
    }

    private func endDrag(_ event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        model.dragEnded(at: globalPoint(for: event))
        dragHandle = .none
        updateCursor(for: event)
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(for: event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(for: event) }

    private func updateCursor(for event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if capsuleHost?.containsControl(at: local) == true || closeHost?.containsControl(at: local) == true {
            NSCursor.arrow.set()
            return
        }
        let point = globalPoint(for: event)
        switch model.mode {
        case .selection:
            dragHandle = isDragging ? dragHandle : model.handle(at: point)
            applyCursor()
        case .screen:
            NSCursor.arrow.set()
        case .window:
            let overCell = model.windowCells.values.joined().contains { $0.rect.contains(point) }
            (overCell ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }

    /// Crosshair outside the Selection, hand inside, resize cursors on edges and corners.
    private func applyCursor() {
        let cursor: NSCursor = switch dragHandle {
        case .none: .crosshair
        case .move: isDragging ? .closedHand : .openHand
        case .top: .frameResize(position: .top, directions: .all)
        case .bottom: .frameResize(position: .bottom, directions: .all)
        case .left: .frameResize(position: .left, directions: .all)
        case .right: .frameResize(position: .right, directions: .all)
        case .topLeft: .frameResize(position: .topLeft, directions: .all)
        case .topRight: .frameResize(position: .topRight, directions: .all)
        case .bottomLeft: .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: .frameResize(position: .bottomRight, directions: .all)
        }
        cursor.set()
    }
}

/// A hosted control whose shadow padding passes mouse events through to the overlay.
private final class ControlHostingView<Content: View>: NSHostingView<Content> {
    var controlFrame = CGRect.zero
    var controlShape = AnyShape(Capsule())

    var visibleControlFrame: CGRect { convert(controlFrame, to: superview) }

    /// The hit-test point is in the superview's coordinates.
    func containsControl(at point: CGPoint) -> Bool {
        let rect = visibleControlFrame
        return !rect.isEmpty && controlShape.path(in: rect).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsControl(at: point) ? super.hitTest(point) : nil
    }
}
