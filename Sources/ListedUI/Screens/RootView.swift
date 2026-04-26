import SwiftUI
import ListedCore

/// Root content for the app. Hosts the navigation split view on macOS / iPad and a
/// stack-based layout on iPhone. Liquid Glass surfaces (toolbars, search bar, sidebar
/// chrome) come from the system on macOS 26 / iOS 26.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showOnboarding: Bool = false
    @State private var showSettings: Bool = false

    public init() {}

    public var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                iPhoneRoot
            } else {
                splitRoot
            }
            #else
            splitRoot
            #endif
        }
        .alert(item: errorBinding) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")) { model.dismissError() })
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
        .onAppear {
            if model.workspace.fileSources.isEmpty {
                showOnboarding = true
            }
        }
    }

    // MARK: - Bindings

    private var errorBinding: Binding<AppErrorIdentifiable?> {
        Binding(
            get: {
                guard let error = model.lastError else { return nil }
                return AppErrorIdentifiable(error: error)
            },
            set: { _ in model.dismissError() }
        )
    }

    // MARK: - Layouts

    private var splitRoot: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            TaskListView()
        } detail: {
            if let task = model.selectedTask {
                TaskDetailView(task: task)
            } else {
                ContentUnavailableView("No task selected", systemImage: "square.text.square", description: Text("Select a task to see its details."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private var iPhoneRoot: some View {
        NavigationStack {
            SidebarView()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                // Both destination registrations live at the NavigationStack
                // root. Nesting `navigationDestination(for:)` *inside* another
                // destination's closure is unreliable on iOS 26 — taps light
                // up but don't push because SwiftUI fails to find the inner
                // registration during the path resolution. Registering both
                // at the same level avoids the issue.
                .navigationDestination(for: SidebarSelection.self) { selection in
                    TaskListView()
                        .onAppear { model.selection = selection }
                }
                .navigationDestination(for: TodoTaskID.self) { taskID in
                    if let task = model.loadedFiles.flatMap(\.tasks).first(where: { $0.id == taskID }) {
                        TaskDetailView(task: task)
                    }
                }
        }
    }
}

private struct AppErrorIdentifiable: Identifiable {
    let id = UUID()
    let error: AppError
    var title: String { error.title }
    var message: String { error.message }
}
