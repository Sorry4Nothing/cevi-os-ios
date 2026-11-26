#if DEBUG
import Foundation

nonisolated extension World {
    /// The Lädeli of the simulated server: two articles, orders are accepted and not kept.
    func shopRoutes(_ request: Request, _ route: [String]) -> Reply {
        switch (request.method, route.dropFirst().first, route.dropFirst(2).first) {
        case ("GET", nil, _):
            return .json(200, [
                "angemeldetAls": "Eva",
                "artikel": [
                    article("00000000-0000-0000-0000-0000000000c1", "Lagershirt", 2500, sizes: ["S", "M", "L"], unavailable: ["L"], order: 1),
                    article("00000000-0000-0000-0000-0000000000c2", "Trinkflasche", 1250, sizes: [], unavailable: [], order: 2),
                ],
                "uebergabearten": ["Im Pfadiheim"],
                "grenzen": ["positionen": 20, "menge": 10, "offeneBestellungen": 5],
                "einstellungen": [
                    "bestellenOffen": true, "schnellDazu": false, "preiseOeffentlich": true, "maxMenge": 10, "maxPositionen": 20, "maxOffene": 5,
                    "mindestRappen": 0, "bezahlhinweis": "Bezahlt wird bei der Übergabe.", "zahlungsart": "Bar", "bestaetigung": "Danke! Hol deine Bestellung {uebergabe} ab.",
                    "uebergabehinweis": "", "bedingungen": "", "geschlossenText": "",
                ] as [String: Any],
            ])
        case ("GET", "bestellungen", "meine"):
            return .json(200, ["bestellungen": [Any](), "weitere": false, "naechste": NSNull()])
        case ("POST", "bestellungen", nil):
            let now = DateFormats.timestampText(.now)
            return .json(201, ["id": "00000000-0000-0000-0000-0000000000c9", "status": "offen", "uebergabe": request.body["uebergabe"] ?? "", "summeRappen": request.body["erwarteteSummeRappen"] ?? 0,
                               "erstelltAm": now, "geaendertAm": now, "positionen": [Any]()])
        default:
            return .notFound
        }
    }

    private func article(_ id: String, _ name: String, _ price: Int, sizes: [String], unavailable: [String], order: Int) -> [String: Any] {
        ["id": id, "name": name, "preisRappen": price, "mediumId": NSNull(), "groessenart": sizes.isEmpty ? "einheit" : "liste", "varianten": sizes,
         "nichtVerfuegbar": unavailable, "hinweis": NSNull(), "verfuegbar": true, "verfuegbarGesetzt": true, "reihenfolge": order]
    }
}
#endif
