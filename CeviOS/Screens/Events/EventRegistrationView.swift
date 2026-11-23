import SwiftUI

/// K4 Anlass-Anmeldung. What the account knows is shown as «Aus deinem Konto»; the person only adds extra details.
struct EventRegistrationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var scrolledTo: String?
    @State private var model: EventRegistrationModel
    @State private var confirmsUnregister = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(occasionId: UUID) { _model = State(initialValue: EventRegistrationModel(occasionId: occasionId)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
            .ceviScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            .task { await model.load(client: appState.client) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(model.form.map { "Anmeldung \($0.title)" } ?? "Anmeldung")
                .font(.title(.title1))
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            if let line = model.form?.headerLine, !line.isEmpty {
                Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.bottom, Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Anmeldung wird geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .notFound:
            StateView.notFound(message: "Diesen Anlass gibt es nicht mehr oder du siehst ihn nicht.", back: .toPrograms { dismiss() })
        case .closed:
            closed
        case .ready:
            if let sent = model.sent { result(sent) } else { form }
        }
    }

    private var closed: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Label("Anmeldung geschlossen", systemImage: "lock")
                .font(.title(.title2))
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text("Die Anmeldung ist geschlossen. Frag die Leitung.").foregroundStyle(Color.ceviOnSurfaceVariant)
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                banner.id("banner")
                if let form = model.form, form.participants.count > 1 { participants(form) }
                if let participant = model.participant, !participant.account.isEmpty { account(participant) }
                if let fields = model.form?.fields, !fields.isEmpty { extras(fields) }
                if model.isRegistered {
                    Button("Abmelden", role: .destructive) { confirmsUnregister = true }
                        .buttonStyle(.ceviText)
                        .disabled(model.action.isRunning)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition(id: $scrolledTo, anchor: .top)
        // Sending fails at the bottom of a long form: bring the banner with the reason into view.
        .onChange(of: [model.action.error ?? "", model.fieldErrors.isEmpty ? "" : "x"]) { scrolledTo = nil; Task { scrolledTo = "banner" } }
        .formBar(model.isRegistered ? "Änderung speichern" : "Anmelden", isEnabled: !model.action.isRunning) {
            Task { await model.send(client: appState.client) }
        }
        .confirmationDialog("Wirklich abmelden?", isPresented: $confirmsUnregister, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await model.unregister(client: appState.client) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var banner: some View {
        if !model.fieldErrors.isEmpty {
            InfoBanner(tone: .error, title: String(localized: "Prüfe deine Eingaben."), message: String(localized: "Ein Feld braucht noch eine Angabe."))
        } else if let error = model.action.error {
            InfoBanner(tone: .error, title: String(localized: "Das hat nicht geklappt"),
                       message: "\(error) \(String(localized: "Deine Eingabe ist noch da. Versuche es nochmals."))") {
                Button("Nochmals versuchen") { Task { await model.send(client: appState.client) } }.buttonStyle(.ceviText)
            }
        }
    }

    private func participants(_ form: EventRegistrationForm) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            FieldLabel(form.registrationFor == .child ? "Für welches Kind?" : "Für wen?").accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: Spacing.s2) {
                ForEach(Array(form.participants.enumerated()), id: \.offset) { index, person in
                    SelectableChip(title: person.name, isSelected: index == model.participantIndex) { model.selectParticipant(index) }
                }
            }
        }
    }

    private func account(_ participant: EventParticipant) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            FieldLabel("Aus deinem Konto").accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(participant.account.enumerated()), id: \.element.id) { index, value in
                    if index > 0 { Divider() }
                    sideBySide {
                        Text(value.label).foregroundStyle(Color.ceviOnSurfaceVariant)
                        Spacer(minLength: Spacing.s3)
                        Text(value.value).multilineTextAlignment(.trailing)
                    }
                    .font(.body)
                    .padding(Spacing.s3)
                    .frame(minHeight: Size.touchTarget)
                    .accessibilityElement(children: .combine)
                }
            }
            .foregroundStyle(Color.ceviOnSurface)
            .background(Color.ceviSurface, in: Radius.shape(Radius.md))
            .overlay { Radius.shape(Radius.md).strokeBorder(Color.ceviOutline, lineWidth: Size.border) }
            Text("Stimmt etwas nicht? Ändere es im Profil.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
    }

    private func extras(_ fields: [EventField]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            FieldLabel("Zusätzliche Angaben").accessibilityAddTraits(.isHeader)
            ForEach(fields.filter { $0.kind != .unknown }) { field in
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    control(field)
                    if let text = model.fieldErrors[field.key] { FieldError(text: text) }
                }
            }
            if model.hasTextField {
                Label("Bitte keine Gesundheitsdaten eintragen.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
    }

    @ViewBuilder
    private func control(_ field: EventField) -> some View {
        let label = field.isRequired ? field.label : "\(field.label) \(String(localized: "(optional)"))"
        switch field.kind {
        case .yesNo:
            sideBySide {
                Text(label).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.s3)
                yesNo(field, label)
            }
        case .choice:
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color.ceviOnSurfaceVariant)
                FlowLayout(spacing: Spacing.s2) {
                    ForEach(field.options, id: \.self) { option in
                        SelectableChip(title: option, isSelected: model.answers[field.key] == .text(option)) {
                            model.set(.text(option), for: field)
                        }
                    }
                }
            }
        case .text, .unknown:
            EventTextField(label: LocalizedStringKey(label), accessibility: label, text: Binding(
                get: { if case .text(let text)? = model.answers[field.key] { text } else { "" } },
                set: { model.set(.text($0), for: field) }
            ), multiline: true)
        }
    }

    /// Next to each other, stacked at accessibility text sizes.
    private func sideBySide<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s2))
            : AnyLayout(HStackLayout(spacing: Spacing.s2))
        return layout { content() }
    }

    private func yesNo(_ field: EventField, _ label: String) -> some View {
        let selected: Answer? = switch model.answers[field.key] {
        case .bool(true)?: .yes
        case .bool(false)?: .no
        default: nil
        }
        return AnswerButtons(name: label, selected: selected, disabled: false) { answer in
            model.set(.bool(answer == .yes), for: field)
        }
    }

    private func result(_ sent: EventRegistrationModel.Sent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                InfoBanner(tone: .success, title: String(localized: "Angemeldet."),
                           message: model.form?.deadline.map { String(localized: "Abmelden geht bis \(ProgramFormat.shortDate($0)).") }) {
                    if sent.canUndo {
                        Button("Rückgängig") { Task { await model.unregister(client: appState.client) } }
                            .buttonStyle(.ceviText)
                            .disabled(model.action.isRunning)
                    }
                }
                if let error = model.action.error { ErrorRow(text: error) }
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.form?.title ?? "").font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                        Spacer(minLength: Spacing.s2)
                        Label("Angemeldet", systemImage: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ceviOnSuccessContainer)
                            .padding(.horizontal, Spacing.s3)
                            .padding(.vertical, Spacing.s1)
                            .background(Color.ceviSuccessContainer, in: Capsule())
                    }
                    Text(sent.participantName).foregroundStyle(Color.ceviOnSurfaceVariant)
                    ForEach(sent.rows, id: \.self) { row in Text(row).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .ceviCard()
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .resultBar("Zu den Programmen") { dismiss() }
    }
}
