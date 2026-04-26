#if os(macOS)
import SwiftUI
import ListedCore

/// Compact, dense version of `TaskRowView` used in the menu bar popover.
///
/// Same conceptual shape as the main row (priority badge + checkbox + title +
/// due chip) but smaller and without the project/context chip rows, since the
/// popover is meant for "glance and tap done."
struct MenuBarTaskRow: View {
    @Environment(AppModel.self) private var model

    let task: TodoTask

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CompletionToggle(
                isCompleted: task.isCompleted,
                tint: task.priority.map(DesignTokens.priorityColor) ?? .accentColor,
                onToggle: { Task { await model.toggleCompletion(task) } }
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let priority = task.priority {
                        Text(String(priority))
                            .font(.caption2.bold())
                            .frame(width: 14, height: 14)
                            .background(
                                Circle().fill(DesignTokens.priorityColor(priority).opacity(0.18))
                            )
                            .foregroundStyle(DesignTokens.priorityColor(priority))
                    }
                    Text(task.cleanTitle.isEmpty ? "Untitled task" : task.cleanTitle)
                        .font(.callout)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if model.activeTaskFiles.count > 1 {
                    Text(model.displayName(forTaskFileID: task.sourceFileID))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            if let due = task.dueDate {
                Text(DesignTokens.dueLabel(for: due))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignTokens.dueColor(for: due))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(DesignTokens.dueColor(for: due).opacity(0.14))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
#endif
