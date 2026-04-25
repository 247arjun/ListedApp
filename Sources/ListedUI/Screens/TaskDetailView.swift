import SwiftUI
import ListedCore

/// The right-hand detail pane.
public struct TaskDetailView: View {
    @Environment(AppModel.self) private var model

    let task: TodoTask

    @State private var description: String = ""
    @State private var dueDate: Date?
    @State private var priority: Character?
    @State private var rawLineExpanded: Bool = false
    @State private var rawLine: String = ""

    public init(task: TodoTask) {
        self.task = task
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                fieldsCard
                metadataCard
                rawCard
            }
            .padding(20)
        }
        .navigationTitle("Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { sync(from: task) }
        .onChange(of: task.id) { _, _ in sync(from: task) }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CompletionToggle(
                    isCompleted: task.isCompleted,
                    tint: (task.priority ?? task.preservedPriority).map(DesignTokens.priorityColor) ?? .accentColor,
                    onToggle: { Task { await model.toggleCompletion(task) } }
                )
                if let due = task.dueDate {
                    Chip(DesignTokens.dueLabel(for: due), systemImage: "calendar", style: .accent(DesignTokens.dueColor(for: due)))
                }
                if let p = task.priority ?? task.preservedPriority {
                    Chip("Priority \(p)", systemImage: "flag.fill", style: .accent(DesignTokens.priorityColor(p)))
                }
                Spacer()
            }
            TextField("Description", text: $description, axis: .vertical)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit { commitDescription() }
        }
        .padding(16)
        .background(card)
    }

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fields").font(.headline)

            HStack {
                Text("Due date").frame(width: 110, alignment: .leading)
                Spacer()
                if let due = dueDate {
                    DatePicker("", selection: Binding(get: { due }, set: { dueDate = $0; commitDueDate() }), displayedComponents: .date)
                        .labelsHidden()
                    Button("Clear") { dueDate = nil; commitDueDate() }
                        .buttonStyle(.borderless)
                } else {
                    Button("Add due date") {
                        dueDate = task.dueDate?.date(in: .current) ?? Date()
                        commitDueDate()
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                Text("Priority").frame(width: 110, alignment: .leading)
                Spacer()
                Picker("", selection: Binding(
                    get: { priority.map(String.init) ?? "—" },
                    set: { newValue in
                        priority = newValue == "—" ? nil : newValue.first
                        commitPriority()
                    }
                )) {
                    Text("—").tag("—")
                    ForEach(["A", "B", "C", "D", "E"], id: \.self) { letter in
                        Text(letter).tag(letter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Text("Source file").frame(width: 110, alignment: .leading)
                Spacer()
                Menu {
                    ForEach(model.activeTaskFiles) { file in
                        Button(file.displayName) {
                            Task { await model.moveTask(task, to: file.id) }
                        }
                    }
                } label: {
                    Text(model.displayName(forTaskFileID: task.sourceFileID))
                }
            }
        }
        .padding(16)
        .background(card)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            tagSubsection(
                title: "Projects",
                icon: "number",
                tint: .blue,
                values: task.projects,
                allKnown: model.allProjects,
                tokenPrefix: "+",
                add: { name in
                    let updated = TaskOperations.addProject(task, name)
                    Task { await model.update(updated) }
                },
                remove: { name in
                    let updated = TaskOperations.removeProject(task, name)
                    Task { await model.update(updated) }
                }
            )

            Divider()

            tagSubsection(
                title: "Contexts",
                icon: "at",
                tint: .purple,
                values: task.contexts,
                allKnown: model.allContexts,
                tokenPrefix: "@",
                add: { name in
                    let updated = TaskOperations.addContext(task, name)
                    Task { await model.update(updated) }
                },
                remove: { name in
                    let updated = TaskOperations.removeContext(task, name)
                    Task { await model.update(updated) }
                }
            )
        }
        .padding(16)
        .background(card)
    }

    /// Renders one tag-collection (projects OR contexts) with add/remove affordances.
    @ViewBuilder
    private func tagSubsection(
        title: String,
        icon: String,
        tint: Color,
        values: [String],
        allKnown: [String],
        tokenPrefix: String,
        add: @escaping (String) -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                AddTagButton(
                    title: "Add \(title.dropLast())",
                    icon: icon,
                    tint: tint,
                    suggestions: allKnown.filter { !values.contains($0) },
                    onAdd: add
                )
            }

            if values.isEmpty {
                Text("Tap \(Image(systemName: "plus.circle")) to add.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayoutCompat(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        TagPill(text: tokenPrefix + value, tint: tint) {
                            remove(value)
                        }
                    }
                }
            }
        }
    }

    private var rawCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $rawLineExpanded) {
                TextEditor(text: $rawLine)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                HStack {
                    Spacer()
                    Button("Save Raw Line") {
                        commitRawLine()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } label: {
                Label("Raw todo.txt line", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
            }
        }
        .padding(16)
        .background(card)
    }

    // MARK: - Commit

    private func sync(from task: TodoTask) {
        description = task.cleanTitle
        dueDate = task.dueDate?.date(in: .current)
        priority = task.priority ?? task.preservedPriority
        rawLine = task.rawLine
    }

    private func commitDescription() {
        let updated = TaskOperations.setDescription(task, to: descriptionWithExistingTokens())
        Task { await model.update(updated) }
    }

    /// Append projects/contexts/key:value tokens that already existed back to the
    /// trimmed description (the user only edited the headline text).
    private func descriptionWithExistingTokens() -> String {
        var text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingPieces = task.description
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { token in
                token.hasPrefix("+") || token.hasPrefix("@") || token.contains(":")
            }
        for token in existingPieces where !text.split(separator: " ").contains(token[...]) {
            text += " " + token
        }
        return text
    }

    private func commitDueDate() {
        let local = dueDate.map { LocalDate.from($0) }
        let updated = TaskOperations.setDueDate(task, to: local)
        Task { await model.update(updated) }
    }

    private func commitPriority() {
        let updated = TaskOperations.setPriority(task, to: priority)
        Task { await model.update(updated) }
    }

    private func commitRawLine() {
        let updated = TaskOperations.replaceRawLine(task, newRawLine: rawLine)
        Task { await model.update(updated) }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
