import Foundation

/// Resolves a `FileSource` + `TaskFile` pair to a usable `URL`. Centralizes the
/// security-scoped bookmark dance and the iCloud / app-container lookups so the
/// repository never has to know which kind of source it's reading.
public final class FileURLResolver: @unchecked Sendable {

    /// Identifier of the iCloud ubiquity container. `nil` means use the default.
    public var iCloudContainerIdentifier: String?

    /// Override hook for tests: when set, this URL is used as the iCloud Documents root.
    private let iCloudRootOverride: (() -> URL?)?

    /// Override hook for tests: when set, this URL is used as the local Documents root.
    private let localRootOverride: (() -> URL)?

    public init(
        iCloudContainerIdentifier: String? = nil,
        iCloudRootOverride: (() -> URL?)? = nil,
        localRootOverride: (() -> URL)? = nil
    ) {
        self.iCloudContainerIdentifier = iCloudContainerIdentifier
        self.iCloudRootOverride = iCloudRootOverride
        self.localRootOverride = localRootOverride
    }

    // MARK: - Roots

    /// Root URL of the app's iCloud Documents directory, if available.
    public func iCloudDocumentsURL() -> URL? {
        if let iCloudRootOverride { return iCloudRootOverride() }
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerIdentifier) else {
            return nil
        }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    /// Root URL of the app's local Documents directory.
    public func localDocumentsURL() -> URL {
        if let localRootOverride { return localRootOverride() }
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    /// Root URL of the app's Application Support directory (used for workspace metadata).
    public func applicationSupportURL() -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Listed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Resolution

    public struct ResolvedURL {
        public let url: URL
        /// True if `startAccessingSecurityScopedResource()` was called and must be balanced.
        public let didStartScope: Bool
        /// Set if the bookmark was stale and was refreshed during resolution.
        public let refreshedBookmark: Data?

        /// Convenience to balance the security scope.
        public func release() {
            if didStartScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    /// Resolve the root URL of a `FileSource`. The caller MUST call `release()` on the
    /// returned `ResolvedURL` when finished.
    public func resolveRoot(for source: FileSource) throws -> ResolvedURL {
        switch source.kind {
        case .appICloudContainer:
            guard let url = iCloudDocumentsURL() else {
                throw StorageError.iCloudUnavailable
            }
            try ensureDirectory(url)
            return ResolvedURL(url: url, didStartScope: false, refreshedBookmark: nil)
        case .appLocalContainer:
            let url = localDocumentsURL()
            try ensureDirectory(url)
            return ResolvedURL(url: url, didStartScope: false, refreshedBookmark: nil)
        case .securityScopedFolder, .securityScopedFile:
            return try resolveBookmark(source.rootBookmarkData)
        }
    }

    /// Resolve a `TaskFile` against its source.
    public func resolve(taskFile: TaskFile, in source: FileSource) throws -> ResolvedURL {
        let root = try resolveRoot(for: source)
        if source.kind == .securityScopedFile {
            // The source IS the file; the bookmark already points at it.
            return root
        }
        let fileURL = root.url.appendingPathComponent(taskFile.relativePath)
        return ResolvedURL(url: fileURL, didStartScope: root.didStartScope, refreshedBookmark: root.refreshedBookmark)
    }

    // MARK: - Bookmarks

    public func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private func resolveBookmark(_ data: Data?) throws -> ResolvedURL {
        guard let data else { throw StorageError.bookmarkStale(nil) }
        var isStale = false
        let url: URL
        do {
            #if os(macOS)
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #else
            url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #endif
        } catch {
            throw StorageError.bookmarkStale(nil)
        }
        let started = url.startAccessingSecurityScopedResource()
        if !started {
            // Some providers don't require it; treat as soft failure only when reads later fail.
        }
        let refreshed: Data? = isStale ? (try? makeBookmark(for: url)) : nil
        return ResolvedURL(url: url, didStartScope: started, refreshedBookmark: refreshed)
    }

    // MARK: - Helpers

    private func ensureDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw StorageError.ioError(underlying: "Expected directory at \(url.path)")
            }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
