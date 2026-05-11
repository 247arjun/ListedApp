import SwiftUI
import ListedCore

/// Cross-platform sheet that builds a new task as a local **draft** — nothing
/// is written to disk until the user taps **Add**. Redesigned with the same
/// flowing document style as TaskDetailView.
struct AddTaskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let targetFileID: UUID?

    // MARK: - Draft state

    @State private var description: String = ""
    @State private var dueDate: Date?
    @State private var priority: Character?
    @State private var chosenFileID: UUID?
    @State private var projects: [String] = []
    @State private var contexts: [String] = []
    @State private var rawLineExpanded: Bool = false
    @State private var rawLineOverride: String?

    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                        .tint(DesignTokens.accent)
                        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if chosenFileID == nil {
                    chosenFileID = targetFileID ?? model.defaultActiveFileID
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    titleFocused = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
            HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
                Image(systemName: "circle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(priority.map(DesignTokens.priorityColor) ?? .secondary)
                    .padding(.top, 5)

                TextField("What needs to be done?", text: $description, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($titleFocused)
                    .submitLabel(.done)
            }

            if dueDate != nil || priority != nil {
                HStack(spacing: DesignTokens.spacingSM) {
                    if let d = dueDate {
                        let local = LocalDate.from(d)
                        Chip(DesignTokens.dueLabel(for: local), systemImage: "calendar", style: .accent(DesignTokens.dueColor(for: local)))
                    }
                    if let p = priority {
                        Chip("Priority \(p)", systemImage: "flag.fill", style: .accent(DesignTokens.priorityColor(p)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 32)
            }
        }
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
            Text("Fields")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Label("Due date", systemImage: "calendar")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Spacer()
                if let due = dueDate {
                    DatePicker("", selection: Binding(get: { due }, set: { dueDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                    Button { dueDate = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Add due date") { dueDate = Date() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(DesignTokens.accent)
                }
            }

            Divider()

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

            HStack {
                Label("Source file", systemImage: "doc.text")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Spacer()
                Menu {
                    ForEach(model.activeTaskFiles) { file in
                        Button(file.displayName) { chosenFileID = file.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentFileLabel)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var currentFileLabel: String {
        let id = chosenFileID ?? targetFileID ?? model.defaultActiveFileID
        guard let id else { return "—" }
        return model.displayName(forTaskFileID: id)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
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

    // MARK: - Raw line

    private var rawSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            DisclosureGroup(isExpanded: $rawLineExpanded) {
                TextEditor(text: Binding(
                    get: { rawLineOverride ?? composedRawLine() },
                    set: { rawLineOverride = $0 }
                ))
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
                        .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("Raw todo.txt line", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Build & commit

    private func composedRawLine() -> String {
        guard let task = buildDraftTask() else { return "" }
        return task.rawLine
    }

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
}
