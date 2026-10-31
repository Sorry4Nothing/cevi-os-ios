import SwiftUI

/// T03 Willkommen: confirm the privacy statement before the app opens.
struct PrivacyView: View {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    /// Name in the greeting.
    let name: String
    /// First names of the children (parents); empty for leaders.
    let childNames: [String]
    @State private var action = ActionState()
    @State private var isPageOpen = false
    @State private var accepted = false

    var body: some View {
        let url = ServerPage.privacy.url(base: configuration.apiBaseURL)
        FillingScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                Spacer(minLength: Spacing.s8)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Eyebrow("Cevi Stäfa-Hombrechtikon")
                    Text("Willkommen, \(name)!")
                        .font(.title(.display))
                        .foregroundStyle(Color.ceviOnSurface)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    feature("Programme", text: programsText, symbol: "calendar")
                    feature("Zusagen", text: "Mit einem Tipp Ja oder Nein sagen.", symbol: "checkmark")
                    feature("Chat", text: "Nachrichten an die Stufenleitung und in der Gruppe.",
                            symbol: "bubble.left.and.bubble.right")
                }
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Toggle("Ich habe die Datenschutzerklärung gelesen und bin einverstanden.", isOn: $accepted)
                        .toggleStyle(CheckboxToggleStyle())
                    Button("Datenschutzerklärung lesen") { isPageOpen = true }
                        .buttonStyle(.ceviText)
                        .disabled(url == nil)
                    if let error = action.error {
                        ErrorRow(text: error)
                    }
                    Button {
                        Task { await action.perform { try await state.privacyAcknowledged() } }
                    } label: {
                        ProgressLabel(title: "Los geht’s", isRunning: action.isRunning)
                    }
                    .buttonStyle(.ceviPrimary)
                    .disabled(!accepted || action.isRunning)
                    SignOutButton()
                        .buttonStyle(CeviTextButtonStyle(color: .ceviPrimaryText))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: Size.contentMax, alignment: .leading)
            .padding(.horizontal, Spacing.s6)
            .padding(.bottom, Spacing.s4)
        }
        .ceviScreenBackground()
        .fullScreenCover(isPresented: $isPageOpen) {
            if let url { WebPageView(url: url) }
        }
    }

    private var programsText: LocalizedStringKey {
        childNames.isEmpty
            ? "Alle Anlässe deiner Stufe auf einen Blick."
            : "Alle Anlässe von \(childNames.formatted(.list(type: .and))) auf einen Blick."
    }

    private func feature(_ title: LocalizedStringKey, text: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s4) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Color.ceviOnSecondaryContainer)
                .frame(width: Size.avatar, height: Size.avatar)
                .background(Color.ceviSecondaryContainer, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                Text(text).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Willkommen") {
    PrivacyView(name: "Marion", childNames: ["Lena", "Noah"]).environment(AppState())
}

#Preview("Willkommen Nacht") {
    PrivacyView(name: "Marion", childNames: []).environment(AppState()).preferredColorScheme(.dark)
}
