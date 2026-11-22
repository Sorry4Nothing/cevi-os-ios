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

## Schnitt A1 Start und Aufgaben: Datenschicht (Issue #61)

Gebaut, ohne Bildschirme. Alle Schreib-Routen tragen `version` (Zeilenversion); bei 409 `VERSION_KONFLIKT` liefert `CampRules.versionConflict` «Aktueller Stand» (`current`) und die abweichenden Felder. Löschen sendet `version` als Abfrage-Parameter. Änderungen (PATCH) sind `Encodable`-Typen mit `CampField` (Wert oder `null` zum Leeren).

| Was | Route (unter `/api/v1/lager/{id}`) | Code |
| --- | --- | --- |
| Ressorts (Liste, Detail, anlegen, ändern, löschen, Reihenfolge) | `…/ressorts`, `…/ressorts/{id}`, `PUT …/ressorts/reihenfolge` | `CampPortfolio*`, `campPortfolios` ff. |
| Ressort-Links und -Notizen | `…/ressorts/{id}/links`, `…/notizen` (je GET, POST, PATCH, DELETE) | `CampPortfolioLink*`, `CampPortfolioNote*` |
| Aufgaben (Liste mit Filtern, Detail, anlegen, ändern, löschen, Reihenfolge) | `…/aufgaben`, `…/aufgaben/{id}`, `PUT …/aufgaben/reihenfolge` | `CampTask`, `CampTaskFilter`, `campTasks` ff. |
| Status (auch Team bei eigenen Aufgaben) | `PUT …/aufgaben/{id}/status` | `setCampTaskStatus` |
| Checkliste, Links, Stichworte | `…/aufgaben/{id}/details`, `…/checkliste`, `…/links`, `PUT …/stichworte` | `CampTaskDetails`, `CampChecklistItem`, `CampTaskLink` |
| Verlauf (nur Änderungsfeed, 30 Tage) | `GET …/aufgaben/{id}/verlauf` | `CampTaskHistory` |
| Duplikate, Zusammenführen | `GET …/aufgaben/duplikate`, `POST …/aufgaben/{id}/zusammenfuehren` | `campTaskDuplicates`, `mergeCampTasks` |
| Schnelleingabe: Vorschlag, dann Bestätigung | `POST …/aufgaben/schnell`, dann `POST …/aufgaben` | `suggestCampTasks`, `CampTaskCreate(confirming:)` |
| Zeitplan lesen, Vorschlag, übernehmen | `GET …/zeitplan`, `…/zeitplan/vorschlag`, `POST …/zeitplan/uebernehmen` | `CampSchedule`, `CampScheduleProposal` |
| Meilensteine, Lagertage, Tagesabschnitte | `…/zeitplan/meilensteine`, `…/lagertage`, `…/tagesabschnitte` (POST, PATCH, DELETE) | `CampMilestone`, `CampDay`, `CampDaySection` |
| Frist verschieben: Vorschau, dann Bestätigung | `POST …/zeitplan/meilensteine/{id}/verschieben` (`trocken`) | `previewCampMilestoneMove`, `confirmCampMilestoneMove` |
| Private To-dos (ohne `version`) | `…/todos` (GET, POST, PATCH, DELETE) | `CampTodo*` |
| Vorlage anwenden (auch Vorschau) | `POST …/vorlagen/{id}/anwenden` | `applyCampTemplate` |
| Start der Lagerleitung | `GET …/start` | `CampStart` |
| Entscheide-Sammlung | `GET …/entscheide` | `CampDecision*` |

Hinweise: Die Aufgaben-Antwort enthält kein `aktionen`-Feld. Welche Knöpfe erscheinen, folgt aus der Rolle und `CampRights.allows` (für das Team nicht lesbar: ein verweigerter Schritt endet in 403).

## Schnitt A2 Sitzungen und Kommunikation: Datenschicht (Issue #63)

Gebaut, ohne Bildschirme. Schreib-Routen tragen `version`; Konflikte wie in A1 (`CampRules.versionConflict`, zum Beispiel `as: CampProtocol.self`). Anonyme Eingänge tragen im Modell nie einen Absender: `CampInboxEntry.sender` ist bei `anonym` immer `nil`, auch wenn der Server einen Namen schickt. Der Rückfragecode (`CampInboxSent.followUpCode`) kommt nur in der Antwort auf das Senden und wird nicht gespeichert. Dateien sind Verweise (`CampFileRef`, ID und Link), keine Bytes.

