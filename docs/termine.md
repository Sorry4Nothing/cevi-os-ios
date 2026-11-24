# Termine: Datenschicht (C1) und Bildschirme (C2)

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

## Bildschirme (Schnitt C2)

| Board | Bildschirm | Code |
|---|---|---|
| A1, A2 | Programme: «Mein Kalender» mit Ort, Gruppen-Chips, Antwortzeile ohne Kindernamen | `ProgramListView`, `ProgramRow`, `ProgramListModel` (lädt `GET /termine/mein`, folgt den Seiten) |
| A3, A4 | Detail: Gruppen, Treffpunkt, Ja/Nein pro Kind (`/programme/{id}/teilnahmen/{kindId}` bleibt), Leitende: Hinweis auf Outlook-Kategorie und «Anmeldungen ansehen» mit Zahlen | `ProgramDetailView`, `ProgramDetailModel` (lädt `GET /termine/{id}`), `EventProgram.swift` |
| A6 | Profil: Meine Gruppen, Kalender-Link (erzeugen, ersetzen, widerrufen, Teilen-Blatt) | `ProfileView`, `CalendarLinkCard`, `CalendarLinkModel` |
| A7 | Benachrichtigungen | `NotificationsView`, `NotificationsModel` |
| K1 | Termin vorschlagen | `SuggestEventView`, `SuggestEventModel` |
| K2 | Raum anfragen | `RequestRoomView`, `RequestRoomModel` |
| K3 | Meine Raumanfragen | `MyRoomRequestsView`, `MyRoomRequestsModel` |
| K4 | Anlass-Anmeldung | `EventRegistrationView`, `EventRegistrationModel` |

Erreichbar: K1 bis K3 über das «+»-Menü im Programme-Tab, K4 über die Zeile «Zur Anmeldung» im Detail eines Termins mit Anlass, A7 über Profil, «App».

Rückbau (Backend #449): `PUT /programme/{id}/zuordnung`, `LeadershipService.assign`, der Zuordnungs-Bildschirm, `programs(from:to:)` und `program(id:)` sind entfernt.

### Abweichungen vom Entwurf
- Nur «Mein Kalender» (Design-Abweichung 1), keine Kindernamen in den Antwortzeilen.
- «Ohne Netz» (A1 bis A3, K1, K4) mit Stand von heute und wartenden Änderungen braucht lokalen Speicher und die Warteschlange der Termine: nicht gebaut. Ohne Verbindung zeigt der Bildschirm «Keine Verbindung».
- A2: Die Liste liefert `eigeneAnmeldung` nicht, die Zeilen der Leitung zeigen darum «Du kommst» nicht. Die eigene Antwort steht im Detail.
- A3/A4: Die Schaltfläche «Zum Kalender hinzufügen» (EventKit) ist nicht gebaut. Der Block «Info» fehlt, die API liefert keinen Infotext.
- A6: «Link kopieren» geht nur direkt nach dem Erzeugen (die Adresse gibt es nur einmal); darum «Link erzeugen» und «Link neu erzeugen» mit Teilen-Blatt, dazu «Link widerrufen». «Meine Gruppen» nennt Stufen, Funktion und Lager; Teams stehen nicht in `GET /ich`.
- A7: Die Schalter «Entscheid zu meinem Terminvorschlag» und «Entscheid zu meiner Raumanfrage» fehlen: Die API kennt dafür keine Art. Dazu stehen Chat, Programme und Anmeldungen (Profil-Schalter) und die Lager-Arten.
- K3: Stornieren offener Anfragen steht nicht im Entwurf, `cancelRoomRequest` wird nur für «Rückgängig» in K2 genutzt.
- K4: «Zu den Programmen» geht einen Schritt zurück (zum Detail), nicht an die Wurzel.
- «Termin vorschlagen» zeigt nur zeitgebundene Termine (der Entwurf kennt kein «ganztägig»).

### Offene Fragen zum Entwurf und zur API
- Ob die `id` eines Stufen-Tags der `stufeId` aus `GET /ich` entspricht: Die App nimmt es an (Rechte für «Anmeldungen ansehen», Logo).
- Wo K1 bis K3 im Entwurf einsteigen: die Boards zeigen keinen Einstieg, gebaut ist das «+»-Menü.
