import SwiftUI
import ListedCore

/// Native circular completion control built from SF Symbols.
///
/// Uses `circle` / `checkmark.circle.fill` rendered as a `Button` so we inherit
/// the system's symbol rendering, accent tinting, and hover/press behavior on
/// macOS 26 / iOS 26 instead of drawing our own ring.
public struct CompletionToggle: View {
    var isCompleted: Bool
    var tint: Color?
    var onToggle: () -> Void

    public init(isCompleted: Bool, tint: Color? = nil, onToggle: @escaping () -> Void) {
        self.isCompleted = isCompleted
        self.tint = tint
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: onToggle) {
            Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint ?? .secondary)
                .accessibilityLabel(isCompleted ? "Mark as not done" : "Mark as done")
        }
        .buttonStyle(.plain)
    }
}
