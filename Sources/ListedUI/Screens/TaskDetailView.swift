import SwiftUI
import ListedCore

/// The right-hand detail pane — redesigned as a flowing document with a hero title,
/// clean metadata grid, and refined card sections.
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
            VStack(alignment: .leading, spacing: 0) {
                // Ambient gradient header tinted by priority or section color
                headerSection
                    .padding(.horizontal, DesignTokens.spacingXL)
                    .padding(.top, DesignTokens.spacingXL)
                    .padding(.bottom, DesignTokens.spacingLG)

                Divider()
                    .padding(.horizontal, DesignTokens.spacingXL)

                fieldsSection
                    .padding(.horizontal, DesignTokens.spacingXL)
                    .padding(.vertical, DesignTokens.spacingLG)

                Divider()
                    .padding(.horizontal, DesignTokens.spacingXL)

                metadataSection
                    .padding(.horizontal, DesignTokens.spacingXL)
                    .padding(.vertical, DesignTokens.spacingLG)

                Divider()
                    .padding(.horizontal, DesignTokens.spacingXL)

                rawSection
                    .padding(.horizontal, DesignTokens.spacingXL)
                    .padding(.vertical, DesignTokens.spacingLG)
            }
        }
        .background(detailBackground)
        .navigationTitle("Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { sync(from: task) }
        .onChange(of: task.id) { _, _ in sync(from: task) }
        .onChange(of: task.rawLine) { _, _ in sync(from: task) }
    }

    // MARK: - Ambient background

    @ViewBuilder
    private var detailBackground: some View {
        let tint = (task.priority ?? task.preservedPriority).map(DesignTokens.priorityColor) ?? DesignTokens.accent
        VStack {
            LinearGradient(
                colors: [tint.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            Spacer()
        }
        .ignoresSafeArea()
    }

    // MARK: - Header: hero title + completion + chips

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
            HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
                CompletionToggle(
                    isCompleted: task.isCompleted,
                    tint: (task.priority ?? task.preservedPriority).map(DesignTokens.priorityColor) ?? DesignTokens.accent,
                    onToggle: { Task { await model.toggleCompletion(task) } }
                )
                .padding(.top, 5)

                TextField("Description", text: $description, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .submitLabel(.done)
                    .onSubmit { commitDescription() }
            }

            // Inline chips below title
            if task.dueDate != nil || task.priority != nil || task.preservedPriority != nil {
                HStack(spacing: DesignTokens.spacingSM) {
                    if let due = task.dueDate {
                        let today = LocalDate.today()
                        Chip(
                            DesignTokens.dueLabel(for: due),
                            systemImage: "calendar",
                            style: due < today ? .filled(DesignTokens.dueColor(for: due)) : .accent(DesignTokens.dueColor(for: due))
                        )
                    }
                    if let p = task.priority ?? task.preservedPriority {
                        Chip("Priority \(p)", systemImage: "flag.fill", style: .accent(DesignTokens.priorityColor(p)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 32) // align under the title text
            }
        }
        .onChange(of: description) { _, _ in /* commit on submit */ }
    }

    // MARK: - Fields: clean metadata grid

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
            Text("Fields")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Due date row
            HStack {
                Label("Due date", systemImage: "calendar")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Spacer()
                if let due = dueDate {
                    DatePicker("", selection: Binding(get: { due }, set: { dueDate = $0; commitDueDate() }), displayedComponents: .date)
                        .labelsHidden()
                    Button { dueDate = nil; commitDueDate() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Add due date") {
                        dueDate = task.dueDate?.date(in: .current) ?? Date()
                        commitDueDate()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignTokens.accent)
                }
            }

            Divider()

            // Priority row
            HStack {
                Label("Priority", systemImage: "flag")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Spacer()
                Picker("", selection: Binding(
                    get: { priority.map(String.init) ?? "—" },
                    set: { newValue in
                        priority = newValue == "—" ? nil : newValue.first
                        commitPriority()
                    }
                )) {
                    Text("—").tag("—")
                    ForEach(DesignTokens.pickerPriorities, id: \.self) { letter in
                        Text(String(letter)).tag(String(letter))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            // Source file row
            HStack {
                Label("Source file", systemImage: "doc.text")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Spacer()
                Menu {
                    ForEach(model.activeTaskFiles) { file in
                        Button(file.displayName) {
                            Task { await model.moveTask(task, to: file.id) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.displayName(forTaskFileID: task.sourceFileID))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Metadata: projects + contexts

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
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
    }

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
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            HStack(spacing: DesignTokens.spacingSM) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.tertiary)
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

    // MARK: - Raw editor with code-editor feel

    private var rawSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            DisclosureGroup(isExpanded: $rawLineExpanded) {
                TextEditor(text: $rawLine)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                    .padding(DesignTokens.spacingMD)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    )
                HStack {
                    Spacer()
                    Button("Save Raw Line") {
                        commitRawLine()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accent)
                    .controlSize(.small)
                }
            } label: {
                Label("Raw todo.txt line", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
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
}
