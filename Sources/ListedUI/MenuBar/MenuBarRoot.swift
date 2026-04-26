#if os(macOS)
import SwiftUI
import ListedCore
import AppKit

/// Compact "Today + overdue" view shown from Listed's menu bar item.
///
/// The menu bar popover is a second view of the same `AppModel` that powers the
/// main window — completing a task here is reflected in the main window
/// instantly because both observe the same `@Observable` model.
public struct MenuBarRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    @State private var newTaskText: String = ""
    @FocusState private var composerFocused: Bool
    /// Which smart list the popover is currently showing. Defaults to Today on
    /// every popover open; the footer pills let the user switch between Today,
    /// Upcoming and All without leaving the menu bar.
    @State private var scope: TaskQuery.SmartList = .today

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            quickAddRow
            Divider()
            taskList
            Divider()
            footer
        }
        .frame(width: 360)
        .frame(minHeight: 320, idealHeight: 480, maxHeight: 600)
        .onAppear {
            // Refresh in the background each time the popover opens so
            // remote edits show up without forcing the user to open the
            // main window first.
            model.startBackgroundRefresh()
            // Always reset to Today when the popover re-opens.
            scope = .today
            // Land focus on the composer for instant keyboard capture.
            composerFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scopeTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Open Listed")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
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

    // MARK: - Quick add

    private var quickAddRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
            TextField("Add a task\u{2026}", text: $newTaskText)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .onSubmit { submit() }
            if !newTaskText.isEmpty {
                Button("Add") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        // Keep focus so the user can keep adding tasks rapid-fire.
        composerFocused = true
    }

    // MARK: - List

    /// Tasks for the currently-selected `scope` across **all enabled active
    /// files** — deliberately independent of the main window's sidebar.
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
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyIcon)
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyIcon: String {
        switch scope {
        case .today: return "checkmark.seal.fill"
        case .upcoming: return "calendar"
        case .all: return "tray"
        case .inbox: return "tray"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .today: return "All caught up"
        case .upcoming: return "Nothing upcoming"
        case .all: return "No tasks yet"
        case .inbox: return "Inbox empty"
        case .completed: return "Nothing completed"
        }
    }

    private var emptyMessage: String {
        switch scope {
        case .today: return "Nothing due today."
        case .upcoming: return "No future due dates."
        case .all: return "Add a task above to get started."
        case .inbox: return "No untagged tasks."
        case .completed: return "Completed tasks will appear here."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            scopePill(.today, label: "Today")
            scopePill(.upcoming, label: "Upcoming")
            scopePill(.all, label: "All")
            Spacer()
            Menu {
                Button("Open Listed") { openMainWindow() }
                Divider()
                Button("Settings\u{2026}") {
                    openSettings()
                }
                Divider()
                Button("Quit Listed") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// One scope-switch pill in the footer. Active scope is highlighted with the
    /// accent color; tapping switches the popover's `scope` state with a smooth
    /// crossfade.
    private func scopePill(_ kind: TaskQuery.SmartList, label: String) -> some View {
        let isActive = scope == kind
        let count = model.taskCount(for: .smartList(kind))
        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                scope = kind
            }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.callout.weight(isActive ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? Color.white : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isActive ? Color.accentColor : Color.secondary.opacity(0.15)
                            )
                        )
                }
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isActive ? Color.accentColor.opacity(0.12) : Color.clear
                )
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
        // Activate the app and bring up the main window. Using `openWindow`
        // ensures the existing scene with id "main" is reused.
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            // macOS 14+ "Settings" scene; SwiftUI installs an action with this selector.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
#endif
