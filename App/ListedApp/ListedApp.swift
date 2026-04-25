import SwiftUI
import ListedCore
import ListedUI

@main
struct ListedApp: App {
    @State private var model: AppModel?

    var body: some Scene {
        #if os(macOS)
        // Use `Window` (singular) on macOS so the `id:` becomes the autosave key
        // for window frame + position. Combined with `.windowResizability(.contentSize)`,
        // macOS persists the user's last size and origin in the app's preferences plist.
        Window("Listed", id: "main") {
            ContentScene(model: model, onLoad: { await loadModel() })
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentSize)
        .commands { appCommands }

        Settings {
            if let model {
                SettingsView()
                    .environment(model)
            }
        }
        #else
        WindowGroup {
            ContentScene(model: model, onLoad: { await loadModel() })
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

    private func loadModel() async {
        let m = await AppModel.makeForLaunch()
        await MainActor.run {
            self.model = m
        }
    }
}

/// Tiny wrapper that flips between a loading state and the real `RootView`. Pulled
/// out so the `WindowGroup`'s view-builder body stays simple.
private struct ContentScene: View {
    let model: AppModel?
    let onLoad: () async -> Void

    var body: some View {
        Group {
            if let model {
                RootView()
                    .environment(model)
                    .task { model.startObservingChanges() }
            } else {
                ProgressView("Loading…")
                    .task { await onLoad() }
            }
        }
        // Enforce a sensible minimum content size on macOS so the three-column
        // layout always has room for sidebar (220) + list (~420) + detail (~420)
        // plus toolbar chrome. SwiftUI translates this into the window's
        // `contentMinSize`, which the user-resize handles can't go below.
        #if os(macOS)
        .frame(minWidth: 1080, minHeight: 640)
        #endif
    }
}

extension Notification.Name {
    static let listedNewTaskRequested = Notification.Name("listed.newTaskRequested")
    static let listedToggleCompletionRequested = Notification.Name("listed.toggleCompletionRequested")
}
