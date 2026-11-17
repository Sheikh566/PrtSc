import PrtScCore
import SwiftUI

/// The Capture Panel: a Liquid Glass capsule with the Capture Mode buttons, the capture button and the
/// Show Pointer toggle.
struct CapturePanelView: View {
    let model: ScreenshotUIModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 14) {
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
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Capture Panel"))
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
        .help(mode.localizedTitle)
        .accessibilityLabel(Text(mode.localizedTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])

        if selected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var captureButton: some View {
        Button {
            model.capture()
        } label: {
            Image(systemName: "camera.fill")
                .font(.title)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .help(Text("Capture"))
        .accessibilityLabel(Text("Capture"))
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
        .help(Text("Show Pointer"))
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
            .help(Text("Close"))
            .accessibilityLabel(Text("Close"))
        }
        .padding(16)
    }
}

/// The check-mark badge on the selected window in the Window Picker.
struct WindowBadgeView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: "checkmark")
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .glassOrSolid(in: .circle, reduceTransparency: reduceTransparency)
            .padding(8)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Liquid Glass, or an opaque background when Reduce Transparency is on.
    @ViewBuilder
    fileprivate func glassOrSolid<S: Shape>(in shape: S, reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            self
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.stroke(Color.primary.opacity(0.25), lineWidth: 1) }
        } else {
            self.glassEffect(.regular.interactive(), in: shape)
        }
    }
}
