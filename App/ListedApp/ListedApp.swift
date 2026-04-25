import SwiftUI
import ListedCore
import ListedUI

@main
struct ListedApp: App {
    @State private var model: AppModel?

    var body: some Scene {
        WindowGroup {
            ContentScene(model: model, onLoad: { await loadModel() })
        }
        .commands { appCommands }

        #if os(macOS)
        Settings {
            if let model {
                SettingsView()
                    .environment(model)
                    .frame(minWidth: 540, minHeight: 540)
            }
        }
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
    }
}

extension Notification.Name {
    static let listedNewTaskRequested = Notification.Name("listed.newTaskRequested")
    static let listedToggleCompletionRequested = Notification.Name("listed.toggleCompletionRequested")
}
