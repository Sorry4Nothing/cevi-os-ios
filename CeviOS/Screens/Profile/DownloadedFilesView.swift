import QuickLook
import SwiftUI

/// «Heruntergeladene Dateien»: what the person downloaded on purpose, from all camps. Open it without network or remove it.
@MainActor @Observable
final class DownloadedFilesModel {
    private(set) var downloads: [CampDownload] = []
    private(set) var notice: String?
    @ObservationIgnored private let store: (any CampDownloadStore)?

    init(store: (any CampDownloadStore)?) { self.store = store }

    func setPreview(_ downloads: [CampDownload]) { self.downloads = downloads }

    func load() async { downloads = await store?.list() ?? [] }

    func remove(_ download: CampDownload) async {
        await store?.remove(download.id)
        await load()
        notice = String(localized: "«\(download.title)» ist entfernt.")
        AccessibilityNotification.Announcement(notice ?? "").post()
    }

    func url(_ download: CampDownload) async -> URL? { await store?.fileURL(download) }

    /// Camps by name, the newest download first inside a camp.
    var groups: [(campTitle: String, items: [CampDownload])] {
        Dictionary(grouping: downloads, by: \.campTitle).map { ($0.key, $0.value.sorted { $0.savedAt > $1.savedAt }) }.sorted { $0.campTitle < $1.campTitle }
    }
}

struct DownloadedFilesView: View {
    @Environment(AppState.self) private var state
    @State private var model: DownloadedFilesModel?

    var body: some View {
        Group { if let model { DownloadedFilesScreen(model: model) } else { Color.clear } }
            .task {
                let created = model ?? DownloadedFilesModel(store: state.client?.campDownloads)
                model = created
                await created.load()
            }
    }
}

struct DownloadedFilesScreen: View {
    @Bindable var model: DownloadedFilesModel
    @State private var preview: URL?

    var body: some View {
        List {
            if model.downloads.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Noch nichts heruntergeladen").font(.headline)
                        Text("Im Lager kannst du Aushänge und die Kalenderdatei eines Hoecks herunterladen. Sie stehen dann hier, auch ohne Netz.")
                            .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                    .padding(.vertical, Spacing.s2)
                }
            }
            if let notice = model.notice {
                Section { Label(notice, systemImage: "checkmark.circle").font(.subheadline).accessibilityAddTraits(.updatesFrequently) }
            }
            ForEach(model.groups, id: \.campTitle) { group in
                Section(group.campTitle) {
                    ForEach(group.items) { download in row(download) }
                }
            }
        }
        .environment(\.headerProminence, .increased)
        .scrollContentBackground(.hidden)
        .ceviScreenBackground()
        .navigationTitle("Heruntergeladene Dateien")
        .navigationBarTitleDisplayMode(.large)
        .quickLookPreview($preview)
    }

    private func row(_ download: CampDownload) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(download.title).font(.headline).foregroundStyle(Color.ceviOnSurface)
            Text(CampDownloadText.detail(download) + ", " + CampRosterText.stamp(download.savedAt, now: Date()))
                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s3) { buttons(download) }
                VStack(alignment: .leading, spacing: 0) { buttons(download) }
            }
        }
        .padding(.vertical, Spacing.s1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func buttons(_ download: CampDownload) -> some View {
        Button("Öffnen") { Task { preview = await model.url(download) } }.buttonStyle(.ceviText)
        Button("Entfernen", role: .destructive) { Task { await model.remove(download) } }.buttonStyle(.ceviText)
    }
}

#if DEBUG
@MainActor private func filesPreview(_ downloads: [CampDownload]) -> some View {
    let model = DownloadedFilesModel(store: nil)
    model.setPreview(downloads)
    return NavigationStack { DownloadedFilesScreen(model: model) }
}

private func sampleDownload(_ title: String, kind: CampDownloadKind, source: CampDownloadSource) -> CampDownload {
    let id = UUID()
    return CampDownload(id: id, campId: UUID(), campTitle: "Sommerlager 2027", title: title, sourceKey: source.key, kind: kind,
                        fileName: id.uuidString.lowercased() + "." + kind.fileExtension, savedAt: Date(), size: 240_000)
}

#Preview("Heruntergeladene Dateien") {
    filesPreview([sampleDownload("Zimmerliste", kind: .pdf, source: .handout(.roomList)),
                  sampleDownload("Kalenderdatei Hoeck", kind: .calendar, source: .meetingCalendar(UUID()))])
}
#Preview("Heruntergeladene Dateien leer") { filesPreview([]) }
#Preview("Heruntergeladene Dateien Nacht") {
    filesPreview([sampleDownload("Zimmerliste", kind: .pdf, source: .handout(.roomList))]).preferredColorScheme(.dark)
}
#endif
