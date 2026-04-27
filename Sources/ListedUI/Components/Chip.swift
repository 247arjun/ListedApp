import SwiftUI

/// Pill-shaped chip used for projects, contexts, due dates, and counts.
///
/// On macOS 26 / iOS 26 the chip uses a Liquid Glass background via `.glassEffect()`
/// when available; older runtimes fall back to a tinted material capsule.
public struct Chip: View {
    public enum Style {
        case neutral
        case accent(Color)
    }

    private let text: String
    private let systemImage: String?
    private let style: Style

    public init(_ text: String, systemImage: String? = nil, style: Style = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foregroundColor)
        .background(background)
    }

    private var foregroundColor: Color {
        switch style {
        case .neutral: return .primary
        case .accent(let color): return color
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .neutral:
            // Flat capsule — no glass effect, no drop shadow. Glass-tinted chips
            // looked nice in isolation but were dropping shadows under every
            // pill in the row, which read as visual noise.
            Capsule().fill(.thinMaterial)
        case .accent(let color):
            Capsule().fill(color.opacity(0.18))
        }
    }
}