| Was | Route (unter `/api/v1/lager/{id}`) | Code |
| --- | --- | --- |
| Höcks (Liste mit `von`/`bis`, Detail, anlegen, ändern, löschen) | `…/hoecks`, `…/hoecks/{id}` | `CampMeeting*`, `campMeetings` ff. Das Team sieht nur die Kurzform (`CampMeetingView`) |
| Kalenderdatei | `GET …/hoecks/{id}.ics` | `campMeetingCalendar` (Rohdaten) |
| Höck-Modus, Anwesende abhaken, Ressort-Runde | `GET …/hoecks/{id}/modus`, `PUT`/`DELETE …/anwesende/{personId}` | `CampMeetingMode`, `markCampMeetingPresent` |
| Traktanden (anlegen, ändern, löschen, sortieren) | `…/traktanden`, `PUT …/traktanden/reihenfolge` | `CampAgendaItem*`, `CampAgendaOrderBody` |
| «Auf nächsten Höck» | `GET …/traktanden/naechster`, `POST …/hoecks/{id}/traktanden/uebernehmen` | `campWaitingAgendaItems`, `adoptCampAgendaItems` |
| Protokolle (Zeile mit Dateiverweis) | `…/protokolle`, `…/protokolle/{id}` (Filter `hoeckId`, `art`, `q`) | `CampProtocol*` |
| Beschlüsse | `…/beschluesse`, `…/beschluesse/{id}` | `CampResolution*` |
| Erwähnungen, «Als Aufgabe», Abgleich | `GET …/erwaehnungen`, `PUT …/erwaehnungen/{typ}/{quelleId}`, `PATCH …/erwaehnungen/{id}`, `POST …/als-aufgabe` | `CampMention*` |
| Pinnwand (Wichtig, Anheften, Zeitfenster, Empfänger, Dateien) | `…/pinnwand`, `…/pinnwand/{id}` (`status=aktiv\|alle`) | `CampNotice*` |
| Umfragen (anlegen, ändern, löschen, Stimme) | `…/pinnwand/{id}/umfrage`, `…/umfrage/stimme` | `CampPoll*` |
| Reaktionen | `PUT`/`DELETE …/reaktionen/pinnwand_beitrag/{id}` | `CampReactions`, `setCampReaction` |
| Eingang (Leitung: lesen, beantworten, zuordnen, löschen) | `…/eingang`, `…/eingang/{id}` | `CampInbox*` |
| Eingang senden (auch anonym), eigene, Status per Code | `POST …/eingang`, `GET …/eingang/eigene`, `POST …/eingang/status` | `CampInboxSend`, `campOwnInbox`, `campInboxStatus` |
| Meldung zu Traktandum | `POST …/eingang/{id}/traktandum` | `makeCampInboxAgendaItem` |
| Aushänge als PDF | `GET …/aushaenge/{art}` | `campHandout` (Rohdaten) |

Hinweise: Ein Protokoll hat in der API keine Abschnitte, nur eine Zeile (Titel, Datum, Art, Höck) mit Verweis auf eine Datei. `…/als-aufgabe` antwortet 201 (neu) oder 200 (gab es schon); die Dienstfunktion liefert nur die Aufgaben-ID. Der Anwesenheits-Haken (`PUT …/anwesende`) trägt keine `version`.

## Route fehlt (blockiert)

| Gebraucht für | Fehlt | Backend-Issue |
| --- | --- | --- |
| Ereignisstrom im Vordergrund | Server-Sent Events | L0d |
| Offline-Warteschlange | Schreib-Route `POST …/aenderungen` mit `clientOpId`, Konfliktantwort `VERSION_KONFLIKT` | L0c (Lesen da, Schreiben fehlt) |
| Papierkorb, Verlauf, Fassungen | Revisionen | L0e |
| Dateien (Dokumente, Bilder) | Lager-Dateien im Medienspeicher | L0g |
| A1: Lager-Check «Sind wir bereit?» | keine Route in der Beschreibung | L1 |
| A1: Vorlagen auflisten (Auswahl für `anwenden`) | nur `/api/v1/admin/vorlagen` (Admin), die App ruft Admin nie auf | L1 |
| A1: frühere Fassungen einer Aufgabe, Zurückholen | Verlauf kennt nur Art, Version, Zeitpunkt; keine Inhalte | L0e |
| A2: Protokoll-Abschnitte (Text im Protokoll) | nur Zeile mit Dateiverweis, kein Inhalt, keine Abschnitte | L2 |
| A2: Dateien zum Hochladen (Pinnwand, Protokoll) | `dateiIds` setzen vorhandene Dateien voraus, Hochladen: Lager-Dateien | L0g |
| A2: Reaktionen auf anderes als Pinnwand | `zielTyp` kennt nur `pinnwand_beitrag` | L3 |
| A3 Einteilung | Teilnehmende, Zimmer, Fahrten, Gruppen, Schichtplan, Diensttausch | L4 |
| A4 Im Lager | Anwesenheit, Tagesseiten, Einkauf, Packliste, Notfall, Wetter, «Heute» | L5 |
| A5 Ablage und Querschnitt | Dokumente, Adressbuch, Wissen, Suche | L6 |

Nicht ableitbar: Welche Rechte die eigene Rolle hat. Die Matrix darf nur die Lagerleitung lesen. Die Aufgaben-Routen sollen laut Auftrag die erlaubten Aktionen in der Antwort liefern (fehlt die Aktion, fehlt der Knopf).

## Entscheide, die der Auftraggeber treffen muss

1. Lokaler Speicher für das Lager (SwiftData, mit Dateischutz) für Offline-Lesen und die Warteschlange. Widerspricht `docs/architektur.md` (Serverdaten nur im Arbeitsspeicher).
2. Zwischenspeicher für Widgets (App-Gruppe), nötig erst für A7.
3. Design-Entwurf «Cevi Lager iOS» liefern (Bildschirme erst danach).
