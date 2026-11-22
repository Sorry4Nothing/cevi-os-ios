import SwiftUI

/// One field in both versions. `differs` marks it with a word, not only with color.
struct CampConflictField: Identifiable, Equatable {
    let label: String
    let mine: String
    let current: String

    var id: String { label }
    var differs: Bool { mine != current }
}

/// U7: someone changed the same row. The person picks which version counts; nothing is lost.
/// «Beide ansehen» (merge by hand) is not part of this screen yet, see `docs/lager.md`.
struct CampConflictView: View {
    let title: String
    let subject: String
    let mineAuthor: String
    let currentAuthor: String
    let fields: [CampConflictField]
    let choose: (CampConflictChoice) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title).font(.title(.title2)).accessibilityAddTraits(.isHeader)
                    Text(subject).font(.headline)
                    Text("Zwei Fassungen.").font(.body)
                    Text("Wähle, welche gilt. Nichts geht verloren.").font(.body).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                .foregroundStyle(Color.ceviOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                version("Deine Fassung", author: mineAuthor) { $0.mine }
                version("Aktuelle Fassung", author: currentAuthor) { $0.current }
                VStack(spacing: Spacing.s1) {
                    Button("Meine behalten") { choose(.keepMine) }.buttonStyle(.ceviPrimary)
                    Button("Aktuelle übernehmen") { choose(.keepCurrent) }.buttonStyle(.ceviText)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .ceviScreenBackground()
        .onAppear { AccessibilityNotification.Announcement(title).post() }
    }

    private func version(_ heading: LocalizedStringKey, author: String, value: @escaping (CampConflictField) -> String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(heading).font(.headline).accessibilityAddTraits(.isHeader)
            Text(author).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            ForEach(fields) { field in
                HStack(alignment: .firstTextBaseline) {
                    Text(field.label).foregroundStyle(Color.ceviOnSurfaceVariant)
                    Spacer(minLength: Spacing.s2)
                    Text(value(field)).fontWeight(field.differs ? .bold : .regular).multilineTextAlignment(.trailing)
                    if field.differs { Text("anders").font(.caption.bold()).foregroundStyle(Color.ceviOnSecondaryContainer)
                        .padding(.horizontal, Spacing.s2).background(Color.ceviSecondaryContainer, in: .capsule) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(field.label): \(value(field))\(field.differs ? ", anders" : "")"))
            }
        }
        .ceviCard()
    }
}

#Preview("U7 Versionskonflikt") {
    CampConflictView(title: "Lea hat diese Aufgabe gerade geändert", subject: "Offerte Lagerhaus einholen",
                     mineAuthor: "Du, eben jetzt", currentAuthor: "Lea, vor 1 Minute",
                     fields: [.init(label: "Frist", mine: "15. März", current: "22. März"),
                              .init(label: "Status", mine: "Läuft", current: "Läuft")]) { _ in }
}
#Preview("U7 Nacht") {
    CampConflictView(title: "Lea hat diese Aufgabe gerade geändert", subject: "Offerte Lagerhaus einholen",
                     mineAuthor: "Du, eben jetzt", currentAuthor: "Lea, vor 1 Minute",
                     fields: [.init(label: "Frist", mine: "15. März", current: "22. März")]) { _ in }
        .preferredColorScheme(.dark)
}
