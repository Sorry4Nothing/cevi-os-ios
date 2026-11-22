import SwiftUI

/// Root of L34 inside a navigation stack.
struct CampAddressBookView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampAddressBookModel?

    var body: some View {
        Group { if let model { CampAddressBookScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampAddressBookModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L34: «Adressbuch», camp leadership only. Phone and email open through `Link`; nothing is shown outside the screen.
struct CampAddressBookScreen: View {
    @Bindable var model: CampAddressBookModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsAdd = false

    var body: some View {
        Group {
            if model.isLocked {
                StateView(symbol: "lock", title: "Kein Zugriff", message: "Das Adressbuch sieht nur die Lagerleitung. Wende dich an die Lagerleitung.",
                          primary: .init(title: "Zurück") { dismiss() })
            } else {
                CampPhaseView(phase: model.phase, loading: "Adressbuch wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
                    CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
                }
            }
        }
        .navigationTitle("Adressbuch")
        .navigationBarTitleDisplayMode(.large)
        .modifier(SearchIfAllowed(allowed: !model.isLocked, text: $model.query))
        .onChange(of: model.query) { model.reloadSoon() }
        .safeAreaInset(edge: .bottom) {
            if model.storage.editsAddressBook && model.phase == .loaded { CampMainAction(title: "Kontakt") { showsAdd = true } }
        }
        .sheet(isPresented: $showsAdd) { CampContactAddSheet(model: model) { showsAdd = false }.presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private var content: some View {
        Label("Nur Lagerleitung", systemImage: "lock").font(.subheadline.bold())
            .foregroundStyle(Color.ceviOnSecondaryContainer)
            .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget / 1.5)
            .background(Color.ceviSecondaryContainer, in: .capsule)
        if model.contacts.isEmpty {
            StateView(symbol: "person.crop.circle", title: "Keine Kontakte",
                      message: model.storage.editsAddressBook ? "Füge den ersten Kontakt hinzu." : "Hier erscheinen die Kontakte des Lagers.").frame(minHeight: 320)
        }
        ForEach(model.contacts) { card($0) }
        if !model.contacts.isEmpty {
            Label("Zum Aufräumen nach dem Lager erinnern wir dich.", systemImage: "info.circle").font(.headline)
                .foregroundStyle(Color.ceviOnSecondaryContainer)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.s4)
                .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        }
    }

    private func card(_ contact: CampContact) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            CampOnSiteCard {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(contact.name).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: Spacing.s2)
                        if let group = CampRosterText.trimmed(contact.group) { CampCountChip(text: group) }
                    }
                    if let function = CampRosterText.trimmed(contact.function) { Text(function).foregroundStyle(Color.ceviOnSurfaceVariant) }
                    if let note = CampRosterText.trimmed(contact.note) { Text(note).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true) }
                    HStack(spacing: Spacing.s2) {
                        if let url = CampStorageText.phoneURL(contact.phone) { CampContactLinkButton(symbol: "phone", label: String(localized: "\(contact.name) anrufen"), url: url) }
                        if let url = CampStorageText.mailURL(contact.email) { CampContactLinkButton(symbol: "envelope", label: String(localized: "\(contact.name) eine E-Mail schreiben"), url: url) }
                    }
                    if let text = CampStorageText.cleanUp(contact) { Text(text).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
            }
            if model.storage.editsAddressBook {
                Toggle("Fürs nächste Lager behalten", isOn: Binding(get: { contact.keep }, set: { keep in Task { await model.setKeep(contact, keep) } }))
                    .tint(Color.ceviAccent)
                    .frame(minHeight: Size.touchTarget).padding(.horizontal, Spacing.s4)
                    .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
                    .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
                    .accessibilityHint(Text("Nimmt \(contact.name) aus dem Aufräumen nach dem Lager"))
            }
        }
    }
}

/// The search field only for those who may read the address book.
private struct SearchIfAllowed: ViewModifier {
    let allowed: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if allowed { content.searchable(text: $text, prompt: "Kontakte durchsuchen") } else { content }
    }
}

/// «Neuer Kontakt»: name, phone and email.
struct CampContactAddSheet: View {
    let model: CampAddressBookModel
    let close: () -> Void
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let error = model.error { ErrorRow(text: error) }
                    Text("Name").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(minHeight: Size.field).textContentType(.name)
                    Text("Telefon").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Telefon", text: $phone).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                    Text("E-Mail").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("E-Mail", text: $email).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Kontakt sichern") { Task { if await model.add(name: name, phone: phone, email: email) { close() } } }
                        .buttonStyle(.ceviPrimary)
                }
                .padding(Spacing.s4)
            }
            .ceviScreenBackground()
            .navigationTitle("Neuer Kontakt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark", action: close) } }
        }
    }
}
