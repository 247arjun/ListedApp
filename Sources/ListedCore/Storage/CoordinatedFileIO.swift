import Foundation

/// Atomic UTF-8 read/write of small text files, using `NSFileCoordinator` so external
/// editors and iCloud Drive remain consistent.
public struct CoordinatedFileIO: Sendable {

    public init() {}

    // MARK: - Read

    public func readUTF8(at url: URL) throws -> String {
        var coordinatorError: NSError?
        var result: String = ""
        var thrown: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinatorError) { newURL in
            do {
                let data = try Data(contentsOf: newURL)
                if let str = String(data: data, encoding: .utf8) {
                    result = str
                } else if let str = String(data: data, encoding: .utf8) {
                    result = str
                } else {
                    thrown = StorageError.encoding(newURL)
                }
            } catch {
                if (error as NSError).code == NSFileReadNoSuchFileError {
                    thrown = StorageError.fileNotFound(newURL)
                } else {
                    thrown = StorageError.ioError(underlying: error.localizedDescription)
                }
            }
        }
        if let coordinatorError {
            throw StorageError.ioError(underlying: coordinatorError.localizedDescription)
        }
        if let thrown { throw thrown }
        return result
    }

    // MARK: - Write (atomic)

    /// Atomically write `text` as UTF-8 to `url`, coordinating with file presenters.
    /// Uses `Data.write(to:options:[.atomic])` so partially-written files never appear.
    public func writeUTF8(_ text: String, to url: URL) throws {
        var coordinatorError: NSError?
        var thrown: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinatorError) { newURL in
            do {
                try ensureContainerExists(for: newURL)
                guard let data = text.data(using: .utf8) else {
                    thrown = StorageError.encoding(newURL)
                    return
                }
                try data.write(to: newURL, options: [.atomic])
            } catch {
                thrown = StorageError.ioError(underlying: error.localizedDescription)
            }
        }
        if let coordinatorError {
            throw StorageError.ioError(underlying: coordinatorError.localizedDescription)
        }
        if let thrown { throw thrown }
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func deleteFile(at url: URL) throws {
        guard fileExists(at: url) else { return }
        var coordinatorError: NSError?
        var thrown: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinatorError) { newURL in
            do {
                try FileManager.default.removeItem(at: newURL)
            } catch {
                thrown = StorageError.ioError(underlying: error.localizedDescription)
            }
        }
        if let coordinatorError {
            throw StorageError.ioError(underlying: coordinatorError.localizedDescription)
        }
        if let thrown { throw thrown }
    }

    // MARK: - Helpers

    private func ensureContainerExists(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
