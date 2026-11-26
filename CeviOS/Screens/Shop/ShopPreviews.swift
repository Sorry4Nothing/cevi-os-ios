#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the Lädeli.
@MainActor
enum ShopPreview {
    static func catalog(open: Bool = true) -> ShopCatalog {
        let json = """
        {"angemeldetAls":"Lea","artikel":[
          {"id":"0190a000-0000-7000-8000-0000000c0001","name":"Lagershirt","preisRappen":2500,"mediumId":null,"groessenart":"liste","varianten":["S","M","L","XL"],"nichtVerfuegbar":["XL"],"hinweis":"Aus Biobaumwolle","verfuegbar":true,"verfuegbarGesetzt":true,"reihenfolge":1},
          {"id":"0190a000-0000-7000-8000-0000000c0002","name":"Trinkflasche","preisRappen":1250,"mediumId":null,"groessenart":"einheit","varianten":[],"nichtVerfuegbar":[],"hinweis":null,"verfuegbar":true,"verfuegbarGesetzt":true,"reihenfolge":2},
          {"id":"0190a000-0000-7000-8000-0000000c0003","name":"Sticker","preisRappen":0,"mediumId":null,"groessenart":"einheit","varianten":[],"nichtVerfuegbar":[],"hinweis":null,"verfuegbar":false,"verfuegbarGesetzt":false,"reihenfolge":3}],
         "uebergabearten":["Im Pfadiheim","Am Lager"],"grenzen":{"positionen":20,"menge":10,"offeneBestellungen":5},
         "einstellungen":{"bestellenOffen":\(open),"schnellDazu":false,"preiseOeffentlich":true,"maxMenge":10,"maxPositionen":20,"maxOffene":5,"mindestRappen":1000,
           "bezahlhinweis":"Bezahlt wird bei der Übergabe.","zahlungsart":"Bar oder TWINT","bestaetigung":"Danke! Hol deine Bestellung {uebergabe} ab.","uebergabehinweis":"Wir melden uns, sobald alles bereit ist.",
           "bedingungen":"Bestellte Artikel werden nicht zurückgenommen.","geschlossenText":"Das Lädeli ist bis zum nächsten Lager geschlossen."}}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder.api.decode(ShopCatalog.self, from: Data(json.utf8))
    }

    static func order(_ n: Int, status: String) -> ShopOrder {
        let json = """
        {"id":"0190a000-0000-7000-8000-0000000d00\(String(format: "%02d", n))","status":"\(status)","uebergabe":"Im Pfadiheim","summeRappen":3750,
         "erstelltAm":"2027-03-01T08:00:00Z","geaendertAm":"2027-03-01T08:00:00Z",
         "positionen":[{"artikelId":null,"name":"Lagershirt","variante":"M","menge":1,"einzelpreisRappen":2500},{"artikelId":null,"name":"Trinkflasche","variante":null,"menge":1,"einzelpreisRappen":1250}]}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder.api.decode(ShopOrder.self, from: Data(json.utf8))
    }

    static var cart: [ShopModel.CartLine] {
        [.init(articleId: UUID(uuidString: "0190a000-0000-7000-8000-0000000c0001")!, variant: "M", quantity: 2),
         .init(articleId: UUID(uuidString: "0190a000-0000-7000-8000-0000000c0002")!, variant: nil, quantity: 1)]
    }

    static func shop(_ model: ShopModel) -> some View { NavigationStack { ShopView(model: model) }.environment(AppState()) }
    static func cart(_ model: ShopModel) -> some View { NavigationStack { ShopCartView(model: model) }.environment(AppState()) }
    static func orders(_ model: MyShopOrdersModel) -> some View { NavigationStack { MyShopOrdersView(model: model) }.environment(AppState()) }
}

#Preview("Lädeli Normal") { ShopPreview.shop(ShopModel(phase: .loaded, catalog: ShopPreview.catalog(), cart: ShopPreview.cart)) }
#Preview("Lädeli Nacht") { ShopPreview.shop(ShopModel(phase: .loaded, catalog: ShopPreview.catalog())).preferredColorScheme(.dark) }
#Preview("Lädeli Geschlossen") { ShopPreview.shop(ShopModel(phase: .loaded, catalog: ShopPreview.catalog(open: false))) }
#Preview("Lädeli Laden") { ShopPreview.shop(ShopModel(phase: .loading)) }
#Preview("Lädeli Fehler") { ShopPreview.shop(ShopModel(phase: .failed(text: "Etwas ist schiefgegangen.", isOffline: false))) }
#Preview("Lädeli Ohne Netz") { ShopPreview.shop(ShopModel(phase: .failed(text: "Keine Verbindung.", isOffline: true))) }
#Preview("Warenkorb") { ShopPreview.cart(ShopModel(phase: .loaded, catalog: ShopPreview.catalog(), cart: ShopPreview.cart, handover: "Im Pfadiheim")) }
#Preview("Warenkorb Nacht Fehler") {
    ShopPreview.cart(ShopModel(phase: .loaded, catalog: ShopPreview.catalog(), cart: ShopPreview.cart, error: "Ein Preis hat sich geändert. Die neue Summe ist CHF 63.00. Prüfe den Warenkorb und bestelle nochmals."))
        .preferredColorScheme(.dark)
}
#Preview("Warenkorb Leer") { ShopPreview.cart(ShopModel(phase: .loaded, catalog: ShopPreview.catalog())) }
#Preview("Warenkorb Bestellt") { ShopPreview.cart(ShopModel(phase: .loaded, catalog: ShopPreview.catalog(), placedText: "Danke! Hol deine Bestellung Im Pfadiheim ab.")) }
#Preview("Bestellungen Normal") {
    ShopPreview.orders(MyShopOrdersModel(phase: .loaded, orders: [ShopPreview.order(1, status: "offen"), ShopPreview.order(2, status: "bereit"), ShopPreview.order(3, status: "storniert")]))
}
#Preview("Bestellungen Nacht") { ShopPreview.orders(MyShopOrdersModel(phase: .loaded, orders: [ShopPreview.order(1, status: "offen")])).preferredColorScheme(.dark) }
#Preview("Bestellungen Leer") { ShopPreview.orders(MyShopOrdersModel(phase: .loaded)) }
#Preview("Bestellungen Laden") { ShopPreview.orders(MyShopOrdersModel(phase: .loading)) }
#Preview("Bestellungen Fehler") { ShopPreview.orders(MyShopOrdersModel(phase: .failed(text: "Etwas ist schiefgegangen.", isOffline: false))) }
#Preview("Bestellungen Stornieren scheitert") {
    let order = ShopPreview.order(1, status: "offen")
    return ShopPreview.orders(MyShopOrdersModel(phase: .loaded, orders: [order], rowErrors: [order.id: "Keine Verbindung zum Server. Bitte später nochmals versuchen."]))
}
#endif
