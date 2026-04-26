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
            // Land focus on the composer for instant keyboard capture.
            composerFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var headerSubtitle: String {
        let count = todaysTasks.count
        let overdue = todaysTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return due < LocalDate.today()
        }.count
        if count == 0 { return "Nothing due today" }
        if overdue == 0 {
            return count == 1 ? "1 task due" : "\(count) tasks due"
        }
        return "\(count) due • \(overdue) overdue"
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

    /// Today's + overdue tasks across **all enabled active files**, regardless of
    /// what the main window's sidebar is currently showing.
    private var todaysTasks: [TodoTask] {
        let q = TaskQuery(scope: .smartList(.today), searchText: "", sort: .default, includeCompleted: false)
        return QueryEngine().run(query: q, files: model.loadedFiles, taskFiles: model.workspace.taskFiles)
    }

    private var taskList: some View {
        Group {
            if todaysTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(todaysTasks) { task in
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
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("All caught up")
                .font(.headline)
            Text("Nothing due today.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            footerButton(label: "Upcoming", count: count(for: .upcoming)) {
                openMainWindow(selecting: .smartList(.upcoming))
            }
            footerButton(label: "All", count: count(for: .all)) {
                openMainWindow(selecting: .smartList(.all))
            }
            Spacer()
            Menu {
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

    private func footerButton(label: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label).font(.callout)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.secondary.opacity(0.15)))
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func count(for kind: TaskQuery.SmartList) -> Int {
        model.taskCount(for: .smartList(kind))
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
