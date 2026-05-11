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
    /// Driven by `Notification.Name.listedNewTaskRequested` (posted by ⌘N on
    /// macOS, the toolbar `+` button, the macOS Dock right-click menu, and the
    /// iOS Home Screen long-press quick action). Lifting this state to
    /// `RootView` means the sheet works regardless of which sub-screen the
    /// user is on (sidebar, list, or detail).
    @State private var showAddSheet: Bool = false

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
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet(targetFileID: model.composerTargetFileID)
                .environment(model)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #else
                .frame(minWidth: 520, minHeight: 600)
                #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .listedNewTaskRequested)) { _ in
            // Don't stack on top of onboarding or settings — defer until they close.
            guard !showOnboarding, !showSettings else { return }
            showAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .listedNotificationTapped)) { notification in
            // Deep-link from a tapped reminder notification: find the task by
            // matching the raw line and source file, then select it.
            guard let userInfo = notification.userInfo,
                  let rawLine = userInfo["taskRawLine"] as? String,
                  let sourceFileString = userInfo["sourceFileID"] as? String,
                  let sourceFileID = UUID(uuidString: sourceFileString) else { return }
            if let task = model.loadedFiles.flatMap(\.tasks).first(where: {
                $0.rawLine == rawLine && $0.sourceFileID == sourceFileID
            }) {
                model.selectedTaskID = task.id
            }
        }
        .onAppear {
            if model.workspace.fileSources.isEmpty {
                showOnboarding = true
            }
            // Cold-launch via iOS Home Screen quick action: the AppDelegate
            // captured the shortcut into a static stash before any view mounted.
            // Drain it here.
            #if os(iOS)
            if PendingLaunchActions.consumeNewTaskRequest() {
                // Tiny delay so the onboarding-check above wins if appropriate.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !showOnboarding, !showSettings {
                        showAddSheet = true
                    }
                }
            }
            #endif
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
            SidebarView(usesPushNavigation: false)
                #if os(iOS)
                // Attach the Settings button to the **sidebar's** toolbar so it
                // shows up in iPad's leftmost column navigation bar. Placing the
                // toolbar on `NavigationSplitView` itself (via `.automatic`) is
                // unreliable on iPad — the button gets hidden when columns
                // collapse. macOS uses the native `Settings` scene + ⌘, so it
                // doesn't need this toolbar entry.
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                #endif
        } content: {
            TaskListView(usesPushNavigation: false)
        } detail: {
            if let task = model.selectedTask {
                TaskDetailView(task: task)
            } else {
                // Beautiful empty detail pane
                VStack(spacing: DesignTokens.spacingLG) {
                    Image(systemName: "square.text.square")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignTokens.accent.opacity(0.6), DesignTokens.accent.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    VStack(spacing: DesignTokens.spacingSM) {
                        Text("No task selected")
                            .font(.title3.weight(.medium))
                        Text("Select a task to see its details.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var iPhoneRoot: some View {
        NavigationStack {
            SidebarView(usesPushNavigation: true)
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
                    TaskListView(usesPushNavigation: true)
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
