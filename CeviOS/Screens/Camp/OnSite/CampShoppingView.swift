import SwiftUI

/// Root of L28 inside a navigation stack.
struct CampShoppingView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampShoppingModel?

    var body: some View {
        Group { if let model { CampShoppingScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampShoppingModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L28: «Einkaufsliste».
struct CampShoppingScreen: View {
    @Bindable var model: CampShoppingModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsAdd = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Einkaufsliste wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error,
                       notice: model.noticeData(undo: model.lastTicked == nil ? nil : { Task { await model.undo() } }),
                       refresh: { await model.load() }) { content }
        }
        .navigationTitle("Einkaufsliste")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if model.canEdit && model.phase == .loaded { CampMainAction(title: "Artikel hinzufügen") { showsAdd = true } }
        }
        .sheet(isPresented: $showsAdd) { CampShoppingAddSheet(model: model) { showsAdd = false }.presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private var content: some View {
        if let line = model.buyersLine { Text(line).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
        if model.items.isEmpty && !model.onlyMine {
            StateView(symbol: "cart", title: "Die Liste ist leer",
                      message: model.canEdit ? "Füge den ersten Artikel hinzu." : "Hier erscheint, was eingekauft wird.").frame(minHeight: 320)
        } else {
            Toggle("Nur was ich einkaufe", isOn: Binding(get: { model.onlyMine }, set: { value in Task { await model.setOnlyMine(value) } }))
                .frame(minHeight: Size.touchTarget)
                .padding(.horizontal, Spacing.s4)
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
                .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
            if model.items.isEmpty { Text("Du kaufst gerade nichts ein.").foregroundStyle(Color.ceviOnSurfaceVariant).padding(.vertical, Spacing.s4) }
            ForEach(model.groups) { group in
                CampSectionTitle(LocalizedStringKey(group.group.title))
                VStack(spacing: 0) {
                    ForEach(group.rows) { row in
                        rowView(row)
                        if row.id != group.rows.last?.id { Divider().padding(.leading, Spacing.s4 + Size.touchTarget) }
                    }
                }
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
                .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
            }
        }
    }

    private func rowView(_ row: CampShoppingModel.Row) -> some View {
        let spoken = [row.name, row.amount, row.buyer, row.done ? String(localized: "abgehakt") : String(localized: "offen")].compactMap { $0 }.joined(separator: ", ")
        let content = HStack(spacing: Spacing.s3) {
            Image(systemName: row.done ? "checkmark.circle.fill" : "circle").font(.title2)
                .foregroundStyle(row.done ? Color.ceviAccent : Color.ceviOnSurfaceVariant).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(row.name).strikethrough(row.done).foregroundStyle(row.done ? Color.ceviOnSurfaceVariant : Color.ceviOnSurface)
                if let buyer = row.buyer { Text(buyer).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
            }
            Spacer(minLength: Spacing.s2)
            if let amount = row.amount { Text(amount).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurface) }
        }
        .padding(.horizontal, Spacing.s4)
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget + Spacing.s3, alignment: .leading)
        .contentShape(.rect)
        return Group {
            if model.canEdit {
                Button { Task { await model.toggle(row) } } label: { content }.buttonStyle(.plain).accessibilityAddTraits(.isToggle)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }
}

/// «Artikel hinzufügen»: name with suggestions while typing, optional amount and unit.
struct CampShoppingAddSheet: View {
    let model: CampShoppingModel
    let close: () -> Void
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let error = model.error { ErrorRow(text: error) }
                    Text("Artikel").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Artikel", text: $name)
                        .focused($focused)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: Size.field)
                        .submitLabel(.done)
                    suggestionChips
                    HStack(spacing: Spacing.s3) {
                        TextField("Menge", text: $amount).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                        TextField("Einheit", text: $unit).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                    }
                    Button("Hinzufügen") {
                        Task { if await model.add(name: name, amount: amount, unit: unit) { close() } }
                    }
                    .buttonStyle(.ceviPrimary)
                }
                .padding(Spacing.s4)
            }
            .ceviScreenBackground()
            .navigationTitle("Artikel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark", action: close) } }
            .task(id: name) {
                // Debounced: a new letter cancels the call before it goes out.
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.loadSuggestions(for: name)
            }
            .onAppear { focused = true }
        }
    }

    private var suggestionChips: some View {
        let existing = model.existing(matching: name)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(existing, id: \.self) { text in
                Label(text, systemImage: "info.circle").font(.subheadline).foregroundStyle(Color.ceviOnSecondaryContainer)
                    .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
                    .background(Color.ceviSecondaryContainer, in: .capsule)
            }
            ForEach(model.suggestions, id: \.name) { suggestion in
                Button { name = suggestion.name } label: {
                    Text(suggestion.name).font(.subheadline.bold()).padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
                        .foregroundStyle(Color.ceviOnSecondaryContainer).background(Color.ceviSecondaryContainer, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Übernimmt den Namen"))
            }
        }
    }
}
