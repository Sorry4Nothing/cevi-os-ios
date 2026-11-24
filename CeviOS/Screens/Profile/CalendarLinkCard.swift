import SwiftUI

/// A6 «Mein Kalender-Link»: subscribe to the own events in the phone or in Outlook. Parents and leaders alike.
struct CalendarLinkCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    let model: CalendarLinkModel
    @Binding var confirmsReplace: Bool
    @Binding var confirmsRevoke: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("Abonniere nur deine Termine in Handy oder Outlook. Der Link gehört nur dir.")
                .foregroundStyle(Color.ceviOnSurface)
            if let error = model.action.error {
                InfoBanner(tone: .error, title: String(localized: "Das hat nicht geklappt"),
                           message: "\(error) \(String(localized: "Dein alter Link gilt noch."))")
            }
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("Link wird geladen"))
            case .failed(let text):
                ErrorRow(text: text)
                Button("Nochmals versuchen") { Task { await model.load(client: state.client) } }.buttonStyle(.ceviText)
            case .loaded(let status):
                loaded(status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.load(client: state.client) }
    }

    @ViewBuilder
    private func loaded(_ status: CalendarLinkStatus) -> some View {
        if status.isActive {
            if let suffix = status.suffix {
                Text("Dein Link ist aktiv und endet auf «\(suffix)».").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            Button { confirmsReplace = true } label: { Label("Link neu erzeugen", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(CeviSecondaryButtonStyle())
                .disabled(model.action.isRunning)
            Text("Der alte Link funktioniert danach nicht mehr.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            Button("Link widerrufen", role: .destructive) { confirmsRevoke = true }
                .buttonStyle(.ceviText)
                .disabled(model.action.isRunning)
        } else {
            Button { Task { await model.create(client: state.client) } } label: { Label("Link erzeugen", systemImage: "link") }
                .buttonStyle(CeviSecondaryButtonStyle())
                .disabled(model.action.isRunning)
        }
    }
}

/// Sheet with the new link and the two confirmations. They belong on the profile screen, not inside a list row.
struct CalendarLinkPresentation: ViewModifier {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    let model: CalendarLinkModel
    @Binding var confirmsReplace: Bool
    @Binding var confirmsRevoke: Bool

    func body(content: Content) -> some View {
        content
        .sheet(isPresented: Binding(get: { model.newLink != nil }, set: { if !$0 { model.newLink = nil } })) {
            if let link = model.newLink { newLinkSheet(link) }
        }
        .confirmationDialog("Link neu erzeugen?", isPresented: $confirmsReplace, titleVisibility: .visible) {
            Button("Link neu erzeugen") { Task { await model.create(client: state.client) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der alte Link funktioniert danach nicht mehr.")
        }
        .confirmationDialog("Link widerrufen?", isPresented: $confirmsRevoke, titleVisibility: .visible) {
            Button("Link widerrufen", role: .destructive) { Task { await model.revoke(client: state.client) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Kalender hört dann auf, Termine abzurufen.")
        }

    }

    private func newLinkSheet(_ link: CalendarLinkNew) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Dein Link ist bereit.").font(.title(.title2)).accessibilityAddTraits(.isHeader)
                Text("Teile ihn mit deinem Kalender oder kopiere ihn. Danach zeigt die App ihn nicht mehr an. Gib ihn niemandem weiter.")
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                if let base = configuration.apiBaseURL, let url = link.url(base: base) {
                    ShareLink(item: url, preview: SharePreview("Mein Kalender-Link")) {
                        Label("Teilen oder kopieren", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.ceviPrimary)
                }
                Spacer()
            }
            .padding(Spacing.s4)
            .ceviScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { model.newLink = nil } }
            }
        }
        .presentationDetents([.medium])
    }
}
