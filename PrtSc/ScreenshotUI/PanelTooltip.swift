import AppKit
import SwiftUI

/// A hover tooltip for a Screenshot UI control: its name and keyboard shortcut.
///
/// AppKit's standard tooltips (`.help`) are drawn in a window below the overlay's `.screenSaver` level,
/// so they never appear over the Screenshot UI. These are drawn by `OverlayView` instead.
struct PanelTooltip: Equatable, Identifiable {
    enum ID: Hashable {
        case captureType(String), mode(String), capture, pointer, close
    }

    /// Which hosted accessory the control lives in; decides where the tooltip is placed.
    enum Source: Equatable {
        case capturePanel   // shown above the capsule
        case closeButton    // shown below the control
    }

    let id: ID
    let title: String
    let shortcut: String
    let source: Source
    /// The control's frame in its hosting view's coordinates (top-left origin).
    let anchor: CGRect
}

extension View {
    /// Shows a `PanelTooltip` with `title` and `shortcut` after hovering the control briefly.
    func panelTooltip(_ title: String, shortcut: String, id: PanelTooltip.ID,
                      source: PanelTooltip.Source = .capturePanel,
                      model: ScreenshotUIModel) -> some View {
        modifier(PanelTooltipModifier(title: title, shortcut: shortcut, id: id, source: source, model: model))
    }
}

/// The coordinate space of each hosting view's root, used to anchor tooltips.
let panelTooltipSpace = "PrtScPanelTooltipSpace"

private struct PanelTooltipModifier: ViewModifier {
    let title: String
    let shortcut: String
    let id: PanelTooltip.ID
    let source: PanelTooltip.Source
    let model: ScreenshotUIModel

    @State private var frame: CGRect = .zero
    @State private var latestTooltip: PanelTooltip?
    @State private var hoverTask: Task<Void, Never>?

    private static let delay: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        let tooltip = PanelTooltip(id: id, title: title, shortcut: shortcut, source: source, anchor: frame)
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(panelTooltipSpace)) } action: {
                frame = $0
            }
            .onChange(of: tooltip, initial: true) { _, newTooltip in
                latestTooltip = newTooltip
                if model.tooltip?.id == id { model.setTooltip(newTooltip) }
            }
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: Self.delay)
                        guard !Task.isCancelled else { return }
                        if let latestTooltip { model.setTooltip(latestTooltip) }
                    }
                } else {
                    hoverTask = nil
                    model.clearTooltip(id: id)
                }
            }
            .onDisappear {
                hoverTask?.cancel()
                model.clearTooltip(id: id)
            }
    }
}

/// The tooltip bubble: name, then the shortcut as a bordered monospaced keycap.
struct PanelTooltipView: View {
    let model: ScreenshotUIModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isVisible = false

    var body: some View {
        if let tooltip = model.tooltip {
            HStack(spacing: 6) {
                Text(tooltip.title)
                    .font(.caption.weight(.medium))
                Text(tooltip.shortcut)
                    .font(.caption.monospaced().weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(
                                Color.primary.opacity(contrast == .increased ? 0.55 : 0.22),
                                lineWidth: 1
                            )
                    }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .fixedSize()
            .tooltipBackground(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
            .padding(4)
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    isVisible = false
                    withAnimation(.easeOut(duration: 0.14)) {
                        isVisible = true
                    }
                }
            }
            .onDisappear {
                isVisible = false
            }
            .accessibilityHidden(true) // the controls already carry labels
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func tooltipBackground(reduceTransparency: Bool, increasedContrast: Bool) -> some View {
        if reduceTransparency {
            self
                .background(Color(nsColor: .windowBackgroundColor), in: .capsule)
                .overlay {
                    Capsule().stroke(Color.primary.opacity(increasedContrast ? 0.6 : 0.25), lineWidth: 1)
                }
        } else {
            self
                .glassEffect(.regular, in: .capsule)
                .overlay {
                    if increasedContrast {
                        Capsule().stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
        }
    }
}

/// A hosting view that never takes mouse events, so the tooltip can't block the Screenshot UI.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
