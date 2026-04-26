import SwiftUI
import ListedCore
import ListedUI

@main
struct ListedApp: App {

    /// Build the AppModel **synchronously** at app-process init time, before any
    /// scene asks for `body`. This reads only the workspace JSON + per-file disk
    /// cache (both in Application Support, both microsecond-fast). It deliberately
    /// does NOT touch iCloud Drive — that happens later via `startBackgroundRefresh`.
    @State private var model: AppModel = AppModel.makeForLaunchSynchronously()

    var body: some Scene {
        #if os(macOS)
        // Use `Window` (singular) on macOS so the `id:` becomes the autosave key
        // for window frame + position. Combined with `.windowResizability(.contentSize)`,
        // macOS persists the user's last size and origin in the app's preferences plist.
        Window("Listed", id: "main") {
            ContentScene(model: model)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentSize)
        .commands { appCommands }

        Settings {
            SettingsView()
                .environment(model)
        }
        #else
        WindowGroup {
            ContentScene(model: model)
        }
        .commands { appCommands }
        #endif
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                NotificationCenter.default.post(name: .listedNewTaskRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Toggle Completion") {
                NotificationCenter.default.post(name: .listedToggleCompletionRequested, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

/// Hosts `RootView` and kicks off the background refresh + change-observer once
/// the scene mounts. There is no longer any "Loading…" intermediate state — the
/// model is always non-nil because it's built synchronously from the cache.
private struct ContentScene: View {
    let model: AppModel

    var body: some View {
        RootView()
            .environment(model)
            .task {
                // Start watching the repository for change events (used by the
                // file presenter / external editor flow), and kick off the real
                // iCloud / external-file read in the background. Both are no-ops
                // for the user's first frame — the cache already painted it.
                model.startObservingChanges()
                model.startBackgroundRefresh()
            }
            #if os(macOS)
            // Enforce a sensible minimum content size on macOS so the three-column
            // layout always has room for sidebar (220) + list (~420) + detail (~420)
            // plus toolbar chrome. SwiftUI translates this into the window's
            // `contentMinSize`, which the user-resize handles can't go below.
            .frame(minWidth: 1080, minHeight: 640)
            #endif
    }
}

extension Notification.Name {
    static let listedNewTaskRequested = Notification.Name("listed.newTaskRequested")
    static let listedToggleCompletionRequested = Notification.Name("listed.toggleCompletionRequested")
}
