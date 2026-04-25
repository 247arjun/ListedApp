import SwiftUI
import ListedCore
#if canImport(UIKit)
import UniformTypeIdentifiers
#endif

/// Settings screen used as a sheet on iOS and a window on macOS.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showFileImporter: Bool = false
    @State private var showFolderImporter: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Storage") {
                    ForEach(model.workspace.fileSources) { source in
                        sourceRow(source)
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Add Task File…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showFolderImporter = true
                    } label: {
                        Label("Add Folder of Files…", systemImage: "folder.badge.plus")
                    }
                }

                Section("Files") {
                    ForEach(model.workspace.taskFiles) { file in
                        fileRow(file)
                    }
                }

                Section("Behavior") {
                    Toggle("Add creation date to new tasks", isOn: bind(\.settings.addCreationDateToNewTasks))
                    Toggle("Add UID to new tasks", isOn: bind(\.settings.addUIDToNewTasks))
                    Toggle("Preserve priority on completion", isOn: bind(\.settings.preservePriorityOnCompletion))
                    Toggle("Auto-archive completed tasks", isOn: bind(\.settings.autoArchiveCompletedTasks))
                    Toggle("Show completed tasks in lists", isOn: bind(\.settings.showCompletedInLists))
                    Toggle("Show raw metadata in rows", isOn: bind(\.settings.showRawMetadataInRows))
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
                handleFileImport(result)
            }
            .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleFolderImport(result)
            }
        }
        .frame(minWidth: 480, minHeight: 480)
    }

    // MARK: - Rows

    private func sourceRow(_ source: FileSource) -> some View {
        HStack {
            Image(systemName: icon(for: source.kind))
                .frame(width: 24)
            VStack(alignment: .leading) {
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
    }

    private func fileRow(_ file: TaskFile) -> some View {
        HStack {
            Image(systemName: file.role == .completedArchive ? "tray.full" : "doc.text")
                .frame(width: 24)
            VStack(alignment: .leading) {
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

    // MARK: - Importers

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.addExternalFile(url) }
        case .failure:
            break
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.addExternalFolder(url) }
        case .failure:
            break
        }
    }
}
