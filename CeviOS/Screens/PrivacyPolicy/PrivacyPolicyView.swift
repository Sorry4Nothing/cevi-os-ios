import SwiftUI

/// T11 Datenschutz: short version of the privacy statement inside the app.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            section("Was wir speichern", bullets: [
                "Deinen Namen, Benutzernamen und deine Rolle",
                "Bei Eltern: die Namen eurer Kinder und ihre Stufe",
                "Deine Zusagen zu Programmen",
                "Deine Chat-Nachrichten und dein Profilbild",
            ])
            section("Wer was sieht", text: "Programme sehen alle aus der Stufe. Zusagen sieht die Leitung. Nachrichten an die Stufenleitung lesen alle Stufenleitenden dieser Stufe.")
            section("Was wir nicht machen", bullets: [
                "Keine Werbung und keine Tracker",
                "Keine Weitergabe an andere",
                "Keine Nachrichten oder Namen in Mitteilungen",
            ])
            Section {
                card("Löschen") {
                    paragraph("Dein Konto löscht die Abteilung. Schreib dafür an die Abteilungsleitung.")
                }
            } footer: {
                Text("Stand: 1. November 2026 · Cevi Stäfa-Hombrechtikon")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .listSectionSpacing(Spacing.s3)
        .scrollContentBackground(.hidden)
        .ceviScreenBackground()
        .navigationTitle("Datenschutz")
        .navigationSubtitle("Cevi Stäfa-Hombrechtikon")
    }

    private func section(_ title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        Section { card(title) { paragraph(text) } }
    }

    private func section(_ title: LocalizedStringKey, bullets: [LocalizedStringKey]) -> some View {
        Section {
            card(title) {
                ForEach(bullets.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        Text(verbatim: "•").accessibilityHidden(true)
                        Text(bullets[index])
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                }
            }
        }
    }

    private func card(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.vertical, Spacing.s1)
        .listRowBackground(Color.ceviSurfaceContainerLow)
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
    }
}

#Preview("Datenschutz") {
    NavigationStack { PrivacyPolicyView() }
}
