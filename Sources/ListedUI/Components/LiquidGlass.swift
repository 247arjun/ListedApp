import SwiftUI

/// Liquid Glass affordances for macOS 26 / iOS 26.
///
/// We isolate the API behind small helpers so the rest of the codebase stays clean
/// and the app can adopt new system styling without scattering availability checks.
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
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
