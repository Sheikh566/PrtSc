import AppKit
import PrtScCore
import SwiftUI

/// The Capture Panel: a single Liquid Glass capsule with borderless segmented groups for Capture Type
/// (Screenshot | Screencast) and Capture Mode (Selection | Screen | Window), a prominent circular
/// shutter/record button, and a borderless Show Pointer toggle.
struct CapturePanelView: View {
    let model: ScreenshotUIModel
    let onControlFrameChange: (CGRect) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @Namespace private var captureTypeNamespace
    @Namespace private var captureModeNamespace
    @State private var appeared = false
    @State private var hoveredType: CaptureType?
    @State private var hoveredMode: CaptureMode?
    @State private var pointerHovered = false

    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2, extraBounce: 0)
    }

    private var trackFill: Color {
        Color.primary.opacity(reduceTransparency ? 0.08 : 0.07)
    }

    private var selectedPillFill: Color {
        if contrast == .increased {
            return Color.primary.opacity(0.24)
        }
        return Color.primary.opacity(reduceTransparency ? 0.16 : 0.17)
    }

    private var selectedPillStroke: Color {
        Color.primary.opacity(contrast == .increased ? 0.55 : 0.14)
    }

    var body: some View {
        HStack(spacing: 12) {
            captureTypeGroup
            panelDivider
            captureModeGroup
            panelDivider
            captureButton
            panelDivider
            pointerButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassOrSolid(in: .capsule, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(panelTooltipSpace)) } action: {
            onControlFrameChange($0)
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(transitionAnimation, value: model.captureType)
        .animation(transitionAnimation, value: model.mode)
        .animation(transitionAnimation, value: model.showPointer)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    appeared = true
                }
            }
        }
        .padding(24)
        .coordinateSpace(.named(panelTooltipSpace))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Capture Panel"))
    }

    private var panelDivider: some View {
        Capsule()
            .fill(Color.primary.opacity(contrast == .increased ? 0.35 : 0.16))
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }

    // MARK: - Capture Type

    private var captureTypeGroup: some View {
        HStack(spacing: 2) {
            ForEach(CaptureType.allCases, id: \.self) { type in
                typeButton(type)
            }
        }
        .padding(3)
        .background(trackFill, in: .capsule)
        .overlay {
            if contrast == .increased {
                Capsule().stroke(Color.primary.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Capture Type"))
    }

    private func typeButton(_ type: CaptureType) -> some View {
        let selected = model.captureType == type
        let hovered = hoveredType == type && !selected
        return Button {
            model.setCaptureType(type)
        } label: {
            Label(type.localizedTitle, systemImage: type.symbolName)
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(width: 36, height: 36)
                .background {
                    if selected {
                        Capsule()
                            .fill(selectedPillFill)
                            .overlay { Capsule().stroke(selectedPillStroke, lineWidth: 1) }
                            .matchedGeometryEffect(id: "selectedCaptureType", in: captureTypeNamespace)
                    } else if hovered {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(.capsule)
                .onHover { hovering in
                    hoveredType = hovering ? type : (hoveredType == type ? nil : hoveredType)
                }
        }
        .buttonStyle(PanelControlButtonStyle(reduceMotion: reduceMotion))
        .panelTooltip(type.localizedTitle, shortcut: "V", id: .captureType(type.rawValue), model: model)
        .accessibilityLabel(Text(type.localizedTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Capture Mode

    private var captureModeGroup: some View {
        HStack(spacing: 2) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }
        }
        .padding(3)
        .background(trackFill, in: .capsule)
        .overlay {
            if contrast == .increased {
                Capsule().stroke(Color.primary.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Capture Mode"))
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let selected = model.mode == mode
        let disabled = mode == .window && !model.windowModeAvailable
        let hovered = hoveredMode == mode && !selected && !disabled
        return Button {
            model.setMode(mode)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .frame(height: 16)
                Text(mode.localizedTitle)
                    .font(.caption2.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .opacity(disabled ? 0.38 : 1)
            .frame(minWidth: 58, minHeight: 36)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background {
                if selected {
                    Capsule()
                        .fill(selectedPillFill)
                        .overlay { Capsule().stroke(selectedPillStroke, lineWidth: 1) }
                        .matchedGeometryEffect(id: "selectedCaptureMode", in: captureModeNamespace)
                } else if hovered {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(.capsule)
            .onHover { hovering in
                hoveredMode = hovering ? mode : (hoveredMode == mode ? nil : hoveredMode)
            }
        }
        .buttonStyle(PanelControlButtonStyle(reduceMotion: reduceMotion))
        .disabled(disabled)
        .panelTooltip(mode.localizedTitle, shortcut: mode.shortcutKey, id: .mode(mode.rawValue), model: model)
        .accessibilityLabel(Text(mode.localizedTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Capture / Record

    /// Prominent circular shutter button for a screenshot; red record button for a Screencast.
    private var captureButton: some View {
        let recording = model.captureType == .screencast
        let accent: Color = recording ? .red : Color(nsColor: .controlAccentColor)
        let symbolTransition: ContentTransition = reduceMotion ? .identity : .symbolEffect(.replace)
        return Button {
            model.capture()
        } label: {
            Image(systemName: recording ? "record.circle.fill" : "camera.aperture")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(symbolTransition)
                .frame(width: 38, height: 38)
                .background(accent, in: .circle)
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(contrast == .increased ? 1 : 0.78), lineWidth: 2)
                }
                .contentShape(.circle)
        }
        .buttonStyle(ShutterButtonStyle(reduceMotion: reduceMotion))
        .panelTooltip(recording ? String(localized: "Record") : String(localized: "Capture"),
                      shortcut: "↩", id: .capture, model: model)
        .accessibilityLabel(recording ? Text("Record") : Text("Capture"))
    }

    // MARK: - Show Pointer

    private var pointerButton: some View {
        let on = model.showPointer
        let accent = Color(nsColor: .controlAccentColor)
        return Button {
            model.togglePointer()
        } label: {
            Label("Show Pointer", systemImage: "cursorarrow")
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? accent : .secondary)
                .frame(width: 38, height: 38)
                .background {
                    if on {
                        Circle()
                            .fill(accent.opacity(reduceTransparency ? 0.24 : 0.22))
                            .overlay {
                                Circle().stroke(accent.opacity(contrast == .increased ? 0.95 : 0.55), lineWidth: 1.5)
                            }
                    } else if pointerHovered {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(.circle)
                .onHover { pointerHovered = $0 }
        }
        .buttonStyle(PanelControlButtonStyle(reduceMotion: reduceMotion))
        .panelTooltip(String(localized: "Show Pointer"), shortcut: "P", id: .pointer, model: model)
        .accessibilityLabel(Text("Show Pointer"))
        .accessibilityValue(Text(on ? "On" : "Off"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Subtle press feedback for borderless controls inside the Capture Panel.
private struct PanelControlButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Tactile press feedback for the prominent circular shutter / record button.
private struct ShutterButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// The separate round close button at the top-left of the Capture Panel's display.
struct CloseButtonView: View {
    let model: ScreenshotUIModel
    let onControlFrameChange: (CGRect) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency {
                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Color(nsColor: .windowBackgroundColor), in: .circle)
                        .overlay {
                            Circle().stroke(Color.primary.opacity(contrast == .increased ? 0.6 : 0.25), lineWidth: 1)
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(PanelControlButtonStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(Text("Close"))
            } else {
                GlassEffectContainer {
                    Button {
                        model.close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .panelTooltip(String(localized: "Close"), shortcut: "Esc", id: .close, source: .closeButton,
                      model: model)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(panelTooltipSpace)) } action: {
            onControlFrameChange($0)
        }
        .padding(16)
        .coordinateSpace(.named(panelTooltipSpace))
    }
}

/// The check-mark badge on the selected window in the Window Picker.
struct WindowBadgeView: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color(nsColor: .controlAccentColor), in: .circle)
            .padding(8)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Liquid Glass, or an opaque background when Reduce Transparency is on.
    @ViewBuilder
    func glassOrSolid<S: Shape>(in shape: S, reduceTransparency: Bool, increasedContrast: Bool = false) -> some View {
        if reduceTransparency {
            self
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(increasedContrast ? 0.6 : 0.25), lineWidth: 1)
                }
        } else {
            self
                .glassEffect(.regular, in: shape)
                .overlay {
                    if increasedContrast {
                        shape.stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
        }
    }
}
