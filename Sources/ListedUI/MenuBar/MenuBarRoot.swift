#if os(macOS)
import SwiftUI
import ListedCore
import AppKit

/// Compact menu bar popover — redesigned as a jewel box with tinted gradient header,
/// prominent quick-add field, and sliding scope selector.
public struct MenuBarRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    @State private var newTaskText: String = ""
    @FocusState private var composerFocused: Bool
    @State private var scope: TaskQuery.SmartList = .today

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            quickAddRow
            Divider()
            taskList
            Divider()
            footer
        }
        .frame(width: 380)
        .frame(minHeight: 340, idealHeight: 500, maxHeight: 620)
        .onAppear {
            model.startBackgroundRefresh()
            scope = model.workspace.settings.menuBarDefaultScope
            composerFocused = true
        }
    }

    // MARK: - Tinted gradient header

    private var header: some View {
        let tint = DesignTokens.smartListColor(for: scope)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scopeTitle)
                        .font(.title3.weight(.semibold))
                        .contentTransition(.numericText())
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button { openMainWindow() } label: {
                    Image(systemName: "macwindow")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Open Listed")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.1), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var scopeTitle: String {
        switch scope {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .all: return "All"
        case .inbox: return "Inbox"
        case .completed: return "Completed"
        }
    }

    private var headerSubtitle: String {
        let count = scopedTasks.count
        switch scope {
        case .today:
            let overdue = scopedTasks.filter { task in
                guard let due = task.dueDate else { return false }
                return due < LocalDate.today()
            }.count
            if count == 0 { return "Nothing due today" }
            if overdue == 0 {
                return count == 1 ? "1 task due" : "\(count) tasks due"
            }
            return "\(count) due \u{2022} \(overdue) overdue"
        case .upcoming:
            return count == 1 ? "1 upcoming task" : "\(count) upcoming tasks"
        case .all, .inbox, .completed:
            return count == 1 ? "1 task" : "\(count) tasks"
        }
    }

    // MARK: - Prominent quick add

    private var quickAddRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(DesignTokens.accent)
                .symbolRenderingMode(.hierarchical)
            TextField("Add a task\u{2026}", text: $newTaskText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($composerFocused)
                .onSubmit { submit() }
            if !newTaskText.isEmpty {
                Button("Add") { submit() }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func submit() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let fileID = model.defaultActiveFileID else { return }
        let dueDate = SmartInputParser.extractDueDate(from: trimmed)
        Task {
            await model.addTask(description: trimmed, in: fileID, dueDate: dueDate)
        }
        newTaskText = ""
        composerFocused = true
    }

    // MARK: - Task list

    private var scopedTasks: [TodoTask] {
        let q = TaskQuery(
            scope: .smartList(scope),
            searchText: "",
            sort: .default,
            includeCompleted: scope == .completed
        )
        return QueryEngine().run(query: q, files: model.loadedFiles, taskFiles: model.workspace.taskFiles)
    }

    private var taskList: some View {
        Group {
            if scopedTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(scopedTasks) { task in
                            MenuBarTaskRow(task: task)
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Contextual empty state

    private var emptyState: some View {
        let selection = SidebarSelection.smartList(scope)
        let icon = DesignTokens.emptyIcon(for: selection)
        let title = DesignTokens.emptyTitle(for: selection)
        let message = DesignTokens.emptySubtitle(for: selection)
        let tint = DesignTokens.smartListColor(for: scope)

        return VStack(spacing: DesignTokens.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer with sliding scope selector

    private var footer: some View {
        HStack(spacing: 4) {
            scopePill(.today, label: "Today")
            scopePill(.upcoming, label: "Upcoming")
            scopePill(.all, label: "All")
            Spacer()
            Menu {
                Button("Open Listed") { openMainWindow() }
                Divider()
                Button("Quit Listed") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func scopePill(_ kind: TaskQuery.SmartList, label: String) -> some View {
        let isActive = scope == kind
        let count = model.taskCount(for: .smartList(kind))
        let tint = DesignTokens.smartListColor(for: kind)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                scope = kind
            }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.callout.weight(isActive ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isActive ? tint : Color.secondary.opacity(0.12))
                        )
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(isActive ? tint : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isActive ? tint.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Window actions

    private func openMainWindow(selecting selection: SidebarSelection? = nil) {
        if let selection {
            model.selection = selection
        }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
#endif
