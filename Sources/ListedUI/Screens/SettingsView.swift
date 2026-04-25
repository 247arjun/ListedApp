import SwiftUI
import ListedCore
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Settings screen used as a sheet on iOS and a Settings window on macOS.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showFileImporter: Bool = false
    @State private var showFolderImporter: Bool = false

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
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Add creation date to new tasks", isOn: bind(\.settings.addCreationDateToNewTasks))
            Toggle("Add UID to new tasks", isOn: bind(\.settings.addUIDToNewTasks))
            Toggle("Preserve priority on completion", isOn: bind(\.settings.preservePriorityOnCompletion))
            Toggle("Auto-archive completed tasks", isOn: bind(\.settings.autoArchiveCompletedTasks))
            Toggle("Show completed tasks in lists", isOn: bind(\.settings.showCompletedInLists))
        }
    }

    // MARK: - Rows

    private func sourceRow(_ source: FileSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: source.kind))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName).font(.body)
                Text(label(for: source.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if source.isDefault {
                Text("Default")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(.tint.opacity(0.15)))
            }
        }
        .padding(.vertical, 2)
    }

    private func fileRow(_ file: TaskFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.role == .completedArchive ? "tray.full" : "doc.text")
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                Text(file.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if file.id == model.workspace.defaultTaskFileID {
                Text("Default")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(.tint.opacity(0.15)))
            } else if file.role == .activeTodo {
                Button("Make default") {
                    Task { await model.setDefaultFile(file.id) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
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
