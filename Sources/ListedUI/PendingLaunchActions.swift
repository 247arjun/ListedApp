import Foundation

/// Static stash for "the app was launched via a shortcut/intent before any
/// SwiftUI view existed." Platform-specific launch hooks (iOS UIApplicationDelegate
/// `application(_:didFinishLaunchingWithOptions:)` / scene `willConnectTo`) write
/// into this; the first SwiftUI view to mount drains it and decides what to do
/// (e.g. present `AddTaskSheet`).
///
/// All access goes through the static API; the underlying lock keeps it thread-
/// safe across the launch task and the main actor.
public enum PendingLaunchActions {
    private static let lock = NSLock()
    /// Access goes through `lock`, so the strict-concurrency checker can't see
    /// the synchronization. `nonisolated(unsafe)` opts this single property out
    /// of those checks while keeping the rest of the file safe.
    nonisolated(unsafe) private static var newTaskRequested: Bool = false

    /// Mark that the next view-mount should present the new-task sheet. Idempotent.
    public static func requestNewTaskOnLaunch() {
        lock.lock()
        newTaskRequested = true
        lock.unlock()
    }

    /// Returns `true` exactly once if a new-task launch was requested. Subsequent
    /// calls return `false` until something else sets it again.
    public static func consumeNewTaskRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if newTaskRequested {
            newTaskRequested = false
            return true
        }
        return false
    }
}
