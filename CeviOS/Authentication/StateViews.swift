import SwiftUI

/// Full-screen state: SF Symbol in a circle, title, text and up to two actions.
/// Used for empty lists, no connection, not found, errors, no access and an ended session.
struct StateView: View {
    enum Tone { case neutral, error }

    struct Action {
        let title: LocalizedStringKey
        var symbol: String?
        let perform: () -> Void
    }

    let symbol: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    var tone: Tone = .neutral
    var primary: Action?
    var secondary: Action?

    var body: some View {
        FillingScrollView {
            VStack(spacing: Spacing.s3) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    // Decorative and inside a fixed circle; the title carries the meaning.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(tone == .error ? Color.ceviOnErrorContainer : Color.ceviOnSecondaryContainer)
                    .frame(width: Size.stateIcon, height: Size.stateIcon)
                    .background(tone == .error ? Color.ceviErrorContainer : Color.ceviSecondaryContainer, in: Circle())
                    .padding(.bottom, Spacing.s2)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title(.title2))
                    .foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                        .padding(.bottom, Spacing.s3)
                }
                VStack(spacing: Spacing.s1) {
                    if let primary {
                        Button(action: primary.perform) { label(primary) }
                            .buttonStyle(CeviPrimaryButtonStyle(expands: false))
                    }
                    if let secondary {
                        Button(action: secondary.perform) { label(secondary) }
                            .buttonStyle(.ceviText)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s6)
            .frame(maxWidth: Size.contentMax)
        }
        .ceviScreenBackground()
    }

    @ViewBuilder
    private func label(_ action: Action) -> some View {
        if let symbol = action.symbol {
            Label(action.title, systemImage: symbol)
        } else {
            Text(action.title)
        }
    }
}

extension StateView {
    /// ZT3: nothing to show yet.
    static func empty(title: LocalizedStringKey, message: LocalizedStringKey, refresh: @escaping () -> Void) -> StateView {
        StateView(symbol: "calendar", title: title, message: message,
                  primary: Action(title: "Aktualisieren", symbol: "arrow.clockwise", perform: refresh))
    }

    /// ZT4: no connection.
    static func offline(retry: @escaping () -> Void) -> StateView {
        StateView(symbol: "wifi.slash", title: "Keine Verbindung", message: "Prüfe dein Internet und versuche es nochmals.",
                  primary: Action(title: "Nochmals versuchen", symbol: "arrow.clockwise", perform: retry))
    }

    /// ZT5: the item is gone.
    static func notFound(message: LocalizedStringKey, back: Action) -> StateView {
        StateView(symbol: "magnifyingglass", title: "Nicht gefunden", message: message, primary: back)
    }

    /// ZT6: server or unknown error.
    static func failure(retry: @escaping () -> Void, back: Action? = nil) -> StateView {
        StateView(symbol: "exclamationmark.triangle", title: "Etwas ist schiefgelaufen",
                  message: "Das liegt nicht an dir. Versuche es in ein paar Minuten nochmals.", tone: .error,
                  primary: Action(title: "Nochmals versuchen", symbol: "arrow.clockwise", perform: retry), secondary: back)
    }

    /// ZT7: the role does not allow this page.
    static func noAccess(back: Action) -> StateView {
        StateView(symbol: "lock", title: "Kein Zugriff",
                  message: "Diese Seite ist nur für die Stufenleitung. Wenn du denkst, das ist ein Fehler, frag deine Stufenleitung.",
                  primary: back)
    }

    /// ZT8: the server ended the session.
    static func sessionEnded(signIn: @escaping () -> Void) -> StateView {
        StateView(symbol: "clock.badge.exclamationmark", title: "Bitte melde dich neu an",
                  message: "Du warst länger nicht aktiv. Zu deiner Sicherheit haben wir dich abgemeldet.",
                  primary: Action(title: "Anmelden", perform: signIn))
    }
}

extension StateView.Action {
    /// «Zu den Programmen» as the way back from a state.
    static func toPrograms(_ perform: @escaping () -> Void) -> StateView.Action {
        StateView.Action(title: "Zu den Programmen", perform: perform)
    }
}

/// ZT1: launch while the session is checked.
struct StartView: View {
    var body: some View {
        FillingScrollView {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Spacer(minLength: 0)
                Eyebrow("Cevi Stäfa-Hombrechtikon")
                Text("Cevi OS")
                    .font(.title(.display))
                    .foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Spacing.s3) {
                    ProgressView()
                    Text("Wird geladen …")
                        .font(.subheadline)
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                .padding(.top, Spacing.s5)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s6)
            .padding(.bottom, Spacing.s8)
        }
        .ceviScreenBackground()
    }
}

/// ZT2: list content is loading. Shows placeholder cards; VoiceOver hears one label.
struct LoadingView: View {
    let label: LocalizedStringKey

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.s2) {
                ForEach(0..<3, id: \.self) { _ in placeholderCard }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .ceviScreenBackground()
    }

    private var placeholderCard: some View {
        // Never visible as text: `redacted` turns it into bars of the right size for the current text size.
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(verbatim: "Samstag, 14.00")
            Text(verbatim: "Programm im Wald").font(.title(.cardTitle))
            Text(verbatim: "Treffpunkt")
        }
        .foregroundStyle(Color.ceviSurfaceContainerHigh)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }
}

#Preview("Start") { StartView() }
#Preview("Laden") { LoadingView(label: "Programme werden geladen") }
#Preview("Leer") {
    StateView.empty(title: "Noch keine Programme",
                    message: "Sobald die Leitung neue Programme einträgt, siehst du sie hier.") {}
}
#Preview("Offline") { StateView.offline {} }
#Preview("Nicht gefunden") {
    StateView.notFound(message: "Dieses Programm gibt es nicht mehr. Vielleicht wurde es verschoben oder abgesagt.",
                       back: .toPrograms {})
}
#Preview("Fehler") { StateView.failure(retry: {}, back: .toPrograms {}) }
#Preview("Fehler Nacht") {
    StateView.failure(retry: {}, back: .toPrograms {}).preferredColorScheme(.dark)
}
#Preview("Kein Zugriff") { StateView.noAccess(back: .toPrograms {}) }
#Preview("Sitzung beendet") { StateView.sessionEnded {} }
