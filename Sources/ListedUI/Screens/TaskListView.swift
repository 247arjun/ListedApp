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
        // iPhone keeps the always-visible navbar drawer search field.
        // iPad uses `.toolbar` placement so the search field lives in the
        // navigation bar itself (a magnifying-glass affordance that expands
        // on tap) instead of a full-width drawer underneath. The drawer mode
        // visually extends behind an open inspector, which looks broken.
        .searchable(
            text: $bindable.searchText,
            placement: usesPushNavigation
                ? .navigationBarDrawer(displayMode: .always)
                : .toolbar,
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
        let grouping = model.sortConfiguration.grouping
        let displayMode = model.workspace.settings.groupDisplayMode

        // Kanban requires active grouping; falls back to inline list otherwise.
        if grouping != .none && displayMode == .kanban {
            kanbanBoard
        } else if grouping != .none {
            groupedInlineList
        } else {
            flatList
        }
    }

    // MARK: - Flat list (no grouping)

    @ViewBuilder
    private var flatList: some View {
        if usesPushNavigation {
            List {
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

    // MARK: - Inline grouped list (sections with collapse/expand)

    @ViewBuilder
    private var groupedInlineList: some View {
        let groups = model.visibleTaskGroups
        if usesPushNavigation {
            List {
                if case .smartList(.today) = model.selection {
                    dateHeader
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }
                ForEach(groups) { group in
                    groupSection(group)
                }
            }
            .listStyle(.plain)
        } else {
            List(selection: Binding(
                get: { model.selectedTaskID },
                set: { model.selectedTaskID = $0 }
            )) {
                if case .smartList(.today) = model.selection {
                    dateHeader
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }
                ForEach(groups) { group in
                    groupSection(group)
                }
            }
            .listStyle(.plain)
        }
    }

    /// One inline section: collapsible header + rows when expanded.
    @ViewBuilder
    private func groupSection(_ group: TaskGroup) -> some View {
        let isCollapsed = model.isGroupCollapsed(group.id)
        Section {
            if !isCollapsed {
                ForEach(group.tasks) { task in
                    rowEntry(for: task)
                }
            }
        } header: {
            groupHeader(group, isCollapsed: isCollapsed)
        }
    }

    /// Tinted group header. The chevron/title region toggles collapse;
    /// the trailing "+" creates a new task pre-populated for this group.
    private func groupHeader(_ group: TaskGroup, isCollapsed: Bool) -> some View {
        let tint = groupTint(for: group)
        return HStack(spacing: DesignTokens.spacingSM) {
            // Collapse-toggle region (chevron + title + count)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.toggleGroupCollapsed(group.id)
                }
            } label: {
                HStack(spacing: DesignTokens.spacingSM) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(group.tasks.count)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(tint.opacity(0.12))
                        )
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // "+" creates a new task pre-populated for this group.
            Button {
                addTaskInGroup(group)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("New task in \(group.title)")
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Accent color for a group header, chosen from the group's identity.
    private func groupTint(for group: TaskGroup) -> Color {
        switch model.sortConfiguration.grouping {
        case .priority:
            if let last = group.id.split(separator: ":").last,
               let letter = last.first {
                return DesignTokens.priorityColor(letter)
            }
            return DesignTokens.accent
        case .dueDate:
            // Map bucket → due-color palette
            if group.id == "due:overdue"  { return .red }
            if group.id == "due:thisWeek" { return .orange }
            if group.id == "due:nextWeek" { return .yellow }
            if group.id == "due:later"    { return .blue }
            return .gray
        case .project:  return .blue
        case .context:  return .purple
        case .completion:
            return group.id == "completion:done" ? .green : DesignTokens.accent
        case .file:     return .gray
        case .none:     return DesignTokens.accent
        }
    }

    /// Compute prefill values for a "+" tap on the given group's header and
    /// post the standard new-task notification. RootView picks up the prefill
    /// from the notification's `object` and threads it into `AddTaskSheet`.
    private func addTaskInGroup(_ group: TaskGroup) {
        let prefill: TaskPrefill = {
            switch model.sortConfiguration.grouping {
            case .priority:
                // "priority:A" → 'A'. The "No Priority" bucket gets nil priority.
                guard let last = group.id.split(separator: ":").last,
                      let letter = last.first, letter != "n" /* "none" */ else {
                    return TaskPrefill()
                }
                return TaskPrefill(priority: letter)

            case .project:
                // "project:home" → "home". "project:none" → no prefill.
                let parts = group.id.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[1] != "none" else { return TaskPrefill() }
                return TaskPrefill(project: parts[1])

            case .context:
                let parts = group.id.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[1] != "none" else { return TaskPrefill() }
                return TaskPrefill(context: parts[1])

            case .dueDate:
                // Map bucket → "start of period" due date:
                //   Overdue   → today (so it isn't immediately overdue again)
                //   This Week → today
                //   Next Week → today + 7
                //   Later     → today + 14
                //   Anytime   → no due date
                let today = LocalDate.today()
                switch group.id {
                case "due:overdue", "due:thisWeek":
                    return TaskPrefill(dueDate: today)
                case "due:nextWeek":
                    return TaskPrefill(dueDate: today.adding(days: 7))
                case "due:later":
                    return TaskPrefill(dueDate: today.adding(days: 14))
                default:
                    return TaskPrefill()
                }

            case .completion, .file, .none:
                return TaskPrefill()
            }
        }()

        NotificationCenter.default.post(
            name: .listedNewTaskRequested,
            object: prefill.isEmpty ? nil : prefill
        )
    }

    // MARK: - Kanban board

    @ViewBuilder
    private var kanbanBoard: some View {
        let groups = model.visibleTaskGroups
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
                ForEach(groups) { group in
                    kanbanColumn(group)
                }
            }
            .padding(.horizontal, DesignTokens.spacingLG)
            .padding(.vertical, DesignTokens.spacingMD)
        }
    }

    /// One kanban column: tinted header + vertically-scrolling stack of cards.
    private func kanbanColumn(_ group: TaskGroup) -> some View {
        let tint = groupTint(for: group)
        return VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack(spacing: DesignTokens.spacingSM) {
                Text(group.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(group.tasks.count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(tint.opacity(0.15))
                    )
                Spacer()
                Button {
                    addTaskInGroup(group)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("New task in \(group.title)")
            }
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.top, DesignTokens.spacingMD)
            .padding(.bottom, DesignTokens.spacingSM)

            // Thin tinted accent rule under the header
            Rectangle()
                .fill(tint.opacity(0.5))
                .frame(height: 2)
                .padding(.horizontal, DesignTokens.spacingMD)

            // Column body: scrolling list of task cards
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: DesignTokens.spacingSM) {
                    if group.tasks.isEmpty {
                        Text("Nothing here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DesignTokens.spacingLG)
                    } else {
                        ForEach(group.tasks) { task in
                            kanbanCard(for: task)
                        }
                    }
                }
                .padding(DesignTokens.spacingMD)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(.background.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    /// A single Kanban-style card for a task.
    private func kanbanCard(for task: TodoTask) -> some View {
        Button {
            if usesPushNavigation {
                // iPhone: rely on the NavigationLink path via selection. We can't
                // imperatively push from here, so we set selection and let the
                // selection-driven UI react. (No push happens — the user can
                // tap into the card content if needed.)
                model.selectedTaskID = task.id
            } else {
                model.selectedTaskID = task.id
            }
        } label: {
            TaskRowView(task: task, showSourceBadge: showsSourceBadge)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            rowContextMenu(for: task)
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

    /// Binding to the persisted `groupDisplayMode` setting. The setter
    /// writes through to the workspace so the choice survives launches.
    private var groupDisplayModeBinding: Binding<GroupDisplayMode> {
        Binding(
            get: { model.workspace.settings.groupDisplayMode },
            set: { newValue in
                var updated = model.workspace
                updated.settings.groupDisplayMode = newValue
                try? model.workspaceStore.save(updated)
                model.replaceWorkspace(updated)
                Task { await model.repository.updateWorkspace(updated) }
            }
        )
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
                // --- Visibility ---
                Section("Visibility") {
                    Toggle("Show Completed", isOn: Binding(
                        get: { model.showCompleted },
                        set: { model.showCompleted = $0 }
                    ))
                }

                // --- Sort: orders tasks within their group (or the flat list) ---
                Section("Sort tasks by") {
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
                    .pickerStyle(.inline)
                }

                // --- Group: partitions tasks into buckets ---
                Section("Group tasks into") {
                    Picker("Group by", selection: Binding(
                        get: { model.sortConfiguration.grouping },
                        set: { model.sortConfiguration.grouping = $0 }
                    )) {
                        Text("No groups").tag(GroupingField.none)
                        Text("Priority").tag(GroupingField.priority)
                        Text("Project").tag(GroupingField.project)
                        Text("Context").tag(GroupingField.context)
                        Text("Due date").tag(GroupingField.dueDate)
                    }
                    .pickerStyle(.inline)
                }

                // Display mode picker — only meaningful when grouping is active.
                if model.sortConfiguration.grouping != .none {
                    Section("Show groups as") {
                        Picker("Display as", selection: groupDisplayModeBinding) {
                            Label("Inline list", systemImage: "list.bullet.rectangle").tag(GroupDisplayMode.inline)
                            Label("Kanban board", systemImage: "rectangle.split.3x1").tag(GroupDisplayMode.kanban)
                        }
                        .pickerStyle(.inline)
                    }
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
