import SwiftUI
import ListedCore

/// One row in the main task list, rendered as a floating card with a left-edge
/// priority color bar for at-a-glance scanning.
public struct TaskRowView: View {
    @Environment(AppModel.self) private var model

    let task: TodoTask
    /// True when the row is rendered inside an aggregated view that mixes files.
    var showSourceBadge: Bool = true

    public init(task: TodoTask, showSourceBadge: Bool = true) {
        self.task = task
        self.showSourceBadge = showSourceBadge
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left-edge priority color bar — visible at peripheral-vision level.
            // Only shown for active tasks with a priority.
            if let priority = task.priority, !task.isCompleted {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DesignTokens.priorityColor(priority))
                    .frame(width: DesignTokens.priorityBarWidth)
                    .padding(.vertical, 6)
                    .padding(.trailing, 10)
            }

            // Main content lane
            HStack(alignment: .center, spacing: DesignTokens.spacingMD) {
                CompletionToggle(
                    isCompleted: task.isCompleted,
                    tint: task.priority.map(DesignTokens.priorityColor) ?? DesignTokens.accent,
                    onToggle: { Task { await model.toggleCompletion(task) } }
                )

                VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                    Text(rowTitle.isEmpty ? "Untitled task" : rowTitle)
                        .font(.body.weight(task.isCompleted ? .regular : .medium))
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Chips row below the title for cleaner hierarchy
                    if !chips.isEmpty || showSourceBadge {
                        HStack(spacing: 6) {
                            ForEach(chips, id: \.self) { chip in
                                chip.view
                            }
                            if showSourceBadge {
                                Text(model.displayName(forTaskFileID: task.sourceFileID))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

                // Trailing: due chip or warning
                if let due = task.dueDate {
                    dueChip(due)
                } else if let warning = task.parseWarnings.first {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(warning.message)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, task.priority != nil && !task.isCompleted ? 8 : DesignTokens.spacingLG)
        .padding(.trailing, DesignTokens.spacingLG)
        .frame(minHeight: 50, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(task.isCompleted ? 0.6 : 1.0)
    }

    /// Honors the "Show raw metadata in rows" Appearance toggle. When off (default)
    /// the row hides projects / contexts / metadata in the headline because the chips
    /// row already shows them. When on, we keep the legacy behavior of stripping
    /// only well-known structural `key:value` tokens.
    private var rowTitle: String {
        if model.workspace.settings.showRawMetadataInRows {
            return task.displayTitle
        }
        return task.cleanTitle
    }

    // MARK: - Chips

    private struct ChipDescriptor: Hashable {
        let id: String
        let view: AnyView

        static func == (lhs: ChipDescriptor, rhs: ChipDescriptor) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var chips: [ChipDescriptor] {
        var result: [ChipDescriptor] = []
        for project in task.projects {
            // Projects: filled accent chip
            result.append(.init(id: "p:\(project)", view: AnyView(Chip("+\(project)", style: .accent(.blue)))))
        }
        for context in task.contexts {
            // Contexts: outlined chip — visually distinct from projects
            result.append(.init(id: "c:\(context)", view: AnyView(Chip("@\(context)", style: .outlined(.purple)))))
        }
        return result
    }

    private func dueChip(_ date: LocalDate) -> some View {
        let label = DesignTokens.dueLabel(for: date)
        let color = DesignTokens.dueColor(for: date)
        let today = LocalDate.today()
        // Overdue tasks get a bold filled chip for urgency
        let style: Chip.Style = date < today ? .filled(color) : .accent(color)
        return Chip(label, systemImage: "calendar", style: style)
    }
}
