import SwiftUI

/// Root of L30 inside a navigation stack.
struct CampEmergencyView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampEmergencyModel?

    var body: some View {
        Group { if let model { CampEmergencyScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampEmergencyModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L30: «Notfall». Phone numbers and the route open only through `Link` (the system asks before a call).
struct CampEmergencyScreen: View {
    @Bindable var model: CampEmergencyModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Notfall wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let title = model.staleTitle { staleNote(title) }
                    if let error = model.error { ErrorRow(text: error) }
                    if let name = model.active.camp?.title { Text(name).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
                    contactList
                    CampSectionTitle("Lageradresse")
                    addressCard
                    if !model.infos.isEmpty {
                        CampSectionTitle("Wichtig im Notfall")
                        ForEach(model.infos) { info in
                            CampOnSiteCard {
                                VStack(alignment: .leading, spacing: Spacing.s1) {
                                    Text(info.title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                                    if let text = CampRosterText.trimmed(info.text) { Text(text).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true) }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax).frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
            .ceviScreenBackground()
        }
        .navigationTitle("Notfall")
        .navigationBarTitleDisplayMode(.large)
    }

    private func staleNote(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Label(title, systemImage: "wifi.slash").font(.headline)
            Text("Das ist der zuletzt geladene Stand. Anrufen geht trotzdem.").font(.subheadline)
        }
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var contactList: some View {
        let all = CampEmergencyModel.rescue + model.contacts
        return VStack(spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, contact in
                contactRow(contact)
                if index < all.count - 1 { Divider() }
            }
        }
        .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
        .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
    }

    private func contactRow(_ contact: CampEmergencyContact) -> some View {
        let label = model.contactLabel(contact)
        return HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(label).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                Text(contact.function).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            Spacer(minLength: Spacing.s2)
            if let phone = contact.phone, contact.phoneURL != nil { Text(phone).font(.headline).foregroundStyle(Color.ceviOnSurface).multilineTextAlignment(.trailing) }
            if let url = contact.phoneURL {
                Link(destination: url) {
                    Image(systemName: "phone.fill").foregroundStyle(Color.ceviOnErrorContainer)
                        .frame(width: Size.button, height: Size.button).background(Color.ceviErrorContainer, in: Circle())
                }
                .accessibilityLabel(Text("\(label), \(contact.function), anrufen"))
            } else {
                Text("Keine Nummer").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .padding(Spacing.s4)
        .frame(minHeight: Size.touchTarget + Spacing.s4)
        .accessibilityElement(children: .contain)
    }

    private var addressCard: some View {
        CampOnSiteCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                let lines = [model.address?.place, model.address?.address].compactMap(CampRosterText.trimmed)
                if lines.isEmpty {
                    Text("Die Lageradresse fehlt noch. Frag die Lagerleitung.").foregroundStyle(Color.ceviOnSurfaceVariant)
                } else {
                    Text(lines[0]).font(.headline).foregroundStyle(Color.ceviOnSurface)
                    ForEach(lines.dropFirst(), id: \.self) { Text($0).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                if let route = model.address?.routeURL {
                    Link(destination: route) { Label("Route öffnen", systemImage: "arrow.triangle.turn.up.right.diamond").frame(minHeight: Size.touchTarget) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
