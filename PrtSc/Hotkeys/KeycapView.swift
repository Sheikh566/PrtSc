import AppKit
import SwiftUI

/// A compact keyboard keycap badge for displaying shortcuts and in-UI keys inside standard macOS windows.
struct KeycapView: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.monospaced().weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.8),
                        lineWidth: 1
                    )
            }
            .fixedSize()
    }
}
