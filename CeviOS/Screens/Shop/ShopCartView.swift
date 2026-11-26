import SwiftUI

/// Lädeli: the cart, the way of handover, the sum and the order button. After ordering it shows the message of the department.
struct ShopCartView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let model: ShopModel

    var body: some View {
        Group {
            if let text = model.placedText { placed(text) } else if model.entries.isEmpty { empty } else { cart }
        }
        .ceviScreenBackground()
        .navigationTitle("Warenkorb")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(model.isOrdering)
    }

    private var empty: some View {
        StateView(symbol: "cart", title: "Der Warenkorb ist leer", message: "Leg im Lädeli etwas hinein.",
                  primary: .init(title: "Zum Lädeli", perform: { dismiss() }))
    }

    private func placed(_ text: String) -> some View {
        StateView(symbol: "checkmark.circle", title: "Bestellung eingegangen", message: LocalizedStringKey(text),
                  primary: .init(title: "Fertig") { model.finishOrder(); dismiss() })
    }

    private var cart: some View {
        ScrollView {
            VStack(spacing: Spacing.s3) {
                ForEach(model.entries) { entry in line(entry) }
                summary
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func line(_ entry: ShopModel.Entry) -> some View {
        let title = entry.line.variant.map { "\(entry.article.name), \($0)" } ?? entry.article.name
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Text("\(entry.line.quantity) × \(ShopRules.price(entry.article.priceCents)) = \(ShopRules.price(entry.totalCents))")
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            .accessibilityElement(children: .combine)
            Stepper(value: Binding(get: { entry.line.quantity }, set: { model.setQuantity(entry.id, $0) }), in: 1...(model.catalog?.limits.quantity ?? 1)) {
                Text("Menge: \(entry.line.quantity)")
            }
            .accessibilityLabel(Text("Menge von \(title)"))
            .accessibilityValue(Text("\(entry.line.quantity)"))
            Button("Entfernen", systemImage: "trash") { model.remove(entry.id) }
                .buttonStyle(.ceviText)
                .accessibilityLabel(Text("\(title) entfernen"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }

    @ViewBuilder
    private var summary: some View {
        if let catalog = model.catalog {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack {
                    Text("Summe").font(.headline)
                    Spacer(minLength: Spacing.s2)
                    Text(ShopRules.chf(model.totalCents)).font(.headline)
                }
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityElement(children: .combine)

                Picker("Übergabe", selection: Bindable(model).handover) {
                    if catalog.handovers.count != 1 { Text("Bitte wählen").tag(String?.none) }
                    ForEach(catalog.handovers, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Size.touchTarget)

                if !catalog.settings.handoverNote.isEmpty { note(catalog.settings.handoverNote) }
                if !catalog.settings.paymentMethod.isEmpty { note("Bezahlung: \(catalog.settings.paymentMethod)") }
                if !catalog.settings.paymentNote.isEmpty { note(catalog.settings.paymentNote) }
                if catalog.settings.minimumCents > 0 { note("Mindestbestellung: \(ShopRules.chf(catalog.settings.minimumCents))") }
                ForEach(catalog.settings.terms.split(whereSeparator: \.isNewline).map(String.init), id: \.self) { note($0) }

                if let error = model.error { ErrorRow(text: error) }
                Button { Task { await model.order(client: appState.client) } } label: {
                    ProgressLabel(title: "Bestellen", isRunning: model.isOrdering).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ceviPrimary)
                .disabled(model.isOrdering)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ceviCard()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
    }
}
