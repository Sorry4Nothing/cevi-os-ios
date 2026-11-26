import Foundation

/// The snapshot file in the container of the app group. Both sides use the same code; only the app writes.
///
/// Without an app group (free development team) `directory` is `nil`: nothing is written, nothing is read, the app runs on.
nonisolated struct WidgetStore: Sendable {
    /// A larger file is not ours (the real one is a few KB); the widget does not parse it.
    static let maxBytes = 256 * 1024
    static let fileName = "widget-snapshot.json"

    let directory: URL?

    /// The group id comes from `AppGroupIdentifier` in the Info.plist (set per environment in `Config/*.xcconfig`).
    static var shared: WidgetStore {
        let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        let url = id.flatMap { $0.isEmpty || $0.contains("$(") ? nil : FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        return WidgetStore(directory: url)
    }

    var isAvailable: Bool { directory != nil }
    private var file: URL? { directory?.appending(path: Self.fileName, directoryHint: .notDirectory) }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Atomic, readable after the first unlock (the widget runs with a locked device), excluded from the backup.
    @discardableResult
    func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard var file, let data = try? Self.encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? file.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    /// `nil` for no file, a file that is too large, damaged or from another version.
    func read() -> WidgetSnapshot? {
        guard let file, let data = try? Data(contentsOf: file), data.count <= Self.maxBytes,
              let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    /// Sign-out and session end: all data goes, only the marker «signed out» stays.
    func clear() { write(.signedOut()) }
}
