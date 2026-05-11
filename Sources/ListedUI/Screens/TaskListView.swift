import SwiftUI
import ListedCore

/// The middle column of the macOS / iPad layout, and the primary screen on iPhone.
///
/// Redesigned with:
///   - Hero typographic header with contextual greeting (Today view) and date subtitle
///   - Card-based row styling with breathing room
///   - Beautiful contextual empty states with gradient backgrounds and animated icons
///   - Elevated inline composer as a first-class dock (macOS)
///   - Smooth number transitions on all numeric displays
public struct TaskListView: View {
    @Environment(AppModel.self) private var model

    /// When `true`, task taps push a `TaskDetailView` onto a `NavigationStack`
    /// (iPhone). When `false`, task taps update the `List(selection:)` binding
    /// to drive the detail column of a `NavigationSplitView` (iPad / macOS).
    ///
    /// **Why explicit?** Inside a `NavigationSplitView`'s content column,
    /// `horizontalSizeClass` is unreliable — `RootView` knows the correct mode
    /// and passes it down.
    private let usesPushNavigation: Bool

    @State private var newTaskText: String = ""
    @FocusState private var newTaskFieldFocused: Bool

    public init(usesPushNavigation: Bool = false) {
        self.usesPushNavigation = usesPushNavigation
    }

    public var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            list
            #if os(macOS)
            inlineComposer
            #endif
        }
        .navigationTitle(navigationTitle)
        #if os(macOS)
        .navigationSubtitle(subtitle)
        .searchable(text: $bindable.searchText, prompt: "Search tasks, +project, @context, due:today")
        #else
        .searchable(
            text: $bindable.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search tasks, +project, @context, due:today"
        )
        #endif
        .toolbar { toolbarItems }
        .animation(.easeInOut(duration: 0.25), value: model.visibleTasks.map(\.id))
    }

    private var navigationTitle: String {
        switch model.selection {
        case .smartList(let kind):
            switch kind {
            case .today:     return DesignTokens.timeOfDayGreeting
            case .upcoming:  return "Upcoming"
            case .all:       return "All Tasks"
            case .inbox:     return "Inbox"
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
        let total = model.visibleTasks.count
        let completed = model.visibleTasks.filter(\.isCompleted).count
        if completed > 0 && total > completed {
            return "\(completed) / \(total) done"
        }
        return total == 1 ? "1 task" : "\(total) tasks"
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

    @ViewBuilder
    private var listForCurrentPlatform: some View {
        if usesPushNavigation {
            List {
                // Date subtitle header for Today view
                if case .smartList(.today) = model.selection {
                    dateHeader
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }
                ForEach(model.visibleTasks) { task in
                    rowEntry(for: task)
                }
                .onMove(perform: handleMove)
            }
            .listStyle(.plain)
        } else {
            selectionList
        }
    }

    /// Date subtitle shown under the greeting-based navigation title on the Today view.
    private var dateHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: DesignTokens.timeOfDayIcon)
                .foregroundStyle(DesignTokens.smartListColor(for: .today))
                .imageScale(.small)
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var selectionList: some View {
        List(selection: Binding(
            get: { model.selectedTaskID },
            set: { model.selectedTaskID = $0 }
        )) {
            // Date subtitle header for Today view
            if case .smartList(.today) = model.selection {
                dateHeader
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
            ForEach(model.visibleTasks) { task in
                rowEntry(for: task)
            }
            .onMove(perform: handleMove)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func rowEntry(for task: TodoTask) -> some View {
        if usesPushNavigation {
            NavigationLink(value: task.id) {
                TaskRowView(task: task, showSourceBadge: showsSourceBadge)
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            .listRowSeparator(.hidden)
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
    }

    private func selectionRow(for task: TodoTask) -> some View {
        TaskRowView(task: task, showSourceBadge: showsSourceBadge)
            .tag(task.id)
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            .listRowSeparator(.hidden)
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
    private func rowBackground(for task: TodoTask) -> some View {
        if model.workspace.settings.priorityRowHighlight,
           let p = task.priority,
           !task.isCompleted {
            DesignTokens.priorityColor(p).opacity(0.06)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Color.clear
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

    private func handleMove(from source: IndexSet, to destination: Int) {
        guard let srcIdx = source.first, source.count == 1 else { return }
        let visible = model.visibleTasks
        let movingTask = visible[srcIdx]
        guard !movingTask.isCompleted else { return }

        let anchorIdx: Int
        if destination > srcIdx {
            anchorIdx = destination - 1
        } else {
            anchorIdx = destination
        }
        guard anchorIdx >= 0, anchorIdx < visible.count, anchorIdx != srcIdx else { return }
        let anchor = visible[anchorIdx]

        guard movingTask.sourceFileID == anchor.sourceFileID,
              movingTask.priority == anchor.priority,
              !anchor.isCompleted else { return }

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

    // MARK: - Empty state (beautiful, contextual)

    private var emptyState: some View {
        let icon = DesignTokens.emptyIcon(for: model.selection)
        let title = DesignTokens.emptyTitle(for: model.selection)
        let message = DesignTokens.emptySubtitle(for: model.selection)
        let gradientColors = DesignTokens.emptyGradient(for: model.selection)
        let tint = DesignTokens.sidebarTint(for: model.selection)

        return VStack(spacing: DesignTokens.spacingXL) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            VStack(spacing: DesignTokens.spacingSM) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.spacingSection)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Composer (elevated first-class dock)

    private var composerTargetFileID: UUID? {
        model.composerTargetFileID
    }

    @ViewBuilder
    private var inlineComposer: some View {
        if let targetID = composerTargetFileID {
            VStack(spacing: 0) {
                Divider()
                    .overlay(newTaskFieldFocused ? DesignTokens.accent.opacity(0.3) : Color.clear)

                VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
                    HStack(spacing: DesignTokens.spacingMD) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DesignTokens.accent)
                            .symbolRenderingMode(.hierarchical)

                        TextField("Add a task\u{2026}", text: $newTaskText)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .focused($newTaskFieldFocused)
                            .onSubmit { submit(to: targetID) }

                        if !newTaskText.isEmpty {
                            Button("Add") { submit(to: targetID) }
                                .buttonStyle(.borderedProminent)
                                .tint(DesignTokens.accent)
                                .controlSize(.small)
                        }
                    }
                    composerTargetHint(for: targetID)
                }
                .padding(.horizontal, DesignTokens.spacingLG)
                .padding(.vertical, DesignTokens.spacingMD)
            }
            .background(.bar)
        }
    }

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
        .foregroundStyle(.tertiary)
        .padding(.leading, 30)
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

            // Primary action button with filled accent style
            Button {
                NotificationCenter.default.post(name: .listedNewTaskRequested, object: nil)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New Task")
        }
    }
}
