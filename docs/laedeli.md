# Lädeli

Artikel ansehen, bestellen, eigene Bestellungen ansehen und offene stornieren. **Ohne Entwurf gebaut**: aus den vorhandenen
Bausteinen (`Components/`, Vorbild `Screens/Events/`), nach `docs/design.md` und dem UX-Handbuch. Kein lokaler Speicher:
Artikel, Warenkorb und Bestellungen liegen nur im Arbeitsspeicher. Referenz: Android-Issue #243.

## Was gebaut ist

| Was | Route | Code |
|---|---|---|
| Artikel, Übergabearten, Grenzen, Regeln und Texte | `GET /api/v1/laden` | `shopCatalog`, `ShopCatalog` |
| Bestellen (einmal, mit `erwarteteSummeRappen`) | `POST /api/v1/laden/bestellungen` | `createShopOrder`, `ShopOrderCreate` |
| Meine Bestellungen | `GET /api/v1/laden/bestellungen/meine` | `myShopOrders` |
| Stornieren (nur Stand «offen») | `DELETE /api/v1/laden/bestellungen/{id}` | `cancelShopOrder` |
| Fehlercodes, Texte, Beträge («CHF 12.50») | | `ShopRules` |

Bildschirme: `Screens/Shop/` (`ShopView`, `ShopCartView`, `MyShopOrdersView`, Modelle `ShopModel`, `MyShopOrdersModel`).
Einstieg: Profil, Zeile «Lädeli» (Abschnitt «Abteilung»). Tests: `ShopTests`, UI-Ablauf `ShopFlowTests`.

## Regeln

- Nicht zu habende Grössen stehen sichtbar im Text («Nicht zu haben: XL»), das Menü «Grösse wählen» bietet sie nicht an.
  Ein nicht verfügbarer Artikel hat keinen Knopf. Ist `bestellenOffen` aus, zeigt die Liste die Artikel, einen Hinweis mit dem
  Text der Abteilung und keinen Knopf zum Bestellen und keinen Warenkorb.
- Bestellen sperrt den Knopf bis zur Antwort. **Der Vertrag hat keinen Idempotenz-Schlüssel** (`LadenBestellen` erlaubt keine
  weiteren Felder). Darum wiederholt die App nie von selbst. Scheitert die Verbindung, bleibt der Warenkorb, der Text sagt, dass
  die Bestellung vielleicht angekommen ist, und verweist auf «Meine Bestellungen».
- Fehler: `PREIS_GEAENDERT` (neue Summe nennen, Shop neu laden, Warenkorb bleibt), `ARTIKEL_NICHT_VERFUEGBAR` und
  `GROESSE_NICHT_VERFUEGBAR` (betroffene Zeilen aus dem Warenkorb nehmen), `LADEN_GESCHLOSSEN` (Text der Abteilung),
  `MINDESTBESTELLUNG`, `BESTELL_LIMIT`, `POSITIONEN_ZU_VIELE`, `MENGE_ZU_GROSS`, `VARIANTE_UNGUELTIG`, `UEBERGABE_UNBEKANNT`,
  beim Stornieren `STATUS_UNGUELTIG` und 404. Die Mindestbestellung prüft die App zusätzlich vorher.
- `APIError.conflictBody` behält neu auch den Body einer 422 (die Positionen von `GROESSE_NICHT_VERFUEGBAR`).

## Nicht gebaut

Zahlung (der Vertrag kennt keine), `/admin/…`, Artikelbilder (`mediumId` bleibt ungenutzt), «Schnell dazu» (`schnellDazu`),
Offline-Lesen und Warenkorb über den App-Start hinaus.

## Offene Fragen

- Ohne Entwurf: Aufbau, Abstände und Texte sind eine Annahme und gehören im Design-Board nachgezogen.
- `preiseOeffentlich` betrifft nur Besucher ohne Konto; die App ist immer angemeldet und zeigt Preise immer.
