import SwiftUI
import ListedCore

/// One row in the main task list.
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
        HStack(alignment: .top, spacing: 12) {
            CompletionToggle(
                isCompleted: task.isCompleted,
                tint: task.priority.map(DesignTokens.priorityColor) ?? .accentColor,
                onToggle: { Task { await model.toggleCompletion(task) } }
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                titleLine
                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            chip.view
                        }
                    }
                }
                if showSourceBadge {
                    Text(model.displayName(forTaskFileID: task.sourceFileID))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let due = task.dueDate {
                dueChip(due)
            } else if let warning = task.parseWarnings.first {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(warning.message)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            if let priority = task.priority {
                Text(String(priority))
                    .font(.caption.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(DesignTokens.priorityColor(priority).opacity(0.15))
                    )
                    .foregroundStyle(DesignTokens.priorityColor(priority))
            }
            Text(rowTitle.isEmpty ? "Untitled task" : rowTitle)
                .font(.body)
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(2)
        }
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
            result.append(.init(id: "p:\(project)", view: AnyView(Chip("+\(project)", style: .accent(.blue)))))
        }
        for context in task.contexts {
            result.append(.init(id: "c:\(context)", view: AnyView(Chip("@\(context)", style: .accent(.purple)))))
        }
        return result
    }

    private func dueChip(_ date: LocalDate) -> some View {
        let label = DesignTokens.dueLabel(for: date)
        let color = DesignTokens.dueColor(for: date)
        return Chip(label, systemImage: "calendar", style: .accent(color))
    }
}
