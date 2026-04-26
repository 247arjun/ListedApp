import Foundation

/// Disposable on-device cache of the rendered text for each `TaskFile`.
///
/// The plain `.txt` files in the user's iCloud / external locations remain the
/// source of truth. This cache exists purely so the app can render the user's
/// last-known tasks **synchronously** at launch, without waiting for the iCloud
/// daemon (`bird`) to resolve the ubiquity container or for `NSFileCoordinator`
/// to download a file.
///
/// File layout, under Application Support / Listed / cache /:
///     <taskFileUUID>.txt       — the file's last-known UTF-8 text
///
/// Deleting the cache directory at any time is safe: the next refresh from the
/// real file source will rebuild it.
public final class TaskCacheStore: @unchecked Sendable {

    private let resolver: FileURLResolver

    public init(resolver: FileURLResolver = FileURLResolver()) {
        self.resolver = resolver
    }

    public var directoryURL: URL {
        let url = resolver.applicationSupportURL().appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func url(for taskFileID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(taskFileID.uuidString).txt")
    }

    // MARK: - Read / write

    /// Synchronously read the cached text for a task file. Returns `nil` if no
    /// cache exists yet (first launch, or after the user nuked the cache).
    public func cachedText(for taskFileID: UUID) -> String? {
        let url = url(for: taskFileID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Atomically write the latest known text to the cache. Errors are swallowed
    /// because cache failures must never bubble up to the user.
    public func write(_ text: String, for taskFileID: UUID) {
        let url = url(for: taskFileID)
        guard let data = text.data(using: .utf8) else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort. If the cache write fails we just lose the optimization
            // for the next launch; user data is unaffected.
        }
    }

    /// Drop the cache entry for a single task file (e.g. after the user removes
    /// it from the workspace).
    public func remove(_ taskFileID: UUID) {
        try? FileManager.default.removeItem(at: url(for: taskFileID))
    }

    /// Wipe the entire cache. Mostly useful for tests / settings "reset cache".
    public func clearAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
