import SwiftUI
import ListedCore

/// Three-column-aware sidebar shared by macOS and iPad. iPhone presents this as a
/// stand-alone screen.
public struct SidebarView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var bindable = model

        List(selection: Binding(
            get: { Optional(model.selection) },
            set: { newValue in
                if let newValue { model.selection = newValue }
            }
        )) {
            Section("Smart Lists") {
                ForEach(TaskQuery.SmartList.allCases, id: \.self) { kind in
                    NavigationLink(value: SidebarSelection.smartList(kind)) {
                        Label(label(for: kind), systemImage: icon(for: kind))
                            .badge(model.taskCount(for: .smartList(kind)))
                    }
                }
            }

            if !model.activeTaskFiles.isEmpty {
                Section("Files") {
                    ForEach(model.activeTaskFiles) { file in
                        NavigationLink(value: SidebarSelection.file(file.id)) {
                            Label(file.displayName, systemImage: "doc.text")
                                .badge(model.taskCount(for: .file(file.id)))
                        }
                    }
                }
            }

            if !model.allProjects.isEmpty {
                Section("Projects") {
                    ForEach(model.allProjects, id: \.self) { project in
                        NavigationLink(value: SidebarSelection.project(project)) {
                            Label("+\(project)", systemImage: "number")
                        }
                    }
                }
            }

            if !model.allContexts.isEmpty {
                Section("Contexts") {
                    ForEach(model.allContexts, id: \.self) { context in
                        NavigationLink(value: SidebarSelection.context(context)) {
                            Label("@\(context)", systemImage: "at")
                        }
                    }
                }
            }

            if !model.usedPriorities.isEmpty {
                Section("Priorities") {
                    ForEach(model.usedPriorities, id: \.self) { priority in
                        NavigationLink(value: SidebarSelection.priority(priority)) {
                            Label("Priority " + String(priority), systemImage: "flag.fill")
                                .foregroundStyle(DesignTokens.priorityColor(priority))
                        }
                    }
                }
            }
        }
        .navigationTitle("Listed")
        #if os(macOS)
        .frame(minWidth: 220)
        #endif
    }

    private func label(for kind: TaskQuery.SmartList) -> String {
        switch kind {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .all: return "All"
        case .inbox: return "Inbox"
        case .completed: return "Completed"
        }
    }

    private func icon(for kind: TaskQuery.SmartList) -> String {
        switch kind {
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .all: return "tray.full"
        case .inbox: return "tray"
        case .completed: return "checkmark.circle"
        }
    }
}
