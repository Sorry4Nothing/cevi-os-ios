import SwiftUI

/// L8 quick entry with L10 duplicate hint. Writes `@Person`, a date in words and `#Ressort` like a message; the app suggests,
/// the person confirms.
struct CampQuickEntryView: View {
    @State var model: CampQuickEntryModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    if let error = model.error { failureCard(error) }
                    TextField("Offerte @Jonas bis 15.3. #Logistik", text: $model.text, axis: .vertical)
                        .lineLimit(2...6).focused($focused).padding(Spacing.s4)
                        .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.sm))
                        .overlay(Radius.shape(Radius.sm).stroke(focused ? Color.ceviFocus : Color.ceviOutline, lineWidth: focused ? Size.focusBorder : Size.border))
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { line, suggestion in suggestionView(line, suggestion) }
                    if let duplicate = model.duplicate { duplicateCard(duplicate) } else {
                        Text("Mehrere Zeilen einfügen ergibt mehrere Aufgaben.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                    if model.duplicate == nil {
                        Button("Erfassen") { Task { await model.submit() } }.buttonStyle(.ceviPrimary).disabled(!model.canSubmit)
                    }
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax).frame(maxWidth: .infinity)
            }
            .ceviScreenBackground()
            .navigationTitle("Schnell erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark") { dismiss() } } }
            .onAppear { focused = true }
            .onChange(of: model.isDone) { _, done in if done { dismiss() } }
            // Suggestions follow the typing after a short pause; nothing is saved by this.
            .task(id: model.text) {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await model.suggest()
            }
        }
        .presentationDetents([.large])
    }

    private func failureCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Label("Das hat nicht geklappt", systemImage: "exclamationmark.triangle.fill").font(.headline)
            Text(text).font(.subheadline)
            Text("Deine Eingabe ist noch da. Versuche es nochmals.").font(.subheadline)
        }
        .foregroundStyle(Color.ceviOnErrorContainer).frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4).background(Color.ceviErrorContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
    }

    private func suggestionView(_ line: Int, _ suggestion: CampTaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Erkannt, zum Ändern antippen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            Text(suggestion.title.isEmpty ? String(localized: "Ohne Titel") : suggestion.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
            HStack(spacing: Spacing.s2) { chips(line, suggestion) }.fixedSize(horizontal: false, vertical: true)
            if let hint = model.hint(for: suggestion) {
                Label(hint, systemImage: "questionmark.circle").font(.subheadline).foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.updatesFrequently)
                if let candidates = suggestion.person?.candidates, suggestion.person?.status != .found, model.personChoice[line] == nil {
                    ForEach(candidates) { candidate in
                        if let name = CampTaskText.personName(name: candidate.name, ceviName: candidate.ceviName) {
                            Button("@\(name) übernehmen") { model.choosePerson(candidate.id, line: line) }.buttonStyle(.ceviText)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }

    @ViewBuilder private func chips(_ line: Int, _ suggestion: CampTaskSuggestion) -> some View {
        if let person = suggestion.person {
            let chosen = model.personChoice[line].flatMap { id in person.candidates.first { $0.id == id } }
            let match = chosen ?? (person.status == .found ? person.candidates.first : nil)
            if let match, let name = CampTaskText.personName(name: match.name, ceviName: match.ceviName) {
                chip(name, symbol: "person")
            }
        }
        if let deadline = suggestion.deadline { chip(CampTaskText.day(deadline.date), symbol: "calendar") }
        if let portfolio = suggestion.portfolio {
            ForEach(portfolio.candidates) { candidate in
                let confirmed = model.portfolioChoice[line] == candidate.id
                Button { model.togglePortfolio(candidate.id, line: line) } label: {
                    Label(confirmed ? candidate.name : String(localized: "\(candidate.name)? Übernehmen"), systemImage: confirmed ? "checkmark" : "folder")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
                        .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
                        .background(confirmed ? Color.ceviSecondaryContainer : Color.clear, in: .capsule)
                        .overlay(Capsule().stroke(Color.ceviOutline, lineWidth: Size.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(confirmed ? "Ressort \(candidate.name) übernommen" : "Ressort \(candidate.name) übernehmen"))
                .accessibilityAddTraits(confirmed ? .isSelected : [])
            }
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSecondaryContainer)
            .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget).background(Color.ceviSecondaryContainer, in: .capsule)
    }

    /// L10.
    private func duplicateCard(_ duplicate: CampQuickEntryModel.Duplicate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Es gibt schon eine ähnliche Aufgabe: «\(duplicate.existing.title)».", systemImage: "doc.on.doc").font(.headline)
            Text("Zusammenführen?").font(.body)
            Button("Zusammenführen") { Task { await model.merge() } }.buttonStyle(.ceviPrimary)
            Button("Beide behalten") { Task { await model.keepBoth() } }.buttonStyle(.ceviText)
        }
        .foregroundStyle(Color.ceviOnSurface).frame(maxWidth: .infinity, alignment: .leading).ceviCard()
        .accessibilityElement(children: .contain).accessibilityAddTraits(.updatesFrequently)
        .disabled(model.isSaving)
    }
}

#if DEBUG
#Preview("L8 Normal") { CampPreview.quickEntry() }
#Preview("L8 Nacht") { CampPreview.quickEntry().preferredColorScheme(.dark) }
#Preview("L8 Aktion läuft") { CampPreview.quickEntry(saving: true) }
#Preview("L8 Eingabefehler") { CampPreview.quickEntry(text: "Offerte @Jona bis 15.3.", suggestions: CampPreview.unknownPerson) }
#Preview("L8 Fehler beim Speichern") { CampPreview.quickEntry(error: "Der Server antwortet nicht.") }
#Preview("L10 Duplikat-Hinweis") { CampPreview.quickEntry(duplicate: true) }
#Preview("L10 Duplikat-Hinweis Nacht") { CampPreview.quickEntry(duplicate: true).preferredColorScheme(.dark) }
#endif
