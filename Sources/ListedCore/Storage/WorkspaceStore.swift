import Foundation

/// Persists the user's `Workspace` (file sources, task files, settings, presets) to
/// the app's Application Support directory as JSON. The workspace is metadata only —
/// the canonical task data lives in the user's `.txt` files.
public final class WorkspaceStore: @unchecked Sendable {

    private let resolver: FileURLResolver
    private let fileName = "workspace.json"
    private let queue = DispatchQueue(label: "com.listed.workspace-store")

    public init(resolver: FileURLResolver = FileURLResolver()) {
        self.resolver = resolver
    }

    public var fileURL: URL {
        resolver.applicationSupportURL().appendingPathComponent(fileName)
    }

    public func load() throws -> Workspace? {
        return try queue.sync {
            let url = fileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Workspace.self, from: data)
        }
    }

    public func save(_ workspace: Workspace) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workspace)
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}
