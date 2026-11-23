import SwiftUI

/// A7 Benachrichtigungen: one switch per kind with one sentence.
struct NotificationsView: View {
    @Environment(AppState.self) private var state
    @Environment(CampListModel.self) private var campList: CampListModel?
    @Environment(\.openURL) private var openURL
    @State private var model = NotificationsModel()
    @State private var profileAction = ActionState()
    /// Profile switches changed here and not yet confirmed by a reloaded profile.
    @State private var pending: [String: Bool] = [:]

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Benachrichtigungen")
            .navigationSubtitle("Was dir die App meldet")
            .navigationBarTitleDisplayMode(.large)
            .toolbarVisibility(.hidden, for: .tabBar)
            .task { await model.load(client: state.client) }
            .onChange(of: state.profile) { pending = [:] }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Einstellungen werden geladen")
        case .failed:
            StateView.failure(retry: { Task { await model.load(client: state.client) } })
        case .loaded:
            if model.systemBlocked { blocked } else { list }
        }
    }

    private var blocked: some View {
        StateView(symbol: "bell.slash", title: "Mitteilungen sind ausgeschaltet",
                  message: "Dein iPhone blockiert Mitteilungen von Cevi OS. Erlaube sie in den Einstellungen, dann kannst du hier wählen, was du bekommst.",
                  primary: .init(title: "In den Einstellungen erlauben") {
                      if let url = URL(string: "app-settings:") { openURL(url) }
                  })
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if let error = model.action.error ?? profileAction.error { ErrorRow(text: error) }
                if let profile = state.profile { appRows(profile) }
                if campList?.showsSwitcher == true, !model.visibleGroups.isEmpty { campRows }
                Text("Mitteilungen zeigen nie Nachrichtentext oder Namen von Kindern.")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
    }

    private func appRows(_ profile: Profile) -> some View {
        card {
            row("Chat", detail: "Wenn dir jemand schreibt.", isOn: binding("chat", profile.pushChat) { ProfilePatch(pushChat: $0) })
            Divider()
            row("Programme und Erinnerungen", detail: "Wenn ein Programm ändert oder bald stattfindet.",
                isOn: binding("programs", profile.pushPrograms) { ProfilePatch(pushPrograms: $0) })
            if let registrations = profile.pushRegistrations {
                Divider()
                row("Anmeldungen", detail: "Wenn sich jemand zu einem Programm an- oder abmeldet.",
                    isOn: binding("registrations", registrations) { ProfilePatch(pushRegistrations: $0) })
            }
        }
    }

    private var campRows: some View {
        card {
            ForEach(Array(model.visibleGroups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { Divider() }
                row(group.title, detail: group.detail, isOn: Binding(
                    get: { model.isOn(group) },
                    set: { new in Task { await model.set(group, on: new, client: state.client) } }
                ))
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color.ceviSurface, in: Radius.shape(Radius.md))
            .overlay { Radius.shape(Radius.md).strokeBorder(Color.ceviOutlineVariant, lineWidth: Size.border) }
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: isOn) { Text(title).font(.body).foregroundStyle(Color.ceviOnSurface) }
                .padding(.top, Spacing.s2)
                .padding(.bottom, Spacing.s1)
                .frame(minHeight: Size.touchTarget)
                .contentShape(Rectangle())
                .accessibilityHint(Text(detail))
            // The sentence is the hint of the switch; read twice it would only repeat.
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .tint(Color.ceviSwitchOn)
        .padding(.horizontal, Spacing.s4)
        .padding(.bottom, Spacing.s2)
        .disabled(model.action.isRunning || profileAction.isRunning)
    }

    private func binding(_ key: String, _ value: Bool, patch: @escaping (Bool) -> ProfilePatch) -> Binding<Bool> {
        Binding(
            get: { pending[key] ?? value },
            set: { new in
                pending[key] = new
                Task {
                    await profileAction.perform {
                        guard let client = state.client else { throw APIError.network }
                        try await client.updateProfile(patch(new))
                    }
                    if profileAction.error != nil { pending[key] = nil } else { await state.reloadProfile() }
                }
            }
        )
    }
}
