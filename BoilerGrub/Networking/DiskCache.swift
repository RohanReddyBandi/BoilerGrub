import Foundation
import OSLog

/// A small JSON-on-disk cache keyed by string.
///
/// It lives in Application Support rather than Caches on purpose: a past day's
/// menu is immutable and worth keeping, and the system is free to evict Caches
/// whenever it likes.
actor DiskCache {
    /// Bumped whenever the persisted model shape changes, so old entries are
    /// ignored rather than mis-decoded. Decode failures are handled gracefully
    /// too; this just avoids doing that work on every read after a migration.
    private static let schemaVersion = "v1"

    private let directory: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.rohanreddybandi.BoilerGrub", category: "Cache")

    /// An entry read back from disk, with how long ago it was written.
    struct Entry<T> {
        let value: T
        let age: TimeInterval
    }

    init(name: String = "MenuCache") {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        directory = base.appendingPathComponent("BoilerGrub/\(name)", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Menus are re-downloadable; there's no reason to spend the user's
        // iCloud quota on them.
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    /// Reads an entry, or nil if it's missing, older than `maxAge`, or no longer
    /// decodable. A `maxAge` of nil means "never expires".
    func read<T: Decodable>(_ key: String, as type: T.Type = T.self, maxAge: TimeInterval?) -> Entry<T>? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        let age = Date().timeIntervalSince(written)

        if let maxAge, age > maxAge { return nil }

        do {
            return Entry(value: try JSONDecoder().decode(T.self, from: data), age: age)
        } catch {
            // Written by an older build with a different shape. Drop it quietly.
            logger.debug("discarding undecodable cache entry \(key, privacy: .public)")
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func write<T: Encodable>(_ value: T, key: String) {
        do {
            try JSONEncoder().encode(value).write(to: fileURL(for: key), options: .atomic)
        } catch {
            // A cache write failing is not worth surfacing or retrying; the app
            // simply goes back to the network next time.
            logger.debug("cache write failed for \(key, privacy: .public)")
        }
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Total bytes on disk, for the diagnostics row in Settings.
    func sizeOnDisk() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return directory.appendingPathComponent("\(Self.schemaVersion)-\(String(safe)).json")
    }
}
