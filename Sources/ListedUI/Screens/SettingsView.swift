import SwiftUI
import ListedCore
import UniformTypeIdentifiers
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

/// Settings screen used as a sheet on iOS and a Settings window on macOS.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showFileImporter: Bool = false
    @State private var showFolderImporter: Bool = false
    @State private var showPurgeConfirmation: Bool = false
    @State private var purgeResultMessage: String?
    @State private var purgeResultIsError: Bool = false
    @State private var notificationPermissionDenied: Bool = false

    public init() {}

    public var body: some View {
        #if os(macOS)
        // The Settings scene supplies the chrome; just lay the form out and size
        // the window. .formStyle(.grouped) gives us the modern inset-card look.
        formContent
            .formStyle(.grouped)
            .frame(minWidth: 600, idealWidth: 680, minHeight: 560, idealHeight: 720)
            .scrollContentBackground(.hidden)
        #else
        NavigationStack {
            formContent
                .formStyle(.grouped)
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    /// The actual form body, hoisted out so each platform can wrap it differently.
    @ViewBuilder
    private var formContent: some View {
        Form {
            storageSection
            filesSection
            appearanceSection
            remindersSection
            completedSection
            behaviorSection
        }
        // .fileImporter is unreliable inside macOS Settings scenes — see addFile()
        // for the AppKit fallback. We still attach the modifier here so iOS keeps
        // working through the document picker.
        #if !os(macOS)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.addExternalFile(url) }
            }
        }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.addExternalFolder(url) }
            }
        }
        #endif
    }

    // MARK: - Sections

    private var storageSection: some View {
        Section("Storage") {
            ForEach(model.workspace.fileSources) { source in
                sourceRow(source)
            }
            Button {
                addFile()
            } label: {
                Label("Add Task File\u{2026}", systemImage: "doc.badge.plus")
            }
            Button {
                addFolder()
            } label: {
                Label("Add Folder of Files\u{2026}", systemImage: "folder.badge.plus")
            }
        }
    }

    private var filesSection: some View {
        Section("Files") {
            ForEach(model.workspace.taskFiles) { file in
                fileRow(file)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle("Highlight rows by priority", isOn: bind(\.settings.priorityRowHighlight))
            Toggle("Show raw metadata in rows", isOn: bind(\.settings.showRawMetadataInRows))
            #if os(macOS)
            Toggle(isOn: bind(\.settings.menuBarEnabled)) {
                Label("Show in menu bar", systemImage: "checkmark.square.fill")
            }
            // Default scope the menu bar popover lands on each time it opens.
            // Only meaningful when the menu bar is enabled, so we disable the
            // picker otherwise rather than hiding it (avoids layout jump).
            Picker("Menu bar default view", selection: Binding(
                get: { model.workspace.settings.menuBarDefaultScope },
                set: { newValue in
                    var updated = model.workspace
                    updated.settings.menuBarDefaultScope = newValue
                    try? model.workspaceStore.save(updated)
                    model.replaceWorkspace(updated)
                    Task { await model.repository.updateWorkspace(updated) }
                }
            )) {
                Text("Today").tag(TaskQuery.SmartList.today)
                Text("Upcoming").tag(TaskQuery.SmartList.upcoming)
                Text("All").tag(TaskQuery.SmartList.all)
            }
            .disabled(!model.workspace.settings.menuBarEnabled)
            #endif
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Add creation date to new tasks", isOn: bind(\.settings.addCreationDateToNewTasks))
            Toggle("Add UID to new tasks", isOn: bind(\.settings.addUIDToNewTasks))
            Toggle("Preserve priority on completion", isOn: bind(\.settings.preservePriorityOnCompletion))
            Toggle("Group completed at bottom", isOn: bind(\.settings.groupCompletedAtBottom))
            Toggle("Show completed tasks in lists", isOn: bind(\.settings.showCompletedInLists))
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Enable due date reminders", isOn: remindersEnabledBinding)

            if model.workspace.settings.remindersEnabled {
                DatePicker(
                    "Reminder time",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )

                Picker("When to remind", selection: reminderDaysBeforeBinding) {
                    Text("On the due date").tag(0)
                    Text("1 day before").tag(1)
                    Text("2 days before").tag(2)
                    Text("3 days before").tag(3)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if model.workspace.settings.remindersEnabled {
                Text("Notifications fire at the chosen time for every task with a due date. Reminders sync automatically when tasks change via iCloud or external editors.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Notifications Disabled", isPresented: $notificationPermissionDenied) {
            Button("Open Settings") {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Listed needs notification permission to send due date reminders. Please enable notifications in Settings.")
        }
    }

    /// Binding for the reminders toggle that requests notification permission
    /// when first enabled.
    private var remindersEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.workspace.settings.remindersEnabled },
            set: { newValue in
                if newValue {
                    // Request permission before enabling
                    Task {
                        let granted = await model.reminderScheduler.requestPermissionIfNeeded()
                        await MainActor.run {
                            if granted {
                                updateSettings { $0.settings.remindersEnabled = true }
                                Task { await model.syncReminders() }
                            } else {
                                notificationPermissionDenied = true
                            }
                        }
                    }
                } else {
                    updateSettings { $0.settings.remindersEnabled = false }
                    Task { await model.syncReminders() }
                }
            }
        )
    }

    /// Binding that converts the stored hour/minute ints to/from a Date
    /// for use with DatePicker.
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = model.workspace.settings.reminderHour
                components.minute = model.workspace.settings.reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: newDate)
                let minute = calendar.component(.minute, from: newDate)
                updateSettings {
                    $0.settings.reminderHour = hour
                    $0.settings.reminderMinute = minute
                }
                Task { await model.syncReminders() }
            }
        )
    }

    /// Binding for the "days before" picker.
    private var reminderDaysBeforeBinding: Binding<Int> {
        Binding(
            get: { model.workspace.settings.reminderDaysBefore },
            set: { newValue in
                updateSettings { $0.settings.reminderDaysBefore = newValue }
                Task { await model.syncReminders() }
            }
        )
    }

    /// Helper that updates workspace settings, persists, and propagates.
    private func updateSettings(_ mutation: (inout Workspace) -> Void) {
        var updated = model.workspace
        mutation(&updated)
        try? model.workspaceStore.save(updated)
        model.replaceWorkspace(updated)
        Task { await model.repository.updateWorkspace(updated) }
    }

    /// Single-file completion model: instead of moving completed tasks to a
    /// separate `done.txt`, Listed keeps them at the bottom of the active file
    /// and offers an opt-in schedule for hard-deleting them.
    private var completedSection: some View {
        Section {
            Picker("Auto-delete completed", selection: Binding(
                get: { model.workspace.settings.completedAutoPurge },
                set: { newValue in
                    var updated = model.workspace
                    updated.settings.completedAutoPurge = newValue
                    try? model.workspaceStore.save(updated)
                    model.replaceWorkspace(updated)
                    Task { await model.repository.updateWorkspace(updated) }
                }
            )) {
                ForEach(PurgeCadence.allCases, id: \.self) { cadence in
                    Text(cadence.displayName).tag(cadence)
                }
            }

            if let last = model.workspace.settings.lastPurgeAt {
                HStack {
                    Text("Last purge")
                    Spacer()
                    Text(last.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                showPurgeConfirmation = true
            } label: {
                Label("Delete completed tasks now", systemImage: "trash")
            }
            .confirmationDialog(
                "Delete all completed tasks from every active file? This can\u{2019}t be undone.",
                isPresented: $showPurgeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Now", role: .destructive) {
                    Task {
                        let count = await model.purgeCompletedTasksNow()
                        await MainActor.run {
                            purgeResultIsError = false
                            purgeResultMessage = count == 1
                                ? "Removed 1 completed task."
                                : "Removed \(count) completed tasks."
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                purgeResultIsError ? "Couldn\u{2019}t purge" : "Done",
                isPresented: Binding(
                    get: { purgeResultMessage != nil },
                    set: { if !$0 { purgeResultMessage = nil } }
                )
            ) {
                Button("OK") { purgeResultMessage = nil }
            } message: {
                Text(purgeResultMessage ?? "")
            }
        } header: {
            Text("Completed Tasks")
        } footer: {
            Text("Listed keeps completed tasks at the bottom of your todo.txt file. Auto-delete removes them on the chosen schedule (anything older than the cadence window). Files always store standard `(A)` syntax for compatibility.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rows

    private func sourceRow(_ source: FileSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: source.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: DesignTokens.sidebarIconSize, height: DesignTokens.sidebarIconSize)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(sourceColor(for: source.kind).gradient)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName).font(.body)
                Text(label(for: source.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if source.isDefault {
                Text("Default")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(DesignTokens.accent.opacity(0.12)))
                    .foregroundStyle(DesignTokens.accent)
            }
        }
        .padding(.vertical, 2)
    }

    private func fileRow(_ file: TaskFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.role == .completedArchive ? "tray.full.fill" : "doc.text.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: DesignTokens.sidebarIconSize, height: DesignTokens.sidebarIconSize)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.gray.gradient)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                Text(file.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if file.id == model.workspace.defaultTaskFileID {
                Text("Default")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(DesignTokens.accent.opacity(0.12)))
                    .foregroundStyle(DesignTokens.accent)
            } else if file.role == .activeTodo {
                Button("Make default") {
                    Task { await model.setDefaultFile(file.id) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(DesignTokens.accent)
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(for kind: FileSourceKind) -> String {
        switch kind {
        case .appICloudContainer: return "icloud"
        case .appLocalContainer: return "internaldrive"
        case .securityScopedFile: return "doc.text"
        case .securityScopedFolder: return "folder"
        }
    }

    private func label(for kind: FileSourceKind) -> String {
        switch kind {
        case .appICloudContainer: return "iCloud Drive · Listed"
        case .appLocalContainer: return "On this device"
        case .securityScopedFile: return "External file"
        case .securityScopedFolder: return "External folder"
        }
    }

    private func sourceColor(for kind: FileSourceKind) -> Color {
        switch kind {
        case .appICloudContainer: return .blue
        case .appLocalContainer: return .gray
        case .securityScopedFile: return .orange
        case .securityScopedFolder: return .purple
        }
    }

    // MARK: - Bindings

    private func bind(_ keyPath: WritableKeyPath<Workspace, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.workspace[keyPath: keyPath] },
            set: { newValue in
                var updated = model.workspace
                updated[keyPath: keyPath] = newValue
                try? model.workspaceStore.save(updated)
                model.replaceWorkspace(updated)
                Task { await model.repository.updateWorkspace(updated) }
            }
        )
    }

    // MARK: - File pickers

    private func addFile() {
        #if os(macOS)
        // SwiftUI's `.fileImporter` doesn't reliably present from inside the macOS
        // Settings scene, so we drive an `NSOpenPanel` directly.
        let panel = NSOpenPanel()
        panel.title = "Add Task File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.addExternalFile(url) }
        }
        #else
        showFileImporter = true
        #endif
    }

    private func addFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Add Folder of Task Files"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.addExternalFolder(url) }
        }
        #else
        showFolderImporter = true
        #endif
    }
}
