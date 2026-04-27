import SwiftUI
import ListedCore

/// Cross-platform sheet that builds a new task as a local **draft** — nothing
/// is written to disk until the user taps **Add**. Same field set as
/// `TaskDetailView` (title, due date, priority, source file, projects,
/// contexts, raw line). Tapping Cancel discards the draft.
///
/// Presented from:
///   - iOS: the toolbar `+` button, the Home Screen long-press "New Task" quick
///     action, and the macOS Dock right-click "New Task" item (via the
///     `listedNewTaskRequested` notification — see `RootView`).
///   - macOS: the toolbar `+` button, ⌘N, and the Dock right-click menu.
struct AddTaskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// File the parent screen wants to add to (sidebar selection or default).
    /// The user can re-pick from the Source File menu before saving.
    let targetFileID: UUID?

    // MARK: - Draft state

    @State private var description: String = ""
    @State private var dueDate: Date?
    @State private var priority: Character?
    @State private var chosenFileID: UUID?
    @State private var projects: [String] = []
    @State private var contexts: [String] = []
    @State private var rawLineExpanded: Bool = false
    /// User-edited override for the raw line. `nil` means "compute from the
    /// structured fields on commit". Once the user explicitly edits the raw
    /// line we honor their text verbatim.
    @State private var rawLineOverride: String?

    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    fieldsCard
                    metadataCard
                    rawCard
                }
                .padding(20)
            }
            .navigationTitle("New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commit() }
                        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Default the source file selection to whatever the parent screen
                // suggested (sidebar selection or workspace default).
                if chosenFileID == nil {
                    chosenFileID = targetFileID ?? model.defaultActiveFileID
                }
                // Auto-focus the title field so the keyboard appears immediately.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    titleFocused = true
                }
            }
        }
    }

    // MARK: - Cards (mirror TaskDetailView)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Use `.top` alignment + tuned padding rather than `.firstTextBaseline`,
            // because the baseline guide collapses when the TextField is empty
            // (no text → no baseline → the checkbox snaps to the top of the row).
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(priority.map(DesignTokens.priorityColor) ?? .secondary)
                    .padding(.top, 3)

                TextField("Description", text: $description, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($titleFocused)
                    .submitLabel(.done)
            }

            if dueDate != nil || priority != nil {
                HStack(spacing: 6) {
                    if let d = dueDate {
                        let local = LocalDate.from(d)
                        Chip(DesignTokens.dueLabel(for: local), systemImage: "calendar", style: .accent(DesignTokens.dueColor(for: local)))
                    }
                    if let p = priority {
                        Chip("Priority \(p)", systemImage: "flag.fill", style: .accent(DesignTokens.priorityColor(p)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28)
            }
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
                    DatePicker("", selection: Binding(get: { due }, set: { dueDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                    Button("Clear") { dueDate = nil }
                        .buttonStyle(.borderless)
                } else {
                    Button("Add due date") {
                        dueDate = Date()
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

            HStack {
                Text("Source file").frame(width: 110, alignment: .leading)
                Spacer()
                Menu {
                    ForEach(model.activeTaskFiles) { file in
                        Button(file.displayName) {
                            chosenFileID = file.id
                        }
                    }
                } label: {
                    Text(currentFileLabel)
                }
            }
        }
        .padding(16)
        .background(card)
    }

    private var currentFileLabel: String {
        let id = chosenFileID ?? targetFileID ?? model.defaultActiveFileID
        guard let id else { return "—" }
        return model.displayName(forTaskFileID: id)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            tagSubsection(
                title: "Projects",
                icon: "number",
                tint: .blue,
                values: projects,
                allKnown: model.allProjects,
                tokenPrefix: "+",
                add: { name in
                    if !projects.contains(name) { projects.append(name) }
                },
                remove: { name in
                    projects.removeAll(where: { $0 == name })
                }
            )

            Divider()

            tagSubsection(
                title: "Contexts",
                icon: "at",
                tint: .purple,
                values: contexts,
                allKnown: model.allContexts,
                tokenPrefix: "@",
                add: { name in
                    if !contexts.contains(name) { contexts.append(name) }
                },
                remove: { name in
                    contexts.removeAll(where: { $0 == name })
                }
            )
        }
        .padding(16)
        .background(card)
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
                TextEditor(text: Binding(
                    get: { rawLineOverride ?? composedRawLine() },
                    set: { rawLineOverride = $0 }
                ))
                .font(.body.monospaced())
                .frame(minHeight: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

                if rawLineOverride != nil {
                    HStack {
                        Spacer()
                        Button("Reset to structured fields") {
                            rawLineOverride = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            } label: {
                Label("Raw todo.txt line", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
            }
        }
        .padding(16)
        .background(card)
    }

    // MARK: - Build & commit

    /// Compose what the raw line *would* look like from the current structured
    /// state, without committing anything.
    private func composedRawLine() -> String {
        guard let task = buildDraftTask() else { return "" }
        return task.rawLine
    }

    /// Build a draft `TodoTask` from the current state. Returns `nil` if the
    /// description is empty.
    private func buildDraftTask() -> TodoTask? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fileID = chosenFileID ?? targetFileID ?? model.defaultActiveFileID
        guard let fileID else { return nil }

        let due = dueDate.map { LocalDate.from($0) }
        return TaskOperations.make(
            description: trimmed,
            priority: priority,
            dueDate: due,
            projects: projects,
            contexts: contexts,
            sourceFileID: fileID,
            lineNumber: 0,
            addUID: model.workspace.settings.addUIDToNewTasks,
            addCreationDate: model.workspace.settings.addCreationDateToNewTasks
        )
    }

    private func commit() {
        let fileID = chosenFileID ?? targetFileID ?? model.defaultActiveFileID
        guard let fileID else { return }

        // If the user edited the raw line, that text wins verbatim.
        if let raw = rawLineOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let parsed = TodoTxtParser().parse(line: raw, lineNumber: 0, sourceFileID: fileID)
            Task {
                await model.appendPreparedTask(parsed, to: fileID)
            }
            dismiss()
            return
        }

        guard let task = buildDraftTask() else { return }
        Task {
            await model.appendPreparedTask(task, to: fileID)
        }
        dismiss()
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.background.secondary)
    }
}
