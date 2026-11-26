import SwiftUI

/// The downloads of the open camp: asks the server for a file on purpose, keeps it, lists it, removes it. Nothing is
/// downloaded by itself.
@MainActor @Observable
final class CampDownloader {
    let active: ActiveCamp
    private(set) var downloads: [CampDownload] = []
    private(set) var busy: Set<String> = []
    private(set) var error: String?
    private(set) var notice: String?
    @ObservationIgnored private var store: (any CampDownloadStore)? { active.client?.campDownloads }

    init(active: ActiveCamp) { self.active = active }

    func setPreview(downloads: [CampDownload], error: String? = nil, notice: String? = nil) {
        self.downloads = downloads
        self.error = error
        self.notice = notice
    }

    func dismissNotice() { notice = nil }

    func saved(_ source: CampDownloadSource) -> CampDownload? { downloads.first { $0.sourceKey == source.key } }

    func refresh() async {
        guard let store, let id = active.camp?.id else { return }
        downloads = await store.list().filter { $0.campId == id }
    }

    /// «Herunterladen» (also «Aktualisieren»: the new file replaces the old one).
    func download(_ source: CampDownloadSource, title: String) async {
        guard let client = active.client, let store, let camp = active.camp, !busy.contains(source.key) else { return }
        busy.insert(source.key)
        defer { busy.remove(source.key) }
        error = nil
        do {
            let data = try await client.campDownloadData(source, campId: camp.id)
            _ = try await store.save(data, source: source, campId: camp.id, campTitle: camp.title, title: title)
            await refresh()
            say(String(localized: "«\(title)» ist heruntergeladen. Du kannst sie auch ohne Netz öffnen."))
        } catch is CancellationError {
        } catch let failure as CampDownloadError {
            error = failure == .invalid ? String(localized: "Die Datei ist nicht gültig. Sie wurde nicht gespeichert.") : String(localized: "Die Datei konnte nicht gespeichert werden.")
        } catch {
            self.error = CampPhase(error: error).failureText
        }
    }

    func remove(_ source: CampDownloadSource) async {
        guard let download = saved(source) else { return }
        await store?.remove(download.id)
        await refresh()
        say(String(localized: "«\(download.title)» ist entfernt."))
    }

    func url(_ source: CampDownloadSource) async -> URL? {
        guard let download = saved(source) else { return nil }
        return await store?.fileURL(download)
    }

    private func say(_ text: String) {
        notice = text
        AccessibilityNotification.Announcement(text).post()
    }
}

nonisolated enum CampDownloadText {
    static func handout(_ handout: CampHandout) -> String {
        switch handout {
        case .shiftPlan: String(localized: "Schichtplan")
        case .roomList: String(localized: "Zimmerliste")
        case .doorSigns: String(localized: "Türschilder")
        case .groupLists: String(localized: "Gruppenlisten")
        case .tripList: String(localized: "Fahrtenliste")
        case .organigram: String(localized: "Organigramm")
        }
    }

    /// «PDF, 240 KB» or «Kalenderdatei, 2 KB».
    static func detail(_ download: CampDownload) -> String {
        let kind = download.kind == .pdf ? "PDF" : String(localized: "Kalenderdatei")
        return kind + ", " + ByteCountFormatter.string(fromByteCount: Int64(download.size), countStyle: .file)
    }
}
