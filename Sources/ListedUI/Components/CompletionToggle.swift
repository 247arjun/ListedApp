import SwiftUI
import ListedCore

/// Animated check / circle used to toggle a task's completion.
public struct CompletionToggle: View {
    @Binding var isCompleted: Bool
    var priority: Character?
    var onToggle: () -> Void

    public init(isCompleted: Binding<Bool>, priority: Character? = nil, onToggle: @escaping () -> Void) {
        self._isCompleted = isCompleted
        self.priority = priority
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .stroke(borderColor, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                if isCompleted {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: isCompleted)
    }

    private var borderColor: Color {
        if let priority { return DesignTokens.priorityColor(priority) }
        return .secondary
    }
}
