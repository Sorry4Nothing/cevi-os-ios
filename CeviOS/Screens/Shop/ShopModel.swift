import SwiftUI

/// Lädeli: the articles of the department and the cart. Built without a design draft from the existing building blocks (`docs/laedeli.md`).
/// The cart lives in memory only and is gone when the app ends.
@MainActor @Observable
final class ShopModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(text: String, isOffline: Bool)
    }

    /// One line of the cart: an article, a size if it has a list, a quantity.
    struct CartLine: Equatable, Identifiable {
        let articleId: UUID
        let variant: String?
        var quantity: Int
        var id: String { "\(articleId.uuidString)|\(variant ?? "")" }
    }

    /// A cart line with its article.
    struct Entry: Identifiable {
        let line: CartLine
        let article: ShopArticle
        var id: String { line.id }
        var totalCents: Int { article.priceCents * line.quantity }
    }

    private(set) var phase: Phase = .loading
    private(set) var catalog: ShopCatalog?
    private(set) var cart: [CartLine] = []
    /// The chosen way of handover; with exactly one way it is chosen already.
    var handover: String?
    /// The order is on its way: the button is locked until the answer is there.
    private(set) var isOrdering = false
    /// Failure of the last order or of the last change of the cart.
    private(set) var error: String?
    /// Message after a successful order.
    private(set) var placedText: String?

    #if DEBUG
    /// Only for previews.
    init(phase: Phase = .loading, catalog: ShopCatalog? = nil, cart: [CartLine] = [], handover: String? = nil, isOrdering: Bool = false, error: String? = nil, placedText: String? = nil) {
        self.phase = phase
        self.catalog = catalog
        self.cart = cart
        self.handover = handover
        self.isOrdering = isOrdering
        self.error = error
        self.placedText = placedText
    }
    #endif

    var isOpen: Bool { catalog?.settings.ordersOpen ?? false }

    var entries: [Entry] {
        cart.compactMap { line in catalog?.articles.first { $0.id == line.articleId }.map { Entry(line: line, article: $0) } }
    }

    var totalCents: Int { entries.reduce(0) { $0 + $1.totalCents } }
    var pieces: Int { cart.reduce(0) { $0 + $1.quantity } }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            catalog = try await client.shopCatalog()
            if let catalog, handover == nil || !catalog.handovers.contains(handover ?? "") {
                handover = catalog.handovers.count == 1 ? catalog.handovers.first : nil
            }
            prune()
            phase = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            if catalog == nil { phase = .failed(text: error.displayText, isOffline: error.kind == .network) }
        } catch {
            if catalog == nil { phase = .failed(text: APIError.network.displayText, isOffline: true) }
        }
    }

    // MARK: Cart

    /// Puts one piece of an article into the cart. `variant` is needed for an article with a size list.
    func add(_ article: ShopArticle, variant: String? = nil) {
        guard let catalog, catalog.settings.ordersOpen, article.isAvailable else { return }
        if article.hasSizeList {
            guard let variant, article.orderableVariants.contains(variant) else { return }
        }
        let size = article.hasSizeList ? variant : nil
        let id = CartLine(articleId: article.id, variant: size, quantity: 1).id
        error = nil
        if let index = cart.firstIndex(where: { $0.id == id }) {
            guard cart[index].quantity < catalog.limits.quantity else {
                say(String(localized: "Von \(article.name) gehen höchstens \(catalog.limits.quantity) Stück pro Bestellung."))
                return
            }
            cart[index].quantity += 1
        } else {
            guard cart.count < catalog.limits.lines else {
                say(String(localized: "Der Warenkorb hat höchstens \(catalog.limits.lines) Positionen."))
                return
            }
            cart.append(CartLine(articleId: article.id, variant: size, quantity: 1))
        }
        AccessibilityNotification.Announcement(String(localized: "\(article.name) im Warenkorb.")).post()
    }

    func setQuantity(_ id: String, _ quantity: Int) {
        guard let index = cart.firstIndex(where: { $0.id == id }) else { return }
        let most = catalog?.limits.quantity ?? 1
        if quantity < 1 { cart.remove(at: index) } else { cart[index].quantity = min(quantity, most) }
    }

    func remove(_ id: String) { cart.removeAll { $0.id == id } }

    func quantityInCart(_ article: ShopArticle) -> Int { cart.filter { $0.articleId == article.id }.reduce(0) { $0 + $1.quantity } }

    /// Takes out what the shop does not offer any more.
    private func prune() {
        guard let catalog else { return }
        let before = cart.count
        cart.removeAll { line in
            guard let article = catalog.articles.first(where: { $0.id == line.articleId }), article.isAvailable else { return true }
            if let variant = line.variant { return !article.orderableVariants.contains(variant) }
            return article.hasSizeList
        }
        for index in cart.indices { cart[index].quantity = min(cart[index].quantity, catalog.limits.quantity) }
        if cart.count < before { say(String(localized: "Ein Artikel ist nicht mehr zu haben. Wir haben ihn aus dem Warenkorb genommen.")) }
    }

    // MARK: Order

    /// What is missing before the order may go out; `nil` if nothing.
    var blocker: String? {
        guard let catalog else { return nil }
        if entries.isEmpty { return String(localized: "Der Warenkorb ist leer.") }
        if handover == nil { return String(localized: "Wähle, wie du die Bestellung bekommst.") }
        if totalCents < catalog.settings.minimumCents { return String(localized: "Die Mindestbestellung ist \(ShopRules.chf(catalog.settings.minimumCents)).") }
        return nil
    }

    /// Orders once. A failure never repeats the order; the person taps again after reading the text.
    func order(client: APIClient?) async {
        guard let client, !isOrdering, isOpen else { return }
        if let blocker { error = blocker; return }
        guard let handover else { return }
        let body = ShopOrderCreate(
            lines: entries.map { .init(articleId: $0.line.articleId, variant: $0.line.variant, quantity: $0.line.quantity) },
            handover: handover, expectedTotalCents: totalCents)
        isOrdering = true
        error = nil
        defer { isOrdering = false }
        do {
            _ = try await BusyState.shared.track { try await client.createShopOrder(body) }
            cart = []
            placedText = ShopRules.confirmation(catalog?.settings.confirmation ?? "", handover: handover)
            AccessibilityNotification.Announcement(placedText ?? "").post()
        } catch let failure as APIError {
            let result = ShopRules.orderFailure(failure)
            cart.removeAll { line in
                result.removeArticles.contains(line.articleId) || result.removeSizes.contains { $0.articleId == line.articleId && $0.variant == line.variant }
            }
            say(result.text)
            if result.reloadsCatalog { await load(client: client) }
        } catch is CancellationError {
        } catch {
            say(ShopRules.orderFailure(.network).text)
        }
    }

    /// Back from the confirmation.
    func finishOrder() { placedText = nil }

    private func say(_ text: String) {
        error = text
        AccessibilityNotification.Announcement(text).post()
    }
}
