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

    /// Accessibility elements for Window Picker cells on this display, built once and reused.
    private var windowCellElements: [WindowCellAccessibilityElement] = []
    private var lastAccessibilityMode: CaptureMode?

    private var isDragging = false
    private var dragHandle: SelectionHandle = .none

    private static let handleDiameter: CGFloat = 10
    private static let activeHandleDiameter: CGFloat = 14

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

        windowCellElements = buildWindowCellAccessibilityElements()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Updates

    /// Redraws after a model change and repositions the hosted SwiftUI accessories.
    func refresh() {
        syncWindowCellAccessibility()
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

    // MARK: Accessibility (Window Picker)

    private func buildWindowCellAccessibilityElements() -> [WindowCellAccessibilityElement] {
        model.cells(on: info).map { cell in
            let label = model.windowDisplayInfo(for: cell.windowID)?.accessibilityLabel
                ?? String(localized: "Window")
            let screenFrame = CoordinateSpace.appKitRect(fromGlobalCG: cell.rect)
            return WindowCellAccessibilityElement(
                windowID: cell.windowID,
                frame: screenFrame,
                label: label,
                parent: self
            ) { [weak model] in
                model?.selectWindow(id: cell.windowID)
            }
        }
    }

    private func syncWindowCellAccessibility() {
        for element in windowCellElements {
            element.setAccessibilitySelected(element.windowID == model.selectedWindowID)
        }
        if lastAccessibilityMode != model.mode {
            let crossedWindowMode = lastAccessibilityMode == .window || model.mode == .window
            lastAccessibilityMode = model.mode
            if crossedWindowMode {
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
        }
    }

    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        if model.mode == .window {
            children.append(contentsOf: windowCellElements)
        }
        return children
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        // NSAccessibility calls this nonisolated, but always on the main thread.
        nonisolated(unsafe) var cell: NSAccessibilityElement?
        MainActor.assumeIsolated { cell = windowCellElement(atScreenPoint: point) }
        return cell ?? super.accessibilityHitTest(point)
    }

    /// The Window Picker cell under a screen point, nil over the Capture Panel or close button.
    private func windowCellElement(atScreenPoint point: NSPoint) -> NSAccessibilityElement? {
        guard model.mode == .window else { return nil }
        if let window {
            let local = convert(window.convertPoint(fromScreen: point), from: nil)
            if capsuleHost?.containsControl(at: local) == true || closeHost?.containsControl(at: local) == true {
                return nil
            }
        }
        return windowCellElements.first(where: { $0.accessibilityFrame().contains(point) })
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

        let activeHandle = model.activeSelectionHandle
        var activePoint: CGPoint?
        for (handle, point) in handlePoints(of: selection) {
            if handle == activeHandle {
                activePoint = point
                continue
            }
            drawHandle(at: point, active: false, in: context)
        }
        if let activePoint {
            drawHandle(at: activePoint, active: true, in: context)
        }

        drawSizeLabel()
    }

    private func drawHandle(at point: CGPoint, active: Bool, in context: CGContext) {
        let diameter = active ? Self.activeHandleDiameter : Self.handleDiameter
        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                          width: diameter, height: diameter)
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if active {
            context.setFillColor(NSColor.controlAccentColor.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            context.setStrokeColor(NSColor.black.withAlphaComponent(highContrast ? 0.85 : 0.35).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: rect.insetBy(dx: -0.5, dy: -0.5))
        } else {
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(NSColor.black.withAlphaComponent(highContrast ? 0.75 : 0.35).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    private func handlePoints(of rect: CGRect) -> [(SelectionHandle, CGPoint)] {
        [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
         (.top, CGPoint(x: rect.midX, y: rect.minY)),
         (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
         (.left, CGPoint(x: rect.minX, y: rect.midY)),
         (.right, CGPoint(x: rect.maxX, y: rect.midY)),
         (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
         (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
         (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))]
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
        drawPillBackground(in: rect)
        text.draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 4), withAttributes: attributes)
    }

    private func drawScreenOutline(in context: CGContext) {
        let selected = info.displayID == model.selectedDisplayID
        let accent = NSColor.controlAccentColor
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if selected {
            let borderWidth: CGFloat = highContrast ? 6 : 4
            let insetRect = bounds.insetBy(dx: 6, dy: 6)
            // Subtle light outer hairline so the accent border stays crisp over accent-tinted wallpapers.
            let outer = NSBezierPath(roundedRect: insetRect.insetBy(dx: -(borderWidth / 2 + 0.5),
                                                                    dy: -(borderWidth / 2 + 0.5)),
                                     xRadius: 15, yRadius: 15)
            NSColor.white.withAlphaComponent(highContrast ? 0.9 : 0.35).setStroke()
            outer.lineWidth = 1
            outer.stroke()

            let outline = NSBezierPath(roundedRect: insetRect, xRadius: 14, yRadius: 14)
            accent.setStroke()
            outline.lineWidth = borderWidth
            outline.stroke()

            if model.displays.count > 1 {
                drawDisplayBadge()
            }
        } else {
            NSColor.black.withAlphaComponent(0.45).setFill()
            bounds.fill()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), xRadius: 16, yRadius: 16)
            NSColor.white.withAlphaComponent(highContrast ? 0.85 : 0.6).setStroke()
            outline.lineWidth = 2
            let dash: [CGFloat] = [8, 6]
            outline.setLineDash(dash, count: dash.count, phase: 0)
            outline.stroke()
        }
    }

    /// On multi-display setups, shows the selected display's name and pixel dimensions.
    private func drawDisplayBadge() {
        let name = model.displayName(for: info.displayID)
        let text = String(localized: "\(name) · \(snapshot.image.width) × \(snapshot.image.height)",
                          comment: "Selected display badge: display name and pixel dimensions") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 5
        let pillSize = CGSize(width: min(textSize.width + horizontalPadding * 2, bounds.width - 48),
                              height: textSize.height + verticalPadding * 2)
        let x = ((bounds.width - pillSize.width) / 2).rounded()
        let y: CGFloat = 24
        let rect = CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height)
        drawPillBackground(in: rect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        var clipped = attributes
        clipped[.paragraphStyle] = paragraph
        let textRect = CGRect(x: rect.minX + horizontalPadding,
                              y: rect.minY + verticalPadding,
                              width: rect.width - horizontalPadding * 2,
                              height: textSize.height)
        text.draw(in: textRect, withAttributes: clipped)
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
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let cells = model.cells(on: info)

        for cell in cells {
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
            } else if cell.windowID == model.hoveredWindowID {
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), xRadius: 11.5, yRadius: 11.5)
                NSColor.white.withAlphaComponent(highContrast ? 0.95 : 0.72).setStroke()
                border.lineWidth = 2
                border.stroke()
            } else {
                NSColor.white.withAlphaComponent(0.25).setStroke()
                shape.lineWidth = 1
                shape.stroke()
            }
        }

        // Draw title pills after all thumbnails so a neighbour's shadow never covers a pill.
        for cell in cells where cell.windowID == model.selectedWindowID || cell.windowID == model.hoveredWindowID {
            guard let displayInfo = model.windowDisplayInfo(for: cell.windowID) else { continue }
            drawWindowPill(for: cell, info: displayInfo)
        }
    }

    private func drawWindowPill(for cell: WindowCell, info displayInfo: WindowDisplayInfo) {
        let cellRect = localRect(cell.rect)
        let title = displayInfo.pillTitle as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]

        let iconSize: CGFloat = displayInfo.icon != nil ? 16 : 0
        let iconGap: CGFloat = displayInfo.icon != nil ? 6 : 0
        let horizontalPadding: CGFloat = 10
        let maxPillWidth = min(max(cellRect.width, 140), 280, bounds.width - 16)
        let maxTextWidth = max(maxPillWidth - horizontalPadding * 2 - iconSize - iconGap, 24)
        let measured = title.size(withAttributes: attributes)
        let textWidth = min(ceil(measured.width), maxTextWidth)
        let pillWidth = horizontalPadding * 2 + iconSize + iconGap + textWidth
        let pillHeight: CGFloat = max(ceil(measured.height), iconSize) + 8

        let clampedX = min(max(cellRect.midX - pillWidth / 2, 8), bounds.width - pillWidth - 8).rounded()
        let belowY = (cellRect.maxY + 8).rounded()
        let belowRect = CGRect(x: clampedX, y: belowY, width: pillWidth, height: pillHeight)
        let localChrome = model.chromeFrames.map { localRect($0) }
        let fitsBelow = belowRect.maxY <= bounds.height - 8
            && !localChrome.contains(where: { $0.intersects(belowRect) })
        let pillRect = fitsBelow
            ? belowRect
            : CGRect(x: clampedX, y: max(cellRect.maxY - pillHeight - 8, 8).rounded(),
                     width: pillWidth, height: pillHeight)

        drawPillBackground(in: pillRect)

        var contentX = pillRect.minX + horizontalPadding
        if let icon = displayInfo.icon {
            let iconRect = CGRect(x: contentX, y: pillRect.midY - iconSize / 2, width: iconSize, height: iconSize)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            contentX += iconSize + iconGap
        }
        let textRect = CGRect(x: contentX,
                              y: (pillRect.midY - measured.height / 2).rounded(),
                              width: textWidth,
                              height: ceil(measured.height))
        title.draw(in: textRect, withAttributes: attributes)
    }

    private func drawPillBackground(in rect: CGRect) {
        let workspace = NSWorkspace.shared
        let solid = workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.black.withAlphaComponent(solid ? 1 : 0.72).setFill()
        shape.fill()
        if solid {
            NSColor.white.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        } else {
            NSColor.white.withAlphaComponent(0.18).setStroke()
            shape.lineWidth = 1
            shape.stroke()
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
            model.setActiveSelectionHandle(dragHandle)
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
                                       options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(for: event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(for: event) }

    override func mouseExited(with event: NSEvent) {
        if model.mode == .selection, !isDragging {
            dragHandle = .none
            model.setActiveSelectionHandle(.none)
        }
        if model.mode == .window,
           let hovered = model.hoveredWindowID,
           model.cells(on: info).contains(where: { $0.windowID == hovered }) {
            model.setHoveredWindowID(nil)
        }
    }

    private func updateCursor(for event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if capsuleHost?.containsControl(at: local) == true || closeHost?.containsControl(at: local) == true {
            if model.mode == .selection, !isDragging {
                dragHandle = .none
                model.setActiveSelectionHandle(.none)
            }
            if model.mode == .window {
                model.setHoveredWindowID(nil)
            }
            NSCursor.arrow.set()
            return
        }
        let point = globalPoint(for: event)
        switch model.mode {
        case .selection:
            dragHandle = isDragging ? dragHandle : model.handle(at: point)
            model.setActiveSelectionHandle(dragHandle)
            applyCursor()
        case .screen:
            NSCursor.arrow.set()
        case .window:
            let hoveredID = model.windowCell(at: point)?.windowID
            model.setHoveredWindowID(hoveredID)
            (hoveredID != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
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

/// Exposes one Window Picker cell to VoiceOver with its screen frame, "App, Title" label, and press action.
private final class WindowCellAccessibilityElement: NSAccessibilityElement {
    let windowID: UInt32
    private let onPress: @MainActor @Sendable () -> Void

    @MainActor
    init(windowID: UInt32, frame: CGRect, label: String, parent: OverlayView,
         onPress: @escaping @MainActor @Sendable () -> Void) {
        self.windowID = windowID
        self.onPress = onPress
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityFrame(frame)
        setAccessibilityParent(parent)
        setAccessibilityElement(true)
    }

    override func accessibilityPerformPress() -> Bool {
        let onPress = onPress
        MainActor.assumeIsolated { onPress() }
        return true
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
