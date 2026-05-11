import SwiftUI
import ListedCore

/// Circular completion control with satisfying bounce animation and haptic feedback.
///
/// Uses `circle` / `checkmark.circle.fill` with a spring scale animation on toggle,
/// plus `.sensoryFeedback` on iOS for a tactile reward on every completion.
public struct CompletionToggle: View {
    var isCompleted: Bool
    var tint: Color?
    var onToggle: () -> Void

    @State private var bouncing: Bool = false

    public init(isCompleted: Bool, tint: Color? = nil, onToggle: @escaping () -> Void) {
        self.isCompleted = isCompleted
        self.tint = tint
        self.onToggle = onToggle
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                bouncing = true
            }
            onToggle()
            // Reset bounce after animation settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                bouncing = false
            }
        } label: {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isCompleted ? (tint ?? DesignTokens.accent) : (tint ?? .secondary))
                .scaleEffect(bouncing ? 1.25 : 1.0)
                .accessibilityLabel(isCompleted ? "Mark as not done" : "Mark as done")
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: isCompleted)
        #endif
    }
}
