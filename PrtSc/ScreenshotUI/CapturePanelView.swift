import PrtScCore
import SwiftUI

/// The Capture Panel: a Liquid Glass capsule with the Capture Type toggle (Screenshot | Screencast), the
/// Capture Mode buttons, the capture (or, for a Screencast, record) button and the Show Pointer toggle.
struct CapturePanelView: View {
    let model: ScreenshotUIModel
    let onControlFrameChange: (CGRect) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(CaptureType.allCases, id: \.self) { type in
                        typeButton(type)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Capture Type"))

                HStack(spacing: 6) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        modeButton(mode)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Capture Mode"))

                captureButton

                pointerButton
            }
            .padding(10)
            .glassOrSolid(in: .capsule, reduceTransparency: reduceTransparency)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(panelTooltipSpace)) } action: {
                onControlFrameChange($0)
            }
        }
        .padding(24)
        .coordinateSpace(.named(panelTooltipSpace))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Capture Panel"))
    }

    @ViewBuilder
    private func typeButton(_ type: CaptureType) -> some View {
        let selected = model.captureType == type
        let button = Button {
            model.setCaptureType(type)
        } label: {
            Label(type.localizedTitle, systemImage: type.symbolName)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 30, height: 26)
        }
        .panelTooltip(type.localizedTitle, shortcut: "V", id: .captureType(type.rawValue), model: model)
        .accessibilityLabel(Text(type.localizedTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])

        if selected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: CaptureMode) -> some View {
        let selected = model.mode == mode
        let button = Button {
            model.setMode(mode)
        } label: {
            Label(mode.localizedTitle, systemImage: mode.symbolName)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 30, height: 26)
        }
        .disabled(mode == .window && !model.windowModeAvailable)
        .panelTooltip(mode.localizedTitle, shortcut: mode.shortcutKey, id: .mode(mode.rawValue), model: model)
        .accessibilityLabel(Text(mode.localizedTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])

        if selected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    /// The camera button for a screenshot; a red record button for a Screencast.
    @ViewBuilder
    private var captureButton: some View {
        let recording = model.captureType == .screencast
        Button {
            model.capture()
        } label: {
            Image(systemName: recording ? "record.circle.fill" : "camera.fill")
                .font(.title)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(recording ? .red : nil)
        .panelTooltip(recording ? String(localized: "Record") : String(localized: "Capture"),
                      shortcut: "↩", id: .capture, model: model)
        .accessibilityLabel(recording ? Text("Record") : Text("Capture"))
    }

    @ViewBuilder
    private var pointerButton: some View {
        let button = Button {
            model.togglePointer()
        } label: {
            Label("Show Pointer", systemImage: "cursorarrow")
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 30, height: 26)
        }
        .panelTooltip(String(localized: "Show Pointer"), shortcut: "P", id: .pointer, model: model)
        .accessibilityLabel(Text("Show Pointer"))
        .accessibilityValue(Text(model.showPointer ? "On" : "Off"))
        .accessibilityAddTraits(model.showPointer ? .isSelected : [])

        if model.showPointer {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

/// The separate round close button at the top-left of the Capture Panel's display.
struct CloseButtonView: View {
    let model: ScreenshotUIModel
    let onControlFrameChange: (CGRect) -> Void

    var body: some View {
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
            .panelTooltip(String(localized: "Close"), shortcut: "Esc", id: .close, source: .closeButton,
                          model: model)
            .accessibilityLabel(Text("Close"))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(panelTooltipSpace)) } action: {
                onControlFrameChange($0)
            }
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
    func glassOrSolid<S: Shape>(in shape: S, reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            self
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.stroke(Color.primary.opacity(0.25), lineWidth: 1) }
        } else {
            self.glassEffect(.regular, in: shape)
        }
    }
}
