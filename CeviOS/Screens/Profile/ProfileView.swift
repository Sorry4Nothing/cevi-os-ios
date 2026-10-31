import PhotosUI
import SwiftUI

/// T10 Profil (with T11 Datenschutz and T12 Abmelden): own data, app settings and sign-out.
struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(AppLock.self) private var lock
    @Environment(\.appConfiguration) private var configuration
    let profile: Profile

    @State private var action = ActionState()
    /// Toggle values that were changed here and are not yet confirmed by a reloaded profile.
    @State private var pending: [String: Bool] = [:]
    @State private var parentsLock = true
    @State private var phone = ""
    @State private var isPickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var page: ServerPage?
    @State private var isConfirmingSignOutEverywhere = false

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                if let error = action.error {
                    Section { ErrorRow(text: error) }
                }

                Section {
                    toggle("Mitteilungen zum Chat", key: "chat", value: profile.pushChat) { ProfilePatch(pushChat: $0) }
                    toggle("Mitteilungen zu Programmen", key: "programs", value: profile.pushPrograms) {
                        ProfilePatch(pushPrograms: $0)
                    }
                    if profile.isLeader, let registrations = profile.pushRegistrations {
                        toggle("Mitteilungen zu Anmeldungen", key: "registrations", value: registrations) {
                            ProfilePatch(pushRegistrations: $0)
                        }
                    }
                } header: {
                    sectionHeader("Benachrichtigungen")
                }

                Section {
                    // Leaders cannot switch the lock off, so the row is hidden for them.
                    if !profile.isLeader {
                        Toggle(isOn: $parentsLock) {
                            row("Mit Face ID entsperren", symbol: "faceid")
                        }
                        .tint(Color.ceviSwitchOn)
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        row("Datenschutz", symbol: "hand.raised")
                    }
                    Button { page = .support } label: { row("Support", symbol: "questionmark.circle") }
                        .accessibilityAddTraits(.isLink)
                    Button { page = .deleteAccount } label: { row("Konto löschen", symbol: "person.crop.circle.badge.xmark") }
                        .accessibilityAddTraits(.isLink)
                } header: {
                    sectionHeader("App")
                } footer: {
                    if !profile.isLeader {
                        Text("Mit Face ID öffnet sich die App nur für dich. Ohne Face ID fragt sie nach deinem Gerätecode.")
                    }
                }

                if profile.isUnitLeader {
                    phoneSection
                }

                Section {
                    SignOutButton()
                        .foregroundStyle(Color.ceviPrimaryText)
                    Button("Überall abmelden") { isConfirmingSignOutEverywhere = true }
                        .foregroundStyle(Color.ceviAccent)
                } header: {
                    sectionHeader("Konto")
                }
            }
            .listSectionSpacing(Spacing.s3)
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Profil")
            .refreshable { await state.reloadProfile() }
        }
        .onAppear {
            parentsLock = lock.parentsLockEnabled
            phone = profile.phone ?? ""
        }
        .onChange(of: parentsLock) { _, new in lock.parentsLockEnabled = new }
        .onChange(of: profile) { pending = [:] }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await upload(item) }
        }
        .fullScreenCover(item: $page) { page in
            if let url = page.url(base: configuration.apiBaseURL) { WebPageView(url: url) }
        }
        .alert("Überall abmelden?", isPresented: $isConfirmingSignOutEverywhere) {
            Button("Abbrechen", role: .cancel) {}
            Button("Überall abmelden", role: .destructive) {
                Task { await state.signOut(everywhere: true) }
            }
        } message: {
            Text("Du wirst auf allen Geräten abgemeldet. Danach brauchst du wieder Benutzername und Passwort.")
        }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s4) { avatarMenu; identity }
            VStack(alignment: .leading, spacing: Spacing.s3) { avatarMenu; identity }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s2)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(profile.ceviName.map { "\(profile.name) (\($0))" } ?? profile.name)
                .font(.title(.title2))
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            ForEach(roleLines, id: \.self) { line in
                Text(line).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            if let username = profile.username {
                Text(username)
                    .font(.subheadline)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                    .accessibilityLabel(Text("Benutzername \(username)"))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var avatarMenu: some View {
        Menu {
            Button("Bild auswählen", systemImage: "photo") { isPickingPhoto = true }
            if profile.imageURL != nil {
                Button("Bild entfernen", systemImage: "trash", role: .destructive) {
                    Task { await deleteImage() }
                }
            }
        } label: {
            ProfileAvatar(path: profile.imageURL, initials: initials)
                .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
        }
        .disabled(action.isRunning)
        .accessibilityLabel(Text("Profilbild ändern"))
    }

    private var initials: String {
        String(profile.name.split(separator: " ").prefix(2).compactMap(\.first))
    }

    private var roleLines: [String] {
        var lines: [String] = []
        if !profile.children.isEmpty {
            let names = profile.children.map(\.firstName).formatted(.list(type: .and))
            lines.append(String(localized: "Elternteil · \(names)"))
        }
        for role in profile.roles {
            let unit = profile.units.first { $0.id == role.unitId }?.name ?? ""
            lines.append(role.type == .unitLeader
                ? String(localized: "Stufenleitung · \(unit)")
                : String(localized: "Leitung · \(unit)"))
        }
        if profile.admin { lines.append(String(localized: "Administration")) }
        return lines
    }

    // MARK: Rows

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label {
            Text(title).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.ceviSecondary)
        }
        .frame(minHeight: Size.touchTarget)
    }

    private func toggle(
        _ title: LocalizedStringKey, key: String, value: Bool, patch: @escaping (Bool) -> ProfilePatch
    ) -> some View {
        Toggle(isOn: Binding(
            get: { pending[key] ?? value },
            set: { new in
                pending[key] = new
                Task {
                    await action.perform { try await requireClient().updateProfile(patch(new)) }
                    if action.error != nil { pending[key] = nil } else { await state.reloadProfile() }
                }
            }
        )) {
            row(title, symbol: "bell")
        }
        .tint(Color.ceviSwitchOn)
        .disabled(action.isRunning)
    }

    private var phoneSection: some View {
        Section {
            TextField("Telefonnummer", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .frame(minHeight: Size.touchTarget)
            if PhoneInput(phone) == .invalid {
                Label("Nur Ziffern, + ( ) / . - und Leerzeichen, 6 bis 30 Zeichen.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnErrorContainer)
            }
            Button("Nummer speichern") {
                Task { await savePhone() }
            }
            .disabled(PhoneInput(phone) == .invalid || phone.trimmingCharacters(in: .whitespaces) == (profile.phone ?? "")
                || action.isRunning)
        } header: {
            sectionHeader("Telefon für Eltern")
        } footer: {
            Text("Diese Nummer sehen alle Eltern der Stufe, und sie können sie speichern. Leer lassen entfernt sie.")
        }
    }

    // MARK: Actions

    private func requireClient() throws -> APIClient {
        guard let client = state.client else { throw APIError.network }
        return client
    }

    private func savePhone() async {
        let value: String?
        switch PhoneInput(phone) {
        case .remove: value = nil
        case .number(let number): value = number
        case .invalid: return
        }
        await action.perform { try await requireClient().updateProfile(ProfilePatch(phone: .some(value))) }
        guard action.error == nil else { return }
        AccessibilityNotification.Announcement(String(localized: "Nummer gespeichert")).post()
        await state.reloadProfile()
    }

    private func upload(_ item: PhotosPickerItem) async {
        await action.perform(message: imageMessage) {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = ProfileImage.jpeg(from: data)
            else { throw APIError(kind: .unsupportedMediaType, status: nil, code: nil, message: nil) }
            try await requireClient().uploadProfileImage(jpeg)
        }
        if action.error == nil { await state.reloadProfile() }
    }

    private func deleteImage() async {
        await action.perform { try await requireClient().deleteProfileImage() }
        if action.error == nil { await state.reloadProfile() }
    }

    private func imageMessage(_ error: APIError) -> String {
        switch error.kind {
        case .payloadTooLarge: String(localized: "Das Bild ist zu gross.")
        case .unsupportedMediaType: String(localized: "Dieses Bild kann die App nicht verwenden. Bitte ein anderes wählen.")
        case .rateLimited: String(localized: "Zu viele Bilder in kurzer Zeit. Bitte später nochmals versuchen.")
        default: error.displayText
        }
    }
}

extension ServerPage: Identifiable {
    var id: String { rawValue }
}

#Preview("Profil") {
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111","name":"Marion Keller","ceviName":null,"benutzername":"m.keller",
     "mussPasswortAendern":false,"datenschutzGelesenAm":"2026-10-01T10:00:00.000Z","telefon":null,"bildUrl":null,
     "pushChat":true,"pushProgramme":true,"admin":false,"zweiterFaktor":false,"rollen":[],"stufen":[],
     "kinder":[{"id":"22222222-2222-2222-2222-222222222222","vorname":"Lena","nachname":"Keller","stufeId":"33333333-3333-3333-3333-333333333333"},
               {"id":"44444444-4444-4444-4444-444444444444","vorname":"Noah","nachname":"Keller","stufeId":"33333333-3333-3333-3333-333333333333"}]}
    """
    // swiftlint:disable:next force_try
    let profile = try! JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
    ProfileView(profile: profile)
        .environment(AppState())
        .environment(AppLock())
}
