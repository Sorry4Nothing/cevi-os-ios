# Widgets (W1 bis W6, WC1, WC2, WK)

Entwurf: Boards `W1..W6`, `WC1`, `WC2`, `WK-Galerie` in «Cevi Lager iOS». Der Auftraggeber hat Widgets und App-Gruppe freigegeben.

## Aufbau

| Teil | Ort |
| --- | --- |
| Widget-Extension (Ziel `CeviOSWidgetsExtension`, Bundle-ID `<App>.widgets`) | `CeviOSWidgets/` |
| Gemeinsamer Code (App und Extension): Schnappschuss-Modell, Speicher, Zustände, Stand-Zeile, Layoutplan, Links, Beispieldaten | `CeviShared/` |
| Farbsets `cevi-<token>` (aus `CeviOS/Assets.xcassets` hierher verschoben, beide Ziele nutzen sie) | `CeviShared/Colors.xcassets` |
| Schwärzung, Abruf, Schreiben in die App-Gruppe | `CeviOS/Core/Widgets/` |
| Konfiguration (WC1 Stufe, WC2 Lager) | `CeviOSWidgets/WidgetIntents.swift` |

Ablauf: Die App holt die Daten mit den bestehenden Diensten (`calendarEvents`, `camps`, `campToday`, `campMyWeek`, `campTasks`, `chats`), schwärzt sie in `WidgetSnapshotBuilder` und schreibt **eine** Datei `widget-snapshot.json` in den Container der App-Gruppe (atomar, Dateischutz «bis zur ersten Entsperrung», vom Backup ausgenommen, höchstens 256 KB). Die Extension liest nur diese Datei. **Sie macht keine Netzanfragen und kennt weder Sitzung noch Cookie.**

Aktualisierung (`AppState.refreshWidgets()`, danach `WidgetCenter.reloadAllTimelines()`): beim Öffnen und Verlassen der App, nach der Anmeldung, nach einer Antwort im Programm, bei einem Push im Vordergrund. Die Zeitleiste lädt zusätzlich alle 30 Minuten neu (liest nur die Datei) und schaltet die Stand-Zeile nach 2 Stunden auf «veraltet.» **Nicht gebaut:** `BGAppRefreshTask`. Er braucht den Hintergrundmodus «Fetch» in der `Info.plist`, also eine neue Berechtigung. Ohne App-Start bleibt der Stand deshalb alt (die Stand-Zeile sagt es).

## Schwärzung (Datenschutz)

Das Modell (`WidgetSnapshot`) hat **keine Felder** für Kindernamen, Namen anderer Personen, Chat-Inhalte, Telefonnummern oder Adressen. Der Stand der Zusagen ist eine Zahl («Zusage für 1 Kind offen»), Chats sind nur Zähler. Der Treffpunkt ist die erste Zeile des Feldes ohne Zeilen mit Nummern (ab 6 Ziffern oder mit `@`), nur für das nächste Programm und nur in W1 auf dem Homescreen; Sperrbildschirm-Widgets und der Zustand «Gesperrt» zeigen ihn nie. Texte sind auf eine Zeile und 80 Zeichen gekürzt. Tests: `WidgetTests` (Feldliste, Antworten voller Namen).

Redaktion (Board «S Gesperrt»): Bei gesperrtem Gerät (`redactionReasons.privacy`) oder eingeschaltetem App-Sperre (`hidesContent`, mit dem Stand der App geschrieben) zeigen W1 bis W4 und W6 nur Art, Zeit und Zähler und «Zum Anzeigen die App öffnen».

## Löschregeln

Abmelden, Sitzungsende und Wechsel zu «nicht angemeldet» (`AppState.onSignOut`): alle Daten werden gelöscht, die Datei enthält nur noch die Marke «abgemeldet», die Widgets laden neu (Zustand «Nicht angemeldet»). Ohne Sitzung beim Start schreibt die App die Marke einmal. Der Zustand «Noch nie geöffnet» gilt, solange die Datei fehlt, beschädigt, zu gross oder von einer anderen Version ist.

## Ohne App-Gruppe (Personal Team)

`WidgetStore.shared` liest die Gruppe aus `AppGroupIdentifier` in der `Info.plist` (`APP_GROUP_ID` in `Config/*.xcconfig`). Gibt es den Container nicht, ist der Speicher leer: nichts wird geschrieben, die App läuft normal, die Widgets zeigen «Noch nie geöffnet». Die Entitlement steht nur in `Config/CeviOS.entitlements` und `Config/CeviOSWidgets.entitlements`, und diese nutzen nur Int und Prod (Dev hat keine Entitlements).

## Ziele (Tippen)

Link `cevios://open?typ=…&id=…`, gelesen wie die Daten eines Pushs (`PushTarget.from(userInfo:)`, auch beim Kaltstart über `pendingTarget`): `programm`+Programm-ID (W1, W2), `chats` (W6), `lager_heute`, `lager_aufgaben`, `lager_notfall` + Lager-ID (W3, W4, W5), `lager_aufgabe` + Aufgaben-ID (Zeilen in W4). Ab «mittel» öffnet jede Zeile ihr Ziel. Ohne Daten öffnet die Fläche die App.

## Abweichungen vom Entwurf

- Schrift: Systemschrift statt Archivo (die Extension bündelt die Schrift nicht).
- Konfiguration (WC1, WC2): Das System zeichnet die Liste. Die Zustände «Liste lädt» und «Fehler» zeichnet das System selbst. «Keine Auswahl möglich»: Die Liste hat dann einen Eintrag, der Satz «Hat dein Kind nur eine Stufe, nimmt das Widget sie automatisch.» steht in der Beschreibung des Intents. Untertitel «Für dein Kind in der Stufe Wölfe» statt «… bei den Wölfen» (der Dativ lässt sich aus dem Namen nicht bilden).
- Galerie (WK): Die Vorschauen entstehen aus erfundenen Beispieldaten (`WidgetSamples`) und der echten Ansicht; Titel und Beschreibung stehen im Widget.
- Platzhalter (P) zeichnet das System (`.redacted`) aus denselben Ansichten, nicht als eigene Balkenansicht.
- Getönt (Y) und Klar (K): Das System tönt die Widgets; Kopfsymbol und Zähler sind `widgetAccentable`. Keine eigene Variante.
- Stufenleitung in W1: Der Satz «Zusage für … offen» fehlt, der Entwurf nennt keinen Text für die eigene Zusage.
- W5 zeigt keine Nummern (der Entwurf zeigt keine). Sanität 144 und Rega 1414 stehen auf der Notfall-Seite der App.
- W4 «Später fällig» und «Diese Woche erledigt» zeigt nur, wer die Aufgabenliste lesen darf.

## Offene Fragen

- Dürfen die Titel der «Wichtig»-Blöcke (W3) und der Aufgaben (W4) im Widget stehen? Es ist freier Text der Lagerleitung und kann Namen enthalten. Der Entwurf zeigt sie; gekürzt auf eine Zeile.
- W3, W4, W5 zeigen bei mehreren aktiven Lagern das gewählte (W3) oder das erste. Soll W4/W5 auch eine Wahl bekommen?
- Nummern aus dem Lager (Notfallkontakte) in W5: weggelassen, bis der Datenschutz-Entscheid vorliegt.
- Hintergrundaktualisierung (`BGAppRefreshTask`): neue Berechtigung nötig, Entscheid des Auftraggebers.
- Nicht auf Gerät geprüft: Die Widgets wurden nur als Vorschau gerendert (Tag, Nacht), nicht in der Widget-Galerie oder auf dem Sperrbildschirm.
