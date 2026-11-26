import Foundation

/// Where downloaded files live. Only files the person asked for; nothing is downloaded by itself.
nonisolated protocol CampDownloadStore: Sendable {
    func list() async -> [CampDownload]
    /// Keeps the file and replaces an earlier download of the same source in the same camp.
    func save(_ data: Data, source: CampDownloadSource, campId: UUID, campTitle: String, title: String) async throws -> CampDownload
    func fileURL(_ download: CampDownload) async -> URL?
    func remove(_ id: UUID) async
    func removeCamp(_ id: UUID) async
    /// Deletes the downloads of every camp that is not in `ids` (the camp does not exist any more).
    func keepOnly(campIds ids: Set<UUID>) async
    func removeAll() async
}

/// App-internal folder in Application Support: file names are generated (UUID and extension, never taken from the server),
/// complete file protection, excluded from the device backup. The index lists the files; a file that is not listed or an
/// entry with an unexpected name is ignored and deleted. Writes nothing to the log.
actor CampFileDownloads: CampDownloadStore {
    private let directory: URL
    private var index: [CampDownload]?

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appending(path: "index.json", directoryHint: .notDirectory) }

    func list() -> [CampDownload] { entries().sorted { $0.savedAt > $1.savedAt } }

    func save(_ data: Data, source: CampDownloadSource, campId: UUID, campTitle: String, title: String) throws -> CampDownload {
        guard source.kind.accepts(data) else { throw CampDownloadError.invalid }
        let id = UUID()
        let download = CampDownload(
            id: id, campId: campId, campTitle: campTitle, title: title, sourceKey: source.key, kind: source.kind,
            fileName: id.uuidString.lowercased() + "." + source.kind.fileExtension, savedAt: Date(), size: data.count
        )
        do {
            try prepareDirectory()
            try data.write(to: directory.appending(path: download.fileName, directoryHint: .notDirectory), options: [.atomic, .completeFileProtection])
        } catch { throw CampDownloadError.storage }
        let old = entries().filter { $0.campId == campId && $0.sourceKey == source.key }
        write(entries().filter { entry in !old.contains { $0.id == entry.id } } + [download])
        for entry in old { delete(entry) }
        return download
    }

    func fileURL(_ download: CampDownload) -> URL? {
        guard let entry = entries().first(where: { $0.id == download.id }), Self.isSafe(entry) else { return nil }
        let url = directory.appending(path: entry.fileName, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func remove(_ id: UUID) { drop { $0.id == id } }
    func removeCamp(_ id: UUID) { drop { $0.campId == id } }
    func keepOnly(campIds ids: Set<UUID>) { drop { !ids.contains($0.campId) } }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        index = []
    }

    /// The generated name only: UUID and one of the two extensions. Anything else never leaves the folder.
    static func isSafe(_ entry: CampDownload) -> Bool {
        entry.fileName == entry.id.uuidString.lowercased() + "." + entry.kind.fileExtension
    }

    private func entries() -> [CampDownload] {
        if let index { return index }
        let loaded = ((try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([CampDownload].self, from: $0) } ?? []).filter(Self.isSafe)
        index = loaded
        return loaded
    }

    private func drop(_ matches: (CampDownload) -> Bool) {
        let all = entries()
        let gone = all.filter(matches)
        guard !gone.isEmpty else { return }
        write(all.filter { !matches($0) })
        for entry in gone { delete(entry) }
    }

    private func delete(_ entry: CampDownload) {
        guard Self.isSafe(entry) else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: entry.fileName, directoryHint: .notDirectory))
    }

    private func write(_ all: [CampDownload]) {
        index = all
        guard let data = try? JSONEncoder().encode(all), (try? prepareDirectory()) != nil else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
}

extension APIClient {
    /// The bytes of a file the person asked for (`GET …/hoecks/{id}.ics` or `GET …/aushaenge/{art}`).
    func campDownloadData(_ source: CampDownloadSource, campId: UUID) async throws -> Data {
        switch source {
        case .meetingCalendar(let id): try await campMeetingCalendar(campId: campId, meetingId: id)
        case .handout(let handout): try await campHandout(campId: campId, handout)
        }
    }
}
