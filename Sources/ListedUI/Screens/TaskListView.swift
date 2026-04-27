import SwiftUI
import ListedCore

/// The middle column of the macOS / iPad layout, and the primary screen on iPhone.
public struct TaskListView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var newTaskText: String = ""
    @FocusState private var newTaskFieldFocused: Bool

    public init() {}

    public var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            list
            // Inline composer takes a permanent slice of the screen — fine on
            // macOS where vertical space is plentiful, but wasteful on iPhone
            // where the toolbar `+` already opens a sheet for adding.
            #if os(macOS)
            inlineComposer
            #endif
        }
        .navigationTitle(navigationTitle)
        #if os(macOS)
        .navigationSubtitle(subtitle)
        .searchable(text: $bindable.searchText, prompt: "Search tasks, +project, @context, due:today")
        #else
        // On iPhone/iPad, dock the search field under the navigation title so the
        // "Search" affordance lives at the top with the other navigation chrome
        // (rather than at the bottom of the screen, which is reserved here for
        // task creation).
        .searchable(
            text: $bindable.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search tasks, +project, @context, due:today"
        )
        #endif
        .toolbar { toolbarItems }
    }

    private var navigationTitle: String {
        switch model.selection {
        case .smartList(let kind):
            switch kind {
            case .today: return "Today"
            case .upcoming: return "Upcoming"
            case .all: return "All"
            case .inbox: return "Inbox"
            case .completed: return "Completed"
            }
        case .file(let id):
            return model.displayName(forTaskFileID: id)
        case .project(let p): return "+\(p)"
        case .context(let c): return "@\(c)"
        case .priority(let p): return "Priority \(p)"
        }
    }

    private var subtitle: String {
        let count = model.visibleTasks.count
        return count == 1 ? "1 task" : "\(count) tasks"
    }

    // MARK: - List

    private var list: some View {
        Group {
            if model.visibleTasks.isEmpty {
                emptyState
            } else {
                listForCurrentPlatform
            }
        }
    }

    /// On iPhone (compact width) we **must not** pass a `selection:` binding to
    /// `List`. Selection mode swallows `NavigationLink` taps — the chevron
    /// highlights but the push never fires. Use a plain `List` there.
    /// macOS / iPad-regular keep the selection-driven list because that's what
    /// drives the third column of `NavigationSplitView`.
    @ViewBuilder
    private var listForCurrentPlatform: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            List {
                ForEach(model.visibleTasks) { task in
                    rowEntry(for: task)
                }
                .onMove(perform: handleMove)
            }
            .listStyle(.plain)
        } else {
            selectionList
        }
        #else
        selectionList
        #endif
    }

    private var selectionList: some View {
        List(selection: Binding(
            get: { model.selectedTaskID },
            set: { model.selectedTaskID = $0 }
        )) {
            ForEach(model.visibleTasks) { task in
                rowEntry(for: task)
            }
            .onMove(perform: handleMove)
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.plain)
        #endif
    }

    /// One list row. On iPhone (compact width) the row is wrapped in a
    /// `NavigationLink(value:)` so taps push to `TaskDetailView` via the
    /// `navigationDestination(for: TodoTaskID.self)` registered in
    /// `RootView.iPhoneRoot`. On macOS / iPad-regular the row uses
    /// `.tag(task.id)` so `List(selection:)` drives the third column of the
    /// `NavigationSplitView` instead.
    @ViewBuilder
    private func rowEntry(for task: TodoTask) -> some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            NavigationLink(value: task.id) {
                TaskRowView(task: task, showSourceBadge: showsSourceBadge)
            }
            .listRowBackground(rowBackground(for: task))
            .swipeActions(edge: .leading) {
                completionSwipeButton(for: task)
            }
            .swipeActions(edge: .trailing) {
                deleteSwipeButton(for: task)
            }
            .contextMenu {
                rowContextMenu(for: task)
            }
        } else {
            selectionRow(for: task)
        }
        #else
        selectionRow(for: task)
        #endif
    }

    /// Selection-driven row variant (no `NavigationLink` wrapper) used on macOS
    /// and regular-width iPad.
    private func selectionRow(for task: TodoTask) -> some View {
        TaskRowView(task: task, showSourceBadge: showsSourceBadge)
            .tag(task.id)
            .listRowBackground(rowBackground(for: task))
            .swipeActions(edge: .leading) {
                completionSwipeButton(for: task)
            }
            .swipeActions(edge: .trailing) {
                deleteSwipeButton(for: task)
            }
            .contextMenu {
                rowContextMenu(for: task)
            }
    }

    @ViewBuilder
    private func completionSwipeButton(for task: TodoTask) -> some View {
        Button {
            Task { await model.toggleCompletion(task) }
        } label: {
            Label(
                task.isCompleted ? "Reopen" : "Complete",
                systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
            )
        }
        .tint(.green)
    }

    @ViewBuilder
    private func deleteSwipeButton(for task: TodoTask) -> some View {
        Button(role: .destructive) {
            Task { await model.delete(task) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Drag-and-drop reordering. Constrained to **same file + same priority +
    /// same completion state**: dragging across priority buckets, between files,
    /// or between active/completed sections is silently ignored, because the
    /// visible list is sorted/filtered and a cross-bucket reorder wouldn't
    /// survive the next sort/partition. The new order is persisted as the
    /// actual line order in the underlying todo.txt file.
    private func handleMove(from source: IndexSet, to destination: Int) {
        guard let srcIdx = source.first, source.count == 1 else { return }
        let visible = model.visibleTasks
        let movingTask = visible[srcIdx]

        // Reordering completed tasks is meaningless: they all live in the
        // bottom section and the next mutation will re-partition them.
        guard !movingTask.isCompleted else { return }

        // Translate SwiftUI's destination (post-move insertion offset) into the
        // visible task we're landing adjacent to.
        let anchorIdx: Int
        if destination > srcIdx {
            anchorIdx = destination - 1
        } else {
            anchorIdx = destination
        }
        guard anchorIdx >= 0, anchorIdx < visible.count, anchorIdx != srcIdx else { return }
        let anchor = visible[anchorIdx]

        // Constraint: only allow within the same file + same priority bucket
        // AND only between two active tasks. Cross-section drags are no-ops.
        guard movingTask.sourceFileID == anchor.sourceFileID,
              movingTask.priority == anchor.priority,
              !anchor.isCompleted else { return }

        // Compute the new visible order, then extract the bucket order in that list.
        var newVisible = visible
        newVisible.move(fromOffsets: source, toOffset: destination)
        let bucketIDs = newVisible
            .filter {
                $0.sourceFileID == movingTask.sourceFileID
                    && $0.priority == movingTask.priority
                    && !$0.isCompleted
            }
            .map { $0.id }

        Task {
            await model.reorderBucket(in: movingTask.sourceFileID, taskIDs: bucketIDs)
        }
    }

    /// Returns a tinted background for tasks that have an explicit priority,
    /// or `nil` to inherit the system row color. We rely on `.listRowBackground`
    /// (the SwiftUI-native way to color a List row) so selection, hover, and
    /// platform chrome continue to work correctly.
    @ViewBuilder
    private func rowBackground(for task: TodoTask) -> some View {
        if model.workspace.settings.priorityRowHighlight,
           let priority = task.priority,
           !task.isCompleted {
            DesignTokens.priorityColor(priority)
                .opacity(0.10)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func rowContextMenu(for task: TodoTask) -> some View {
        Button(task.isCompleted ? "Reopen" : "Complete") {
            Task { await model.toggleCompletion(task) }
        }
        Divider()
        Menu("Move to file") {
            ForEach(model.activeTaskFiles) { file in
                if file.id != task.sourceFileID {
                    Button(file.displayName) {
                        Task {
                            await model.moveTask(task, to: file.id)
                        }
                    }
                }
            }
        }
        Button("Delete", role: .destructive) {
            Task { await model.delete(task) }
        }
    }

    private var showsSourceBadge: Bool {
        switch model.selection {
        case .file: return false
        default: return model.activeTaskFiles.count > 1
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No tasks",
            systemImage: "checkmark.circle",
            description: Text("Add a task below to get started.")
        )
    }

    // MARK: - Composer

    /// File the inline composer should append to. Delegates to
    /// `AppModel.composerTargetFileID` so the iOS toolbar `+`, the macOS Dock
    /// menu, ⌘N and the inline composer all agree on the destination.
    private var composerTargetFileID: UUID? {
        model.composerTargetFileID
    }

    @ViewBuilder
    private var inlineComposer: some View {
        if let targetID = composerTargetFileID {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.tint)
                    TextField("Add a task\u{2026} (e.g. Pay rent +Home @errands due:tomorrow)", text: $newTaskText)
                        .textFieldStyle(.plain)
                        .focused($newTaskFieldFocused)
                        .onSubmit { submit(to: targetID) }
                    if !newTaskText.isEmpty {
                        Button("Add") { submit(to: targetID) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                composerTargetHint(for: targetID)
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(12)
        }
    }

    /// Tiny "Adding to <file>" caption so users always know where a new task will go.
    @ViewBuilder
    private func composerTargetHint(for targetID: UUID) -> some View {
        let displayName = model.displayName(forTaskFileID: targetID)
        let isDefault = targetID == model.defaultActiveFileID
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.right")
            Text("Adding to ")
            Text(displayName).fontWeight(.medium)
            if isDefault { Text("(default)") }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.leading, 24)
    }

    private func submit(to fileID: UUID) {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dueDate = SmartInputParser.extractDueDate(from: trimmed)
        Task {
            await model.addTask(description: trimmed, in: fileID, dueDate: dueDate)
        }
        newTaskText = ""
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Tiny non-blocking "syncing" indicator. Shown only while a background
            // refresh is in flight; never gates the UI.
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing from iCloud\u{2026}")
            }

            Menu {
                Toggle("Show Completed", isOn: Binding(
                    get: { model.showCompleted },
                    set: { model.showCompleted = $0 }
                ))
                Divider()
                Picker("Sort by", selection: Binding(
                    get: { model.sortConfiguration.field },
                    set: { model.sortConfiguration.field = $0 }
                )) {
                    Text("Smart").tag(SortField.smart)
                    Text("Due date").tag(SortField.dueDate)
                    Text("Priority").tag(SortField.priority)
                    Text("Project").tag(SortField.project)
                    Text("Context").tag(SortField.context)
                    Text("Creation").tag(SortField.creationDate)
                    Text("File order").tag(SortField.fileOrder)
                    Text("Manual").tag(SortField.manual)
                }
            } label: {
                Label("Display", systemImage: "slider.horizontal.3")
            }

            Button {
                // Single entry point on both platforms: post the notification
                // and let RootView present the AddTaskSheet. Same path as
                // the macOS Dock right-click → "New Task" item and the iOS
                // Home Screen long-press quick action.
                NotificationCenter.default.post(name: .listedNewTaskRequested, object: nil)
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
