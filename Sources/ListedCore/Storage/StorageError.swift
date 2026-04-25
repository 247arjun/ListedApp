import Foundation

/// Errors thrown by the storage layer.
public enum StorageError: Error, LocalizedError, Sendable {
    case iCloudUnavailable
    case fileNotFound(URL)
    case permissionLost(URL)
    case bookmarkStale(URL?)
    case encoding(URL)
    case writeConflict(URL)
    case ioError(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: return "iCloud Drive is unavailable."
        case .fileNotFound(let url): return "This task file could not be found: \(url.lastPathComponent)."
        case .permissionLost(let url): return "Listed no longer has access to \(url.lastPathComponent)."
        case .bookmarkStale: return "The saved location can no longer be opened. Please reconnect it."
        case .encoding(let url): return "\(url.lastPathComponent) is not valid UTF-8."
        case .writeConflict(let url): return "\(url.lastPathComponent) changed outside Listed."
        case .ioError(let underlying): return underlying
        }
    }
}
