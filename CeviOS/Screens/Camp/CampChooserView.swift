import SwiftUI

/// L1: the camps of the person. Not shown as a tab: opened from the switcher and from «Mehr».
struct CampChooserView: View {
    let model: CampListModel
    let retry: () -> Void
    let choose: (CampListEntry) -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .loading where model.camps.isEmpty:
                LoadingView(label: "Lager werden geladen")
            case .failed(let state, _) where model.camps.isEmpty:
                if let state, state.isFullScreen, state != .offline {
                    CampStateView(state: state, retry: retry)
                } else {
                    StateView.failure(retry: retry)
                }
            default:
                if model.camps.isEmpty {
                    StateView(symbol: "tent", title: "Du bist in keinem Lager",
                              message: "Sobald dich die Lagerleitung hinzufügt, erscheint das Lager hier.")
                } else {
                    list
                }
            }
        }
        .navigationTitle("Deine Lager")
        .navigationBarTitleDisplayMode(.large)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                if case .failed(_, let text) = model.phase { ErrorRow(text: text) }
                ForEach(model.openCamps) { entry in
                    Button { choose(entry) } label: { card(entry) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(label(entry)))
                }
                if !model.closedCamps.isEmpty {
                    Text("Abgeschlossen").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.closedCamps) { entry in
                        Button { choose(entry) } label: { row(entry) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(label(entry)))
                    }
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .refreshable { retry() }
        .ceviScreenBackground()
    }

    private func card(_ entry: CampListEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.camp.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                Spacer(minLength: Spacing.s2)
                // A word with a symbol, not only a color.
                Label(entry.camp.status == .active ? "Aktiv" : "Entwurf", systemImage: entry.camp.status == .active ? "checkmark" : "pencil")
                    .font(.caption.bold()).foregroundStyle(Color.ceviOnSecondaryContainer)
                    .padding(.horizontal, Spacing.s2).padding(.vertical, Spacing.s1)
                    .background(Color.ceviSecondaryContainer, in: .capsule)
            }
            Text(details(entry)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            Text("Deine Rolle: \(CampRoleText.name(entry.role))").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }

    private func row(_ entry: CampListEntry) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "tent").foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(entry.camp.title).font(.body.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
                Text("\(CampFormat.dates(from: entry.camp.from, to: entry.camp.to)), nur lesen")
                    .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
        }
        .frame(minHeight: Size.touchTarget)
        .ceviCard()
    }

    private func details(_ entry: CampListEntry) -> String {
        let dates = CampFormat.dates(from: entry.camp.from, to: entry.camp.to)
        return entry.camp.place.map { "\(dates), \($0)" } ?? dates
    }

    private func label(_ entry: CampListEntry) -> String {
        let status = switch entry.camp.status {
        case .active: String(localized: "aktiv")
        case .draft: String(localized: "Entwurf")
        case .completed, .archived: String(localized: "abgeschlossen, nur lesen")
        }
        return "\(entry.camp.title), \(status), \(details(entry)), \(String(localized: "Deine Rolle")): \(CampRoleText.name(entry.role))"
    }
}

/// Role names as the design shows them.
nonisolated enum CampRoleText {
    static func name(_ role: CampRole) -> String {
        switch role {
        case .campLeader: String(localized: "Lagerleitung")
        case .leader: String(localized: "Leitung")
        case .team: String(localized: "Team")
        case .readOnly: String(localized: "Lesen")
        }
    }
}

#Preview("L1 Normal") { CampChooserPreview.make(.loaded) }
#Preview("L1 Laden") { CampChooserPreview.make(.loading) }
#Preview("L1 Leer") { CampChooserPreview.make(.loaded, empty: true) }
#Preview("L1 Fehler") { CampChooserPreview.make(.failed(state: nil, text: "x"), empty: true) }
#Preview("L1 Nacht") { CampChooserPreview.make(.loaded).preferredColorScheme(.dark) }
#Preview("L1 AX3") { CampChooserPreview.make(.loaded).dynamicTypeSize(.accessibility3) }

/// Sample data for the previews, invented.
@MainActor
enum CampChooserPreview {
    static func make(_ phase: CampListModel.Phase, empty: Bool = false) -> some View {
        NavigationStack {
            CampChooserView(model: .preview(phase, empty: empty), retry: {}, choose: { _ in })
        }
    }
}

extension CampListModel {
    static func preview(_ phase: Phase, empty: Bool = false) -> CampListModel {
        let model = CampListModel()
        model.setPreview(phase: phase, camps: empty ? [] : [
            sample("Sommerlager Beispiel 2027", status: "aktiv", from: "2027-07-17", to: "2027-07-24", role: "lagerleitung"),
            sample("Sommerlager Beispiel 2026", status: "abgeschlossen", from: "2026-07-18", to: "2026-07-25", role: "team"),
        ])
        return model
    }

    private static func sample(_ title: String, status: String, from: String, to: String, role: String) -> CampListEntry {
        let json = """
        {"id":"\(UUID().uuidString)","titel":"\(title)","von":"\(from)","bis":"\(to)","vorbereitungAb":null,"ort":"Lagerhaus Beispielberg",
         "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"rolle":"\(role)"}
        """
        // The sample is a literal, so decoding cannot fail.
        return try! JSONDecoder.api.decode(CampListEntry.self, from: Data(json.utf8))
    }
}
