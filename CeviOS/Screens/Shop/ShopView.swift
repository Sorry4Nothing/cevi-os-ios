import SwiftUI

/// Lädeli: the articles. Built without a design draft (`docs/laedeli.md`). Closed shop: articles show, no button to order.
struct ShopView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: ShopModel
    @State private var orders = MyShopOrdersModel()

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Lädeli")
            .navigationSubtitle("Bestelle bei deiner Abteilung")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { MyShopOrdersView(model: orders) } label: { Label("Meine Bestellungen", systemImage: "list.bullet.rectangle") }
                }
            }
            .task { await model.load(client: appState.client) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Lädeli wird geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .loaded:
            if let catalog = model.catalog { list(catalog) }
        }
    }

    private func list(_ catalog: ShopCatalog) -> some View {
        ScrollView {
            VStack(spacing: Spacing.s3) {
                if !catalog.settings.ordersOpen {
                    InfoBanner(tone: .info, title: String(localized: "Das Lädeli ist geschlossen"), message: nonEmpty(catalog.settings.closedText))
                } else if let note = nonEmpty(catalog.settings.paymentNote) {
                    Text(note).font(.callout).foregroundStyle(Color.ceviOnSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.error { ErrorRow(text: error) }
                if catalog.articles.isEmpty {
                    StateView(symbol: "bag", title: "Noch keine Artikel", message: "Die Abteilung hat im Lädeli noch nichts eingestellt.").frame(minHeight: 320)
                }
                ForEach(catalog.articles) { article in card(article, open: catalog.settings.ordersOpen) }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.load(client: appState.client) }
        .safeAreaInset(edge: .bottom) { if catalog.settings.ordersOpen, model.pieces > 0 { cartBar } }
    }

    private var cartBar: some View {
        NavigationLink { ShopCartView(model: model) } label: {
            Text("Warenkorb, \(ShopRules.chf(model.totalCents))").frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Warenkorb ansehen, \(model.pieces) Stück, \(ShopRules.chf(model.totalCents))"))
        }
        .buttonStyle(.ceviPrimary)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
    }

    private func card(_ article: ShopArticle, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(article.name).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Text(ShopRules.price(article.priceCents)).foregroundStyle(Color.ceviOnSurface)
                if article.hasSizeList {
                    Text("Grössen: \(article.orderableVariants.formatted(.list(type: .and)))").foregroundStyle(Color.ceviOnSurfaceVariant)
                    if !article.unavailableVariants.isEmpty {
                        Text("Nicht zu haben: \(article.unavailableVariants.formatted(.list(type: .and)))").foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                }
                if let note = nonEmpty(article.note) { Text(note).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                let count = model.quantityInCart(article)
                if count > 0 { Label("\(count) im Warenkorb", systemImage: "cart").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSuccessContainer) }
            }
            .accessibilityElement(children: .combine)
            if !article.isAvailable {
                Label("Nicht zu haben", systemImage: "nosign").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
            } else if open {
                if article.hasSizeList {
                    Menu {
                        ForEach(article.orderableVariants, id: \.self) { size in
                            Button(size) { model.add(article, variant: size) }
                        }
                    } label: { Label("Grösse wählen", systemImage: "plus") }
                        .buttonStyle(.ceviPrimary)
                        .accessibilityLabel(Text("\(article.name): Grösse wählen und in den Warenkorb legen"))
                } else {
                    Button("In den Warenkorb", systemImage: "plus") { model.add(article) }
                        .buttonStyle(.ceviPrimary)
                        .accessibilityLabel(Text("\(article.name) in den Warenkorb legen"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }

    private func nonEmpty(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
