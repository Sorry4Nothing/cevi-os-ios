import QuickLook
import SwiftUI

/// Root of «Aushänge» inside a navigation stack.
struct CampHandoutsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var downloader: CampDownloader?

    var body: some View {
        Group { if let downloader { CampHandoutsScreen(downloader: downloader) } else { Color.clear } }
            .task {
                guard downloader == nil else { return }
                let created = CampDownloader(active: active)
                downloader = created
                await created.refresh()
            }
    }
}

/// «Aushänge»: the printable sheets as PDF. The person downloads one on purpose and can open it without network.
struct CampHandoutsScreen: View {
    @Bindable var downloader: CampDownloader
    @State private var preview: URL?

    var body: some View {
        List {
            Section {
                if let notice = downloader.notice { Label(notice, systemImage: "checkmark.circle").font(.subheadline).accessibilityAddTraits(.updatesFrequently) }
                if let error = downloader.error { ErrorRow(text: error) }
                ForEach(CampHandout.allCases, id: \.self) { handout in row(handout) }
            } footer: {
                Text("Heruntergeladene Aushänge bleiben auf diesem Gerät, bis du sie entfernst, dich abmeldest oder das Lager gelöscht wird. Du findest sie auch im Profil.")
            }
        }
        .environment(\.headerProminence, .increased)
        .scrollContentBackground(.hidden)
        .ceviScreenBackground()
        .navigationTitle("Aushänge")
        .navigationBarTitleDisplayMode(.large)
        .quickLookPreview($preview)
    }

    private func row(_ handout: CampHandout) -> some View {
        let source = CampDownloadSource.handout(handout)
        let title = CampDownloadText.handout(handout)
        let saved = downloader.saved(source)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title).font(.headline).foregroundStyle(Color.ceviOnSurface)
            if let saved { Text(CampDownloadText.detail(saved)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            // Three buttons wrap below each other at the large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s3) { actions(source, title: title, saved: saved != nil) }
                VStack(alignment: .leading, spacing: 0) { actions(source, title: title, saved: saved != nil) }
            }
        }
        .padding(.vertical, Spacing.s1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ source: CampDownloadSource, title: String, saved: Bool) -> some View {
        if downloader.busy.contains(source.key) {
            ProgressView().frame(minHeight: Size.touchTarget)
            Text("Wird geladen").font(.subheadline)
        } else if saved {
            Button("Öffnen") { Task { preview = await downloader.url(source) } }.buttonStyle(.ceviText)
            Button("Aktualisieren") { Task { await downloader.download(source, title: title) } }.buttonStyle(.ceviText)
            Button("Entfernen", role: .destructive) { Task { await downloader.remove(source) } }.buttonStyle(.ceviText)
        } else {
            Button("Herunterladen") { Task { await downloader.download(source, title: title) } }.buttonStyle(.ceviText)
        }
    }
}

#if DEBUG
private func sample(_ handout: CampHandout, _ title: String) -> CampDownload {
    let id = UUID()
    return CampDownload(id: id, campId: UUID(), campTitle: "Sommerlager 2027", title: title, sourceKey: CampDownloadSource.handout(handout).key,
                        kind: .pdf, fileName: id.uuidString.lowercased() + ".pdf", savedAt: Date(), size: 240_000)
}

@MainActor private func handoutsPreview(downloads: [CampDownload] = [], error: String? = nil) -> some View {
    let active = CampPreview.active(role: .campLeader)
    let downloader = CampDownloader(active: active)
    downloader.setPreview(downloads: downloads, error: error)
    return NavigationStack { CampHandoutsScreen(downloader: downloader) }.environment(active)
}

#Preview("Aushänge") { handoutsPreview() }
#Preview("Aushänge mit Download") { handoutsPreview(downloads: [sample(.roomList, "Zimmerliste")]) }
#Preview("Aushänge Fehler") { handoutsPreview(error: "Das hat nicht geklappt. Bitte versuche es nochmals.") }
#Preview("Aushänge Nacht") { handoutsPreview(downloads: [sample(.roomList, "Zimmerliste")]).preferredColorScheme(.dark) }
#endif
