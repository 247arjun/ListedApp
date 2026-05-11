import Foundation

/// Watches a single file or directory for external changes (iCloud sync,
/// another editor, etc.) via `NSFilePresenter`. When the content changes,
/// fires a callback so the `TaskRepository` can reload.
///
/// This is the companion piece to `CoordinatedFileIO`'s `NSFileCoordinator` usage.
/// When iCloud writes a synced file, `NSFileCoordinator` notifies all registered
/// `NSFilePresenter`s — including ours — so we get real-time change detection
/// without polling.
public final class TaskFileWatcher: NSObject, NSFilePresenter, Sendable {

    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue

    private let onChange: @Sendable () -> Void

    /// Create a watcher for a specific file or directory.
    ///
    /// - Parameters:
    ///   - url: The file or directory to watch.
    ///   - onChange: Called (on an arbitrary queue) when the item changes.
    ///     The callback should debounce before performing heavy work.
    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        let queue = OperationQueue()
        queue.name = "app.listed.fileWatcher.\(url.lastPathComponent)"
        queue.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = queue
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    /// Stop watching. Safe to call multiple times.
    public func stop() {
        NSFileCoordinator.removeFilePresenter(self)
    }

    // MARK: - NSFilePresenter callbacks

    /// Called when another coordinated writer modifies the file (iCloud sync,
    /// external editor, etc.).
    public func presentedItemDidChange() {
        onChange()
    }

    /// Called when the file content is replaced (e.g., atomic write from another process).
    public func accommodatePresentedItemEviction(completionHandler: @escaping (Error?) -> Void) {
        onChange()
        completionHandler(nil)
    }

    /// Called when a sub-item in a watched directory changes (for folder sources).
    public func presentedSubitemDidChange(at url: URL) {
        // Only care about .txt files
        guard url.pathExtension.lowercased() == "txt" else { return }
        onChange()
    }

    /// Called when a new sub-item appears in a watched directory (for folder sources).
    public func presentedSubitemDidAppear(at url: URL) {
        guard url.pathExtension.lowercased() == "txt" else { return }
        onChange()
    }

    /// Called when a sub-item is removed from a watched directory.
    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        if url.pathExtension.lowercased() == "txt" {
            onChange()
        }
        completionHandler(nil)
    }

    /// Called when the file moves (iCloud can do this during sync).
    public func presentedItemDidMove(to newURL: URL) {
        onChange()
    }
}
