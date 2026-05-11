import SwiftUI

/// Pill-shaped chip used for projects, contexts, due dates, and counts.
///
/// Three visual styles:
///   - `.neutral`  — subtle material background, primary text
///   - `.filled(Color)` — solid tinted background, white/accent text (for due dates, urgent items)
///   - `.outlined(Color)` — bordered capsule, tinted text (for contexts)
///   - `.accent(Color)` — tinted background at 18% opacity, accent text (for projects)
public struct Chip: View {
    public enum Style {
        case neutral
        case accent(Color)
        case filled(Color)
        case outlined(Color)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(foregroundColor)
        .background(background)
    }

    private var foregroundColor: Color {
        switch style {
        case .neutral:           return .primary
        case .accent(let color): return color
        case .filled(let color): return color == .red || color == .orange ? .white : color
        case .outlined(let color): return color
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .neutral:
            Capsule().fill(.thinMaterial)
        case .accent(let color):
            Capsule().fill(color.opacity(0.14))
        case .filled(let color):
            Capsule().fill(color.opacity(color == .red || color == .orange ? 0.85 : 0.18))
        case .outlined(let color):
            Capsule()
                .strokeBorder(color.opacity(0.35), lineWidth: 1.2)
                .background(Capsule().fill(color.opacity(0.06)))
        }
    }
}
