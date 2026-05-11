#if os(macOS)
import SwiftUI
import ListedCore

/// Compact, dense version of `TaskRowView` used in the menu bar popover.
/// Redesigned with left-edge priority bars for instant scannability.
struct MenuBarTaskRow: View {
    @Environment(AppModel.self) private var model

    let task: TodoTask

    var body: some View {
        HStack(spacing: 0) {
            // Thin priority color bar
            if let priority = task.priority, !task.isCompleted {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DesignTokens.priorityColor(priority))
                    .frame(width: 2.5)
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
            }

            HStack(alignment: .center, spacing: 10) {
                CompletionToggle(
                    isCompleted: task.isCompleted,
                    tint: task.priority.map(DesignTokens.priorityColor) ?? DesignTokens.accent,
                    onToggle: { Task { await model.toggleCompletion(task) } }
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.cleanTitle.isEmpty ? "Untitled task" : task.cleanTitle)
                        .font(.callout.weight(task.isCompleted ? .regular : .medium))
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if model.activeTaskFiles.count > 1 {
                        Text(model.displayName(forTaskFileID: task.sourceFileID))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 6)

                if let due = task.dueDate {
                    let color = DesignTokens.dueColor(for: due)
                    let today = LocalDate.today()
                    Text(DesignTokens.dueLabel(for: due))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(due < today ? .white : color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(due < today ? color.opacity(0.85) : color.opacity(0.14))
                        )
                }
            }
        }
        .padding(.horizontal, task.priority != nil && !task.isCompleted ? 10 : 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .opacity(task.isCompleted ? 0.6 : 1.0)
    }
}
#endif
