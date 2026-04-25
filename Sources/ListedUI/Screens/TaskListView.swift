import SwiftUI
import ListedCore

/// The middle column of the macOS / iPad layout, and the primary screen on iPhone.
public struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @State private var newTaskText: String = ""
    @FocusState private var newTaskFieldFocused: Bool

    public init() {}

    public var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            list
            inlineComposer
        }
        .navigationTitle(navigationTitle)
        #if os(macOS)
        .navigationSubtitle(subtitle)
        #endif
        .searchable(text: $bindable.searchText, prompt: "Search tasks, +project, @context, due:today")
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
                List(selection: Binding(
                    get: { model.selectedTaskID },
                    set: { model.selectedTaskID = $0 }
                )) {
                    ForEach(model.visibleTasks) { task in
                        TaskRowView(task: task, showSourceBadge: showsSourceBadge)
                            .tag(task.id)
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await model.toggleCompletion(task) }
                                } label: {
                                    Label(task.isCompleted ? "Reopen" : "Complete", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await model.delete(task) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                rowContextMenu(for: task)
                            }
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.plain)
                #endif
            }
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

    @ViewBuilder
    private var inlineComposer: some View {
        if let defaultID = model.defaultActiveFileID {
            Divider()
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                TextField("Add a task… (e.g. Pay rent +Home @errands due:tomorrow)", text: $newTaskText)
                    .textFieldStyle(.plain)
                    .focused($newTaskFieldFocused)
                    .onSubmit { submit(to: defaultID) }
                if !newTaskText.isEmpty {
                    Button("Add") { submit(to: defaultID) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(12)
        }
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
                if let id = model.defaultActiveFileID {
                    newTaskFieldFocused = true
                    _ = id
                }
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
