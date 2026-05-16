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

    /// Pre-filled values for the next presentation of `AddTaskSheet`. Set by
    /// group-header "+" buttons (via `.listedNewTaskRequested` notification's
    /// `object`); cleared on dismiss.
    @State private var addSheetPrefill: TaskPrefill?

    /// Whether the task-detail inspector pane is visible on iPad / macOS.
    /// Inspector slides in from the trailing edge over the task list, so the
    /// list (especially a Kanban board) gets the full window width when it's
    /// hidden. Opens automatically when the user selects a task; can be
    /// toggled manually from the toolbar.
    @State private var showInspector: Bool = false

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
        .sheet(isPresented: $showAddSheet, onDismiss: { addSheetPrefill = nil }) {
            AddTaskSheet(targetFileID: model.composerTargetFileID, prefill: addSheetPrefill)
                .environment(model)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #else
                .frame(minWidth: 520, minHeight: 600)
                #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .listedNewTaskRequested)) { notification in
            // Don't stack on top of onboarding or settings — defer until they close.
            guard !showOnboarding, !showSettings else { return }
            // Group-header "+" buttons attach a `TaskPrefill` to the
            // notification's `object`; the generic "+" toolbar button posts nil.
            addSheetPrefill = notification.object as? TaskPrefill
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
        // Two-column NavigationSplitView with the task list in the detail
        // slot. TaskDetailView rides as an `.inspector` over the list so the
        // user can collapse it on demand — critical for Kanban view to get
        // full window width.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(usesPushNavigation: false)
                // Suppress NavigationSplitView's auto-provided sidebar toggle
                // (which lives inside the sidebar's toolbar region and
                // disappears when the sidebar is collapsed). We supply our
                // own manual toggle in the detail toolbar below — keeping
                // both creates a redundant double-button when sidebar is open.
                .toolbar(removing: .sidebarToggle)
                #if os(iOS)
                // Settings gear lives in the sidebar's toolbar on iPad.
                // macOS uses the native `Settings { }` scene + ⌘, instead.
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                #endif
        } detail: {
            TaskListView(usesPushNavigation: false)
                .inspector(isPresented: $showInspector) {
                    inspectorContent
                        // Wide-enough minimum so the metadata grid's trailing
                        // controls (+/x buttons, date picker, chevrons) aren't
                        // clipped. iPad's default is too narrow.
                        .inspectorColumnWidth(min: 360, ideal: 440, max: 640)
                }
                .toolbar {
                    // Explicit sidebar toggle in the leading position.
                    // NavigationSplitView's auto-provided toggle attaches to
                    // the *sidebar's* toolbar region, which disappears when
                    // the sidebar is collapsed — leaving the user stranded
                    // with no way to bring it back. Adding our own in the
                    // detail's toolbar guarantees the affordance is always
                    // reachable.
                    ToolbarItem(placement: sidebarTogglePlacement) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Toggle Sidebar")
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }

                    // Inspector toggle — slides the task detail in/out.
                    // Uses `sidebar.right` (filled when active) to match the
                    // standard SwiftUI inspector affordance.
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showInspector.toggle()
                        } label: {
                            Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                                .symbolVariant(showInspector ? .fill : .none)
                        }
                        .help(showInspector ? "Hide Details" : "Show Details")
                        .keyboardShortcut("0", modifiers: [.command, .option])
                    }
                }
                .onChange(of: model.selectedTaskID) { _, new in
                    // Auto-open inspector when the user selects a task so a
                    // single tap reveals details. Don't auto-close on deselect
                    // — the user may want the inspector to persist as they
                    // browse adjacent tasks.
                    if new != nil { showInspector = true }
                }
        }
    }

    /// Cross-platform toolbar placement for the manual sidebar toggle.
    /// macOS uses `.navigation` (leftmost of the unified title bar);
    /// iOS/iPadOS uses `.topBarLeading` (leading edge of the nav bar).
    private var sidebarTogglePlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .navigation
        #else
        return .topBarLeading
        #endif
    }

    /// Inspector body — either the selected task's detail view or an empty
    /// placeholder. Shown in the trailing inspector pane on iPad / macOS.
    @ViewBuilder
    private var inspectorContent: some View {
        if let task = model.selectedTask {
            TaskDetailView(task: task)
        } else {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
