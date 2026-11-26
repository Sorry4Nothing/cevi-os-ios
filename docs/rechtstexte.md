# Datenschutz, Support und «Konto löschen lassen» in der App

Ziel (Android-Issue #236): Die drei Seiten sollen nativ in der App stehen statt im Browser. **Stand: nicht gebaut, weil der Vertrag
das Format nicht liefert.** Die App öffnet die Seiten weiter über `ServerPage` im Browser (Profil, Anmeldung, Willkommen).
Der Link «Konto löschen» bleibt damit in der App erreichbar (App-Store-Prüfung, `docs/app-store.md`).

## Befund (Vertrag und Server, 26.11.2026)

| Seite | Route | Antwort |
|---|---|---|
| Datenschutz | `GET /datenschutz` | 308 auf `/datenschutz-website`, eine Seite des Seiteneditors (HTML) |
| Support | `GET /support` | 200, `text/html`, ganze HTML-Seite mit Kopf und Stil |
| Konto löschen | `GET /konto-loeschen` | 200, `text/html`, ganze HTML-Seite mit Kopf und Stil |
| Knoten `{tag, attr?, kinder?}` | `GET /api/v1/website/inhalt?pfad=…` | **nur mit Sitzung** und **nur die geschützten Bausteine** einer Seite; ohne Sitzung 401, unbekannter Pfad 404 |

Ein Aufruf der drei öffentlichen Seiten mit `Accept: application/json` liefert ebenfalls HTML.

## Route fehlt

- Eine öffentliche Route ohne Sitzung, die den Text dieser drei Seiten als Knoten (`WebsiteKnoten`) liefert. `website/inhalt` ist
  dafür nicht gedacht (Sitzung nötig, liefert nur geschützte Bausteine) und für Datenschutz, Support und Konto löschen nicht
  brauchbar: Der Willkommen-Bildschirm und die Anmeldung stehen vor der Sitzung.
- Das HTML der Seiten selbst zu lesen wäre eine Erfindung des Formats: Der Vertrag beschreibt es nur als `string`, ohne Gerüst, ohne
  Zusicherung, welche Elemente vorkommen. Ein HTML-Leser in der App wäre eine neue Angriffsfläche (Links, Stil, Skripte) ohne
  Vertrag. Der Auftrag verbietet WebView.

## Nächster Schritt

Backend: `GET /api/v1/website/seite?pfad=/datenschutz-website` (oder gleichwertig) ohne Sitzung, Antwort `WebsiteInhalt`, Grenze
512 KiB, nur die drei Adressen. Danach in der App: Dienst ohne Sitzung (eigener Host, Weiterleitungen nur auf denselben Host),
Knotenleser für Überschrift, Absatz, Liste, fett, kursiv, Link (nur `https`, `mailto:`, `tel:`), Bildschirme mit Laden, Fehler,
Ohne Netz und leerer Seite, Text nur im Arbeitsspeicher, Einstiege im Profil und im Willkommen-Bildschirm, `POST /ich/datenschutz`
bleibt. Verantwortliche Stelle und Kontaktadresse setzt der Server ein, sie stehen nicht im Repo.
