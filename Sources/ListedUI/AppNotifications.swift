import Foundation

/// Cross-platform notification names used to broadcast user intents from
/// platform-specific entry points (Dock right-click on macOS, app icon
/// long-press on iOS, ⌘N command, etc.) into the SwiftUI view tree.
public extension Notification.Name {
    /// Posted when the user requests a new task via any platform-specific shortcut.
    /// `RootView` listens and presents the `AddTaskSheet`.
    static let listedNewTaskRequested = Notification.Name("listed.newTaskRequested")

    /// Posted when the user invokes the "Toggle Completion" command (⌘↩ on macOS).
    /// Currently observed at the row level.
    static let listedToggleCompletionRequested = Notification.Name("listed.toggleCompletionRequested")
}
