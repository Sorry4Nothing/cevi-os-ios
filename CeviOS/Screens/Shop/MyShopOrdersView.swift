import SwiftUI

/// Lädeli: Meine Bestellungen. An open order has «Stornieren» (with a question first).
struct MyShopOrdersView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: MyShopOrdersModel
    @State private var cancelling: ShopOrder?

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Meine Bestellungen")
            .navigationSubtitle("Deine Bestellungen im Lädeli")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.load(client: appState.client) }
            .confirmationDialog("Bestellung stornieren?", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
                Button("Stornieren", role: .destructive) {
                    if let order = cancelling { Task { await model.cancel(order, client: appState.client) } }
                }
                Button("Behalten", role: .cancel) {}
            } message: {
                Text("Die Bestellung wird nicht mehr vorbereitet.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Bestellungen werden geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .loaded where model.orders.isEmpty:
            StateView(symbol: "bag", title: "Keine Bestellungen", message: "Du hast noch nichts bestellt.")
        case .loaded:
            ScrollView {
                VStack(spacing: Spacing.s3) {
                    if let notice = model.notice { noticeBar(notice) }
                    ForEach(model.orders) { order in card(order) }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load(client: appState.client) }
        }
    }

    private func noticeBar(_ text: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Color.ceviOnSuccessContainer)
            Spacer(minLength: Spacing.s2)
            Button("Schliessen", systemImage: "xmark") { model.dismissNotice() }.labelStyle(.iconOnly).frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
        }
        .padding(.leading, Spacing.s4)
        .background(Color.ceviSuccessContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .contain)
    }

    private func card(_ order: ShopOrder) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s1))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s2))
                layout {
                    Text(order.createdAt.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)))
                        .font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s2) }
                    ShopStatusChip(status: order.status)
                }
                ForEach(Array(order.lines.enumerated()), id: \.offset) { _, line in
                    Text("\(line.quantity) × \(line.variant.map { "\(line.name), \($0)" } ?? line.name)").foregroundStyle(Color.ceviOnSurface)
                }
                Text("Summe \(ShopRules.chf(order.totalCents)). Übergabe: \(order.handover)").foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            .accessibilityElement(children: .combine)
            if let error = model.rowErrors[order.id] { ErrorRow(text: error) }
            if MyShopOrdersModel.canCancel(order) {
                Button("Stornieren", systemImage: "xmark") { cancelling = order }
                    .buttonStyle(.ceviText)
                    .disabled(model.busyId == order.id)
                    .accessibilityLabel(Text("Bestellung vom \(order.createdAt.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone))) stornieren"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }
}

/// State of an order: symbol and word in a capsule.
struct ShopStatusChip: View {
    let status: ShopOrderStatus

    var body: some View {
        let (title, symbol, foreground, background): (LocalizedStringKey, String, Color, Color) = switch status {
        case .open: ("Offen", "questionmark.circle", .ceviOnSurface, .clear)
        case .ready: ("Bereit zur Übergabe", "bag", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .handedOver: ("Übergeben", "checkmark", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .cancelled: ("Storniert", "minus.circle", .ceviOnSurfaceVariant, .clear)
        case .unknown: ("Unbekannt", "questionmark", .ceviOnSurfaceVariant, .clear)
        }
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
            .overlay { if background == .clear { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) } }
    }
}
