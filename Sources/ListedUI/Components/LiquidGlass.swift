import SwiftUI

/// Glass morphism affordances for macOS 26 / iOS 26, plus refined card styling
/// that serves as the foundation for the card-based UI refresh.
public extension View {

    /// Apply a Liquid Glass capsule background. Used for chips, floating composers,
    /// and the new-task button.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if let tint {
            self.padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular.tint(tint.opacity(0.25)), in: Capsule())
        } else {
            self.padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
        }
    }

    /// Apply a Liquid Glass rounded-rectangle background. Used for cards.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = DesignTokens.cardCornerRadius) -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Refined card surface: subtle fill + thin border for layered depth.
    /// Used as the standard card background throughout the detail pane and sheets.
    @ViewBuilder
    func refinedCard(cornerRadius: CGFloat = DesignTokens.cardCornerRadius) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.background.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                )
        }
    }
}
