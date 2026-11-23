# Termine: Datenschicht (Schnitt C1)

Modelle, Dienste und Tests für die Termine der App. Keine Bildschirme, kein lokaler Speicher, keine Widgets.
Quelle ist `api-vertrag/openapi.yaml` (Stand der Kopie siehe `api-vertrag/README.md`). Neue Dateien tragen das Präfix `Event`.

## Was gebaut ist

| Was | Route | Code |
|---|---|---|
| Mein Kalender, eines Zeitraums, mit Seiten | `GET /api/v1/termine/mein` | `calendarEvents` |
| Termin im Detail (Stufenseite, eigene Anmeldung, Verweis auf Anlass) | `GET /api/v1/termine/{id}` | `calendarEvent` |
| Kalenderlink: Status | `GET /api/v1/ich/kalender-link` | `calendarLinkStatus` |
| Kalenderlink: erzeugen oder ersetzen (Adresse nur hier) | `POST /api/v1/ich/kalender-link` | `createCalendarLink`, `CalendarLinkNew.url(base:)` |
| Kalenderlink: widerrufen | `DELETE /api/v1/ich/kalender-link` | `revokeCalendarLink` |
| Vorschlagen: Recht und Kategorien | `GET /api/v1/termin-vorschlaege/optionen` | `eventSuggestionOptions` |
| Eigene Vorschläge | `GET /api/v1/termin-vorschlaege/meine` | `myEventSuggestions` |
| Termin vorschlagen | `POST /api/v1/termin-vorschlaege` | `createEventSuggestion`, `EventSuggestionCreate` |
| Vorschlag lesen, zurückziehen | `GET`/`DELETE /api/v1/termin-vorschlaege/{id}` | `eventSuggestion`, `withdrawEventSuggestion` |
| Räume | `GET /api/v1/raeume` | `rooms` |
| Raum anfragen | `POST /api/v1/raeume/{id}/anfragen` | `requestRoom` |
| Eigene und offene Anfragen | `GET /api/v1/raeume/anfragen/meine`, `…/offen` | `myRoomRequests`, `openRoomRequests` |
| Anfrage stornieren | `DELETE /api/v1/raeume/anfragen/{id}` | `cancelRoomRequest` |
| Anfrage entscheiden | `POST /api/v1/raeume/anfragen/{id}/entscheid` | `decideRoomRequest`, `RoomDecision` |
| Anlass-Anmeldung: Formular | `GET /api/v1/anlaesse/{id}` | `eventRegistrationForm` |
| Anlass-Anmeldung: anmelden, ändern, abmelden | `PUT`/`DELETE /api/v1/anlaesse/{id}/anmeldung` | `registerForEvent`, `unregisterFromEvent` |
| Fehlercodes und Texte (Raum, Vorschlag, Anmeldung) | | `EventRules` |

Tests: `CeviOSTests/Core/Services/EventTests.swift`; alle Aufrufe stehen im Vertragstest `ApiContractTests`.

## Bewusst nicht gebaut

- `GET /api/v1/termine/alle`: nur für das Web, die App liest nur «Mein Kalender».
- `/api/v1/admin/*` (Warnliste, Vorschläge entscheiden, Räume verwalten, Anmeldungen und CSV), `/api/v1/redaktion/*`, `/api/v1/website/*`.

## Route fehlt

- Keine. Die Anlass-Anmeldung (Formular mit Text, Ja/Nein und Auswahl, Anmeldung über das Konto) steht in der Beschreibung.
- Der Verweis vom Termin auf den Anlass steht in `GET /api/v1/termine/mein` (Feld `anlass`), eine Route «alle Anlässe» gibt es nicht und braucht es nicht.

## Annahmen und offene Punkte

- Der Kalenderlink ist ein Geheimnis. `CalendarLinkNew` gibt die Adresse nur über `url(base:)` an den Aufrufer, druckt sie nie, und der Dienst speichert sie nicht. Anzeigen nur im Teilen-Blatt, nie in Logs, Absturzberichten oder Widgets.
- Der Server liefert jeden Termin je Person einmal, auch bei mehreren passenden Tags. `CalendarEventPage.appending` hält ihn zusätzlich beim Seitenwechsel nur einmal.
- Eingabefehler (400) und Konflikte (409) der Schreibaufrufe geben den Servertext weiter. Eigene Texte gibt es nur für die 409-Fälle (`EventRules`). `APIError` behält dafür auch den Body eines 400 (`conflictBody`), damit `EventRules.answerErrors` die Feldfehler lesen kann.
- Unbekannte Werte des Servers sind bei Status des Termins, Art des Tags und Art des Formularfelds tolerant (`unknown`). Feste Mengen (Status von Vorschlag, Anfrage und Anmeldung) sind strikt.
- `ETag` und `If-None-Match` (304) der beiden Terminrouten sind nicht umgesetzt: Die App lädt bei jedem Aufruf neu. Das gehört zum Entscheid über den lokalen Speicher.
- Wer vorschlagen darf und wer Räume anfragen darf, sind laut Beschreibung Annahmen des Servers, noch nicht vom Nutzer bestätigt. Die App richtet sich nach `darfVorschlagen` und den Antworten 403/404.
- Offen (nicht geprüft): ob die Liste einen mehrtägigen Termin einmal oder je Tag liefert. Die Beschreibung sagt «erscheint an jedem seiner Tage».
- Die neue Beschreibung kennt `PUT /api/v1/programme/{id}/zuordnung` nicht mehr (Backend #449: 404). Der Aufruf `assign` in `LeadershipService` bleibt vorerst und ist im Vertragstest als Ausnahme eingetragen; beides entfällt zusammen mit der Umstellung der Programme auf «Mein Kalender».
