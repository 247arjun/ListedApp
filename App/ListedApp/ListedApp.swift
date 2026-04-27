import SwiftUI
import ListedCore
import ListedUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@main
struct ListedApp: App {

    /// Build the AppModel **synchronously** at app-process init time, before any
    /// scene asks for `body`. This reads only the workspace JSON + per-file disk
    /// cache (both in Application Support, both microsecond-fast). It deliberately
    /// does NOT touch iCloud Drive — that happens later via `startBackgroundRefresh`.
    @State private var model: AppModel = AppModel.makeForLaunchSynchronously()

    /// macOS-only AppDelegate that keeps the process alive when the main window
    /// closes (so the menu bar item stays available, Mail/Messages-style) and
    /// re-opens the window when the user clicks the Dock icon.
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ListedAppDelegate.self) private var appDelegate
    #endif

    /// iOS-only AppDelegate that captures Home Screen quick-action launches
    /// (long-press the Listed icon → "New Task") and routes them into a
    /// notification the SwiftUI view tree can react to.
    #if os(iOS)
    @UIApplicationDelegateAdaptor(ListedIOSAppDelegate.self) private var iosAppDelegate
    #endif

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

        // Optional menu bar accessory. Visible by default; the user can turn it
        // off via Settings → Appearance → "Show in menu bar". When disabled the
        // entire scene disappears (the `.disabled(true)` would still show the
        // icon greyed-out, which we don't want).
        MenuBarExtra("Listed", systemImage: "checkmark.square.fill", isInserted: menuBarVisible) {
            MenuBarRoot()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentScene(model: model)
        }
        .commands { appCommands }
        #endif
    }

    #if os(macOS)
    /// Two-way binding for the `MenuBarExtra(isInserted:)` flag, sourced from the
    /// workspace's `AppSettings.menuBarEnabled`. Updates persist through
    /// `WorkspaceStore` so the choice survives app launches.
    private var menuBarVisible: Binding<Bool> {
        Binding(
            get: { model.workspace.settings.menuBarEnabled },
            set: { newValue in
                var updated = model.workspace
                updated.settings.menuBarEnabled = newValue
                try? model.workspaceStore.save(updated)
                model.replaceWorkspace(updated)
                Task { await model.repository.updateWorkspace(updated) }
            }
        )
    }
    #endif

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

#if os(macOS)
/// AppDelegate that gives Listed the standard "stays running with the menu bar"
/// behavior on macOS. Closing the main window does NOT terminate the process
/// when the menu bar item is enabled, mirroring how Mail / Messages / Music
/// behave. Clicking the Dock icon re-opens the main window.
final class ListedAppDelegate: NSObject, NSApplicationDelegate {

    /// Keep the app alive on last-window-close when the menu bar accessory is on
    /// (so the user still has a UI surface). When the menu bar is off, fall back
    /// to AppKit's normal "quit when the last window closes" behavior so we
    /// don't leave a hidden process running with no way to interact with it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !menuBarEnabledFromDisk()
    }

    /// When the user clicks the Dock icon (or the app is otherwise re-activated
    /// without a visible window), re-open the main window. Returning `true`
    /// tells AppKit it should restore Listed's previously-closed window;
    /// SwiftUI's `Window(id: "main")` scene picks this up and re-creates the
    /// content. We also forward `NSWorkspace.didActivateApplicationNotification`
    /// so the menu bar refresh trigger continues to fire.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Walk the existing windows; if one is hidden/miniaturized, surface it.
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return true
            }
        }
        // Returning `true` tells AppKit to perform its default behavior, which
        // for a SwiftUI `Window` scene is to re-create the window.
        return true
    }

    /// Read the persisted `menuBarEnabled` setting straight from the workspace
    /// JSON on disk. The delegate doesn't have a reference to the live AppModel,
    /// but the workspace JSON is the source of truth and is microsecond-fast to
    /// read. Defaults to `true` (matches `AppSettings.menuBarEnabled` default).
    private func menuBarEnabledFromDisk() -> Bool {
        let store = WorkspaceStore()
        if let workspace = try? store.load() {
            return workspace.settings.menuBarEnabled
        }
        return true
    }

    // MARK: - Dock menu

    /// Right-click on the Dock icon → shows our custom menu. Currently just
    /// "New Task" — handles the same `listedNewTaskRequested` notification the
    /// iOS Home Screen quick action uses, so both platforms route through one
    /// SwiftUI sheet (`AddTaskSheet` presented by `RootView`).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newTask = NSMenuItem(
            title: "New Task",
            action: #selector(handleDockNewTask),
            keyEquivalent: ""
        )
        newTask.target = self
        menu.addItem(newTask)
        return menu
    }

    @objc private func handleDockNewTask() {
        // Make sure there's a visible window; AppKit will route the sheet to it.
        NSApp.activate(ignoringOtherApps: true)
        var foundVisible = false
        for window in NSApp.windows where window.canBecomeMain {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            foundVisible = true
            break
        }
        if !foundVisible {
            // No window exists yet (app was running window-less in the menu bar).
            // Stash the request and let the SwiftUI scene drain it on first mount.
            PendingLaunchActions.requestNewTaskOnLaunch()
        }
        NotificationCenter.default.post(name: .listedNewTaskRequested, object: nil)
    }
}
#endif

// MARK: - iOS quick actions

#if os(iOS)
/// Captures Home Screen long-press quick-action launches on iOS. Cold launches
/// arrive in `application(_:didFinishLaunchingWithOptions:)`; warm launches go
/// through the scene delegate's `windowScene(_:performActionFor:)`. Both paths
/// post `.listedNewTaskRequested` so the SwiftUI view tree handles the rest.
final class ListedIOSAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            handleShortcut(item)
        }
        return true
    }

    /// Hand SwiftUI a custom `UISceneConfiguration` so the scene delegate below
    /// receives `windowScene(_:performActionFor:)` callbacks. Without this,
    /// scene-based apps don't get warm-launch shortcut delivery to the app
    /// delegate at all.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ListedSceneDelegate.self
        return config
    }

    fileprivate func handleShortcut(_ item: UIApplicationShortcutItem) {
        guard item.type == "app.listed.Listed.NewTask" else { return }
        // Stash for cold launches (no view mounted yet); also fire the
        // notification immediately for warm launches.
        PendingLaunchActions.requestNewTaskOnLaunch()
        NotificationCenter.default.post(name: .listedNewTaskRequested, object: nil)
    }
}

/// Scene delegate that catches both cold-via-scene and warm-launch shortcuts.
final class ListedSceneDelegate: NSObject, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            (UIApplication.shared.delegate as? ListedIOSAppDelegate)?.handleShortcut(item)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        (UIApplication.shared.delegate as? ListedIOSAppDelegate)?.handleShortcut(shortcutItem)
        completionHandler(true)
    }
}
#endif
