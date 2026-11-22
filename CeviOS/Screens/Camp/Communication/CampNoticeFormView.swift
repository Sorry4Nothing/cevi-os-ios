import SwiftUI

/// L17: «Neue Mitteilung» with recipients, poll, flags and a closing day.
struct CampNoticeFormView: View {
    @State var model: CampNoticeFormModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ActiveCamp.self) private var active

    var body: some View {
        NavigationStack {
            Form {
                if model.saveError != nil || model.inputError != nil { messages }
                Section {
                    TextField("Titel", text: $model.title)
                    TextField("Text", text: $model.text, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    ForEach([CampNoticeRole.leadership, .team, .readOnly], id: \.self) { role in
                        Toggle(CampNoticesModel.roleName(role), isOn: .init(get: { model.roles.contains(role) }, set: { if $0 { model.roles.insert(role) } else { model.roles.remove(role) } }))
                    }
                } header: { Text("Empfänger") } footer: { Text(model.roles.isEmpty ? "Ohne Auswahl sehen alle die Mitteilung." : "Nur die gewählten Gruppen sehen die Mitteilung.") }
                Section {
                    ForEach(model.options.indices, id: \.self) { index in
                        HStack {
                            TextField("Option \(index + 1)", text: $model.options[index])
                            if model.options.count > 2 { Button("Option entfernen", systemImage: "minus.circle") { model.removeOption(at: index) }.labelStyle(.iconOnly) }
                        }
                    }
                    Button("Option hinzufügen", systemImage: "plus") { model.addOption() }.frame(minHeight: Size.touchTarget)
                    Toggle("Mehrere Stimmen erlaubt", isOn: $model.multiple)
                } header: { Text("Umfrage") } footer: { Text("Ohne Optionen gibt es keine Umfrage.") }
                Section {
                    Toggle("Wichtig", isOn: $model.important)
                    Toggle("Anheften", isOn: $model.pinned)
                    Toggle("Sichtbar bis", isOn: .init(get: { model.visibleUntil != nil }, set: { model.visibleUntil = $0 ? model.now() : nil }))
                    if let until = model.visibleUntil {
                        DatePicker("Sichtbar bis", selection: .init(get: { until }, set: { model.visibleUntil = $0 }), displayedComponents: .date)
                            .environment(\.calendar, DateFormats.calendar).environment(\.timeZone, DateFormats.timeZone)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Neue Mitteilung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Veröffentlichen") { Task { if await model.publish() { dismiss() } } }.disabled(model.isSaving) }
            }
            .overlay(alignment: .bottom) { Text(active.title).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant).padding(.bottom, Spacing.s2).allowsHitTesting(false) }
        }
    }

    @ViewBuilder private var messages: some View {
        Section {
            if let input = model.inputError {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Label("Prüfe die Eingabe.", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text(input).font(.subheadline)
                }
                .foregroundStyle(Color.ceviOnErrorContainer).accessibilityElement(children: .combine)
                .task(id: input) { AccessibilityNotification.Announcement(input).post() }
            }
            if let save = model.saveError {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Label("Das hat nicht geklappt", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text("Deine Eingabe ist noch da. Versuche es nochmals.").font(.subheadline)
                    Text(save).font(.footnote)
                    Button("Nochmals versuchen") { Task { if await model.publish() { dismiss() } } }.buttonStyle(.ceviText)
                }
                .foregroundStyle(Color.ceviOnErrorContainer).accessibilityElement(children: .contain)
                .task(id: save) { AccessibilityNotification.Announcement(String(localized: "Das hat nicht geklappt. Deine Eingabe ist noch da.")).post() }
            }
        }
        .listRowBackground(Color.ceviErrorContainer)
    }
}

#if DEBUG
#Preview("L17 Normal") { CampCommsPreview.noticeForm() }
#Preview("L17 Nacht") { CampCommsPreview.noticeForm().preferredColorScheme(.dark) }
#Preview("L17 Eingabefehler") { CampCommsPreview.noticeForm(inputError: "Eine Umfrage braucht mindestens zwei Optionen.") }
#Preview("L17 Aktion läuft") { CampCommsPreview.noticeForm(saving: true) }
#Preview("L17 Fehler beim Speichern") { CampCommsPreview.noticeForm(saveError: "Keine Verbindung zum Server. Bitte später nochmals versuchen.") }
#endif
