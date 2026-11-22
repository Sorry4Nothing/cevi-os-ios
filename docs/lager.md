# Lager-Modul in der App: Stand

Quelle: Auftrag «Lager-Apps» (Obsidian, `Cevi/Cevi OS Erweiterung/`). Gebaut wird nur, was die API-Beschreibung (`api-vertrag/openapi.yaml`) heute hergibt. Bildschirme folgen nach dem Design-Entwurf.

## Schnitt A0 Gerüst: Datenschicht (Issue #59)

Gebaut, ohne Bildschirme:

| Was | Route | Code |
| --- | --- | --- |
| Meine Lager, Rolle | `GET /api/v1/lager`, `GET /api/v1/lager/{id}` | `Camp.swift`, `CampService.swift` |
| Rechte-Matrix (nur Lagerleitung) | `GET /api/v1/lager/{id}/rechte` | `CampRights.allows` |
| Benachrichtigungen | `GET …/benachrichtigungen`, `…/ungelesen`, `POST …/gelesen` | `CampNotification*` |
| Push-Ziel auflösen | `GET /api/v1/lager/aufloesen/{typ}/{id}` | `PushTarget.camp`, `resolveCampPush` |
| Änderungsfeed lesen | `GET /api/v1/lager/{id}/aenderungen` (410: neu laden) | `campFeedState`, `campChanges` |

Der Push-Typ `lager_*` wird erkannt (`PushTarget.camp`). Ein Tipp darauf öffnet noch nichts, weil es keine Lager-Bildschirme gibt.

## Route fehlt (blockiert)

| Gebraucht für | Fehlt | Backend-Issue |
| --- | --- | --- |
| Ereignisstrom im Vordergrund | Server-Sent Events | L0d |
| Offline-Warteschlange | Schreib-Route `POST …/aenderungen` mit `clientOpId`, Konfliktantwort `VERSION_KONFLIKT` | L0c (Lesen da, Schreiben fehlt) |
| Papierkorb, Verlauf, Fassungen | Revisionen | L0e |
| Dateien (Dokumente, Bilder) | Lager-Dateien im Medienspeicher | L0g |
| A1 Start und Aufgaben | Ressorts, Aufgaben, Zeitplan, Schnelleingabe, Lager-Check | L1a bis L1g |
| A2 Sitzungen und Kommunikation | Höcks, Protokolle, Erwähnungen, Pinnwand, Umfragen, Eingang | L2, L3 |
| A3 Einteilung | Teilnehmende, Zimmer, Fahrten, Gruppen, Schichtplan, Diensttausch | L4 |
| A4 Im Lager | Anwesenheit, Tagesseiten, Einkauf, Packliste, Notfall, Wetter, «Heute» | L5 |
| A5 Ablage und Querschnitt | Dokumente, Adressbuch, Wissen, Suche | L6 |

Nicht ableitbar: Welche Rechte die eigene Rolle hat. Die Matrix darf nur die Lagerleitung lesen. Die Aufgaben-Routen sollen laut Auftrag die erlaubten Aktionen in der Antwort liefern (fehlt die Aktion, fehlt der Knopf).

## Entscheide, die der Auftraggeber treffen muss

1. Lokaler Speicher für das Lager (SwiftData, mit Dateischutz) für Offline-Lesen und die Warteschlange. Widerspricht `docs/architektur.md` (Serverdaten nur im Arbeitsspeicher).
2. Zwischenspeicher für Widgets (App-Gruppe), nötig erst für A7.
3. Design-Entwurf «Cevi Lager iOS» liefern (Bildschirme erst danach).
