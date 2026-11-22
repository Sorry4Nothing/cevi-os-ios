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

## Schnitt A3 Einteilung: Datenschicht (Issue #65)

Gebaut, ohne Bildschirme. Schreib-Routen tragen `version`; Konflikte wie in A1 (`CampRules.versionConflict`). Vorschläge und Bestätigung sind getrennte Aufrufe: Mischen (`suggestCampGroupShuffle`, dann `confirmCampGroupShuffle`) und «Leere Dienste füllen» (`suggestCampShifts`, dann `confirmCampShifts`) senden bei der Bestätigung denselben `seed` (und dieselben Optionen); der Server liefert bei gleichem Stand dasselbe Ergebnis. Auch der Import der Teilnehmenden hat Vorschau und Bestätigung. Namen und Stufen von Teilnehmenden gehören nie in Widgets, Logs oder Benachrichtigungen (Doc-Kommentare in den Modellen). Für den Screenreader liefert `CampShiftText.sentence` und `CampShiftPlan.sentences(days:sections:)` ganze Sätze («Küche, Montag Vormittag, Pat Muster, noch ein Platz frei»).

| Was | Route (unter `/api/v1/lager/{id}`) | Code |
| --- | --- | --- |
| Teilnehmende (Liste mit `stufe`, Detail, anlegen, ändern, löschen) | `…/teilnehmer`, `…/teilnehmer/{id}` | `CampParticipant*`, `campParticipants` ff. `ceviName` nur für Rollen mit Recht (sonst `nil`) |
| Import aus Text: Vorschau, dann Bestätigung | `POST …/teilnehmer/import` (`uebernehmen`) | `previewCampParticipantImport`, `importCampParticipants` |
| Abzählliste (Filter `art`, `stufe`, `gruppe`), Haken für alle, Zurücksetzen | `GET`/`PUT …/abzaehlen`, `POST …/abzaehlen/zuruecksetzen` | `CampCountEntry`, `CampCountFilter`, `setCampCount`, `resetCampCount` |
| Zimmer und Zelte (Team sieht nur Namen) | `…/zimmer`, `…/zimmer/{id}`, `GET …/zimmer/offen` | `CampRoomView` (voll oder Team), `CampRoomRow`, `campOpenRoomPeople` |
| Einteilen, Herausnehmen (Überbelegung erlaubt, `ueberbelegt`) | `POST …/zimmer/{id}/zuordnung`, `…/zuordnung/entfernen` | `placeInCampRoom`, `removeFromCampRoom` |
| Fahrten, Mitfahrende, Personen ohne Fahrt | `…/fahrten`, `…/fahrten/{id}`, `…/mitfahrer`, `GET …/fahrten/ohne` | `CampTrip*`, `addCampPassenger`, `campPeopleWithoutTrip` (Cursor ist Text) |
| Gruppen, Zuordnung (`gruppeId` null = keine), Abwählen | `…/gruppen`, `PUT …/gruppen/zuordnung`, `PUT …/gruppen/abgewaehlt` | `CampGroup*`, `assignCampGroup`, `deselectCampParticipants` |
| Gemischt einteilen: Vorschlag, dann Bestätigung | `POST …/gruppen/mischen` (`uebernehmen`, `seed`) | `suggestCampGroupShuffle`, `confirmCampGroupShuffle` |
| Schichtplan lesen, Dienste, Besetzung eines Tages | `GET …/schichtplan`, `…/schichtplan/dienste`, `PUT …/schichtplan/schichten` | `CampShiftPlan`, `CampDuty*`, `setCampShifts` |
| Leere Dienste füllen: Vorschlag, dann Bestätigung | `POST …/schichtplan/vorschlag` | `suggestCampShifts`, `confirmCampShifts`, `CampShiftOptions` |
| Diensttausch (alle, eigene, anfragen, entscheiden, zurückziehen) | `…/diensttausch`, `…/eigene`, `…/{id}/entscheid`, `…/{id}/zurueckziehen` | `CampShiftSwap*` |

Hinweise: Die Schichten-Route (`PUT …/schichten`) liefert einen Zustand ohne `version`. Antworten mit `oneOf` (Zimmer: Voll/Team) werden am Feld `plaetze` unterschieden. Der Teilnehmenden-Eintrag kennt den Cevi-Namen nur in der Vollansicht; im Schichtplan zeigt `name` bei Teilnehmenden nie den Cevi-Namen.

## Schnitt A4 Im Lager: Datenschicht (Issue #67)

Gebaut, ohne Bildschirme und ohne lokalen Speicher. Alle neuen Modelle sind `Codable` (auch `CampTask`, `CampShift`, `CampDuty`, `CampMeetingView` und weitere, die «Heute» enthält), damit ein späterer Zwischenspeicher sie so ablegen kann, wie sie vom Server kommen (`JSONEncoder.api` und `JSONDecoder.api` sind Gegenstücke). Das Notfall-Fenster ist eine Antwort (`campEmergency`): Adresse, Kontakte mit Telefon, Info-Abschnitte mit Merkmal «Notfall». Die Route zur Lageradresse liefert `CampEmergencyAddress.routeURL` (gespeicherter Kartenlink, sonst Apple Karten mit dem Adresstext). Telefonnummern und Adressen gehören nur in diese Modelle und in Bildschirme der Mitglieder. Das Wetter kennt nur den Ort des Lagers (Breite, Länge), keine Personendaten.

Anwesenheit: Das Team trägt offene Felder bis zur Frist direkt ein (`setOwnCampAttendance`, «ganzer Tag» mit `CampAttendanceField.wholeDay`). Ist ein Feld schon gesetzt oder die Frist vorbei, schreibt der Server nichts und antwortet 409 `ANFRAGE_NOETIG`; `CampRules.attendanceBlocked` liefert die Felder mit Grund, dann folgt die Anfrage (`requestCampAttendanceChange`). Die Lagerleitung entscheidet getrennt (`decideCampAttendanceRequests`, Annehmen setzt das Feld) und überschreibt Felder jederzeit (`setCampAttendance`).

| Was | Route (unter `/api/v1/lager/{id}`) | Code |
| --- | --- | --- |
| Matrix (Seiten, Filter Lagertage), Zusammenfassung | `GET …/anwesenheit`, `…/anwesenheit/zusammenfassung` | `CampAttendancePage`, `CampAttendanceSummary` |
| Lagerleitung trägt ein, Frist | `PUT …/anwesenheit`, `PUT …/anwesenheit/frist` | `setCampAttendance`, `setCampAttendanceDeadline` |
| Eigene Anwesenheit und Anfragen, eintragen | `GET`/`PUT …/anwesenheit/eigene` | `CampOwnAttendance`, `setOwnCampAttendance` |
| Anfragen: stellen, auflisten, entscheiden | `POST`/`GET …/anwesenheit/anfragen`, `POST …/anfragen/entscheid` | `CampAttendanceRequest*`, `decideCampAttendanceRequests` |
| Tagesseiten (Tageschef, Notiz), Tag lesen mit Blöcken, Wetter, To-dos | `GET …/tagesseiten`, `GET`/`POST`/`PATCH …/tagesseiten/{lagertagId}` | `CampDayPage*`, `CampDayPageDetail` (To-dos des Tages sind die Aufgaben mit Frist an dem Tag) |
| Blöcke (Wichtig, Idee, Programmbild) | `POST …/bloecke`, `PATCH`/`DELETE …/bloecke/{id}` | `CampDayBlock*` |
| Wetter lesen, Ort setzen | `GET …/wetter`, `PUT …/wetter/ort` | `CampWeather`, `setCampWeatherPlace` |
| Heute, Meine Woche | `GET …/heute`, `GET …/meine-woche` | `CampToday`, `CampMyWeek` (Teile `nil` ohne Leserecht, 403 ohne lesbaren Teil) |
| Einkauf (Filter `einkaeufer`=`ich` oder ID, `erledigt`), zusammengezählt, Vorschläge | `…/einkauf`, `…/einkauf/zusammen`, `…/einkauf/vorschlaege`, `…/einkauf/{id}` | `CampShopping*`, `CampShoppingPage.byGroup` (nach Warengruppe) |
| Packliste: Vorlage, Zustand abhaken, eigene Punkte | `…/packliste`, `…/packliste/punkte`, `PUT …/punkte/{id}/zustand`, `…/packliste/eigene` | `CampPackingList`, `setCampPackingState`, `CampOwnPackingPoint*` |
| Notfall-Fenster, Kartenlink, Kontakte | `GET …/notfall`, `PUT …/notfall/karte`, `…/notfall/kontakte` | `CampEmergency`, `CampEmergencyContact*`, `setCampMapLink` |
| Infos (Abschnitte, Reihenfolge) | `…/infos`, `…/infos/{id}`, `PUT …/infos/reihenfolge` | `CampInfo*` |
| Start der Lagerleitung | `GET …/start` | schon in A1 (`CampStart`) |

Hinweise: Die Antworten tragen kein `aktionen`-Feld; Zeilen mit `version` richten die Knöpfe nach der Rolle (403 sonst). Die Einkaufs-Zeile «zusammen» nennt ihre Artikel mit `id` und `version`. Eigene Packlisten-Punkte tragen keine `version`. Die Konflikt-Antworten `KEINE_ANFRAGE_NOETIG` (Felder), `ANFRAGE_OFFEN` (Felder) und `BEREITS_ENTSCHIEDEN` (IDs) haben in der Beschreibung keine Form für ihre Zusatzfelder; die App liest nur den Fehlercode (`CampRules`).

## Schnitt A5 Ablage und Querschnitt: Datenschicht (Issue #69)

Gebaut, ohne Bildschirme und ohne lokalen Speicher. Dateien sind in dieser API **keine signierten Adressen und keine Bytes**: `…/dateien` speichert nur eine `https`-Verknüpfung auf den Ablageort (SharePoint der Abteilung), der Server ruft sie nie ab. Die App öffnet den Link über das System (`CampFileRef.openableLink`, nur `https`) und lädt nichts selbst; der Link wird nicht protokolliert und nicht zwischengespeichert. Eine Prüfung «gleiche Herkunft wie die Basis-URL» passt hier nicht, der Ablageort liegt per Definition woanders. Das Adressbuch (`CampContact`) trägt Name, Telefon, E-Mail und Notiz Dritter: nie in Widgets, Logs oder Absturzberichten. Die Suche liefert nur Felder des Schemas (Art, ID, Titel, Auszug); die Rollen filtert der Server. Schreib-Routen tragen `version`; Konflikte wie in A1 (`CampRules.versionConflict`); abgelehnte Links: `CampRules.linkInvalidCode`, `linkHostNotAllowedCode`.

| Was | Route (unter `/api/v1/lager/{id}`) | Code |
| --- | --- | --- |
| Datei-Verknüpfung anlegen, lesen, löschen | `POST …/dateien`, `GET`/`DELETE …/dateien/{id}` | `CampFileCreate`, `CampFileRef`, `createCampFile`, `campFile`, `deleteCampFile` |
| Dokumente (Filter `q`, `stichwort`, `typ`; Seiten) | `GET`/`POST …/dokumente`, `GET`/`PATCH`/`DELETE …/dokumente/{id}` | `CampDocument*`, `CampDocumentFilter`, `campDocuments` ff. Dateien anderer Module haben `version` = `nil` |
| Adressbuch (nur Lagerleitung; `behalten`, `aufraeumenAb`) | `GET`/`POST …/adressbuch`, `GET`/`PATCH`/`DELETE …/adressbuch/{id}` | `CampContact*`, `campContacts` ff. |
| Suche (Volltext, nach Rolle gefiltert, Filter `typ`) | `GET …/suche` | `CampSearchResult`, `CampSearchType`, `searchCamp` |
| Aushänge als PDF | `GET …/aushaenge/{art}` | schon in A2 (`campHandout`) |

Hinweise: `APIClient.send` gibt nur den Rumpf zurück, nicht die Kopfzeilen; für den Aushang ist der Dateiname deshalb `<art>.pdf` (so beschreibt ihn die API). Die Dokumentenliste ist eine Sammelabfrage über mehrere Module (`quelle`).

## Schnitt A0b Sync: Datenschicht (Issue #71)

Backend L0c und L0d sind da (Stand der Kopie `f8d55c5`). Gebaut, ohne Bildschirme und ohne lokalen Speicher:

| Was | Route (unter `/api/v1/lager/{id}`) | Code |
| --- | --- | --- |
| Änderungen senden (Stapel bis 100, idempotent über `clientOpId`; je Änderung `ok`, `konflikt`, `abgelehnt`) | `POST …/aenderungen` | `CampOperation`, `CampOperationResult`, `sendCampOperations` |
| Ereignisstrom im Vordergrund (nur «Es gibt Neues» und Folgenummer) | `GET …/ereignisse` (`Last-Event-ID`) | `CampEventParser`, `CampLiveEvent`, `campEvents` |
| Warteschlange im Arbeitsspeicher | nutzt `POST …/aenderungen` | `CampOutbox`, `CampOutboxStore`, `CampOutboxMemoryStore` |
| Konfliktauflösung (`keepMine`, `keepCurrent`, `merge`) | Folge-Aufruf: neue `clientOpId` und aktuelle `version` | `CampConflictChoice`, `CampOperation.resolved`, `CampOutbox.resolve` |

Hinweise:

- Die API kennt für das Senden nur `ok`, `konflikt`, `abgelehnt`. «Schon angewendet» ist kein eigener Status: Eine Wiederholung mit derselben `clientOpId` liefert das gespeicherte `ok`.
- Die Beschreibung nennt weder die `typ`-Werte (ausser dem Beispiel `aufgabe.aendern`) noch die Felder der `nutzlast`. Der Code trägt sie als `[String: CampJSON]`. Annahme: Das Versionsfeld der Nutzlast heisst `version` (wie in den PATCH-Körpern); wer eine Operation baut, prüft das gegen die Module.
- `keepCurrent` verwirft den Eintrag, `keepMine` und `merge` ersetzen ihn durch einen neuen `waiting`-Eintrag. So verlangt es die Beschreibung («neue `clientOpId` und die aktuelle `version`»). Ein Konflikt oder eine Ablehnung verschwindet nie ohne Entscheid der Person.
- Ganze Anfrage abgelehnt (400, 403, 404, 409 `LAGER_GESCHLOSSEN`, 410, 413): die Einträge dieser Anfrage werden `rejected`. Netz, 401, 426, 429 und 5xx lassen sie `waiting`.
- Der Strom hat eine eigene Sitzung (`APIClient.makeSession(streaming: true)`), sonst gleich geschützt. Zeitgrenze: 75 s ohne Daten (der Server schickt alle 25 s einen Herzschlag) statt 30 s je Anfrage. Wiederverbinden macht der Aufrufer: Strom endet nach `ende` oder bei Verbindungsende; dann `campEvents(campId:lastEventId:)` mit dem letzten `upTo` und den Feed ab dort lesen. 429 `ZU_VIELE_VERBINDUNGEN` kommt als `APIError` mit `retryAfter`.
- Der Strom läuft nur im Vordergrund; der Hintergrund (Push) ist nicht gebaut.

## Schnitt B0 Navigation, Lagerwahl, übergreifende Zustände: Bildschirme (Issue #80)

Gebaut (Boards A8, A9, A10, L1, L37, U1 bis U8):

| Was | Code |
| --- | --- |
| Umschalter Programm-/Lager-Ansicht oben links, nur wenn `GET /api/v1/lager` mindestens ein Lager liefert | `CampSwitcher.swift` (`.campSwitcher()`), `CampListModel.showsSwitcher` |
| Aktives Lager (Rolle, Titel, `isReadOnly`, Warteschlange), nur im Arbeitsspeicher | `ActiveCamp.swift`, in der Umgebung von `MainView` |
| Lager-Tab-Leiste: Start (vorläufig: Lagerkopf und Banner), Chat (wie bisher), Mehr | `CampTabView.swift` |
| L1 Lagerwahl (Normal, Laden, Leer, Fehler) | `CampChooserView.swift`, `CampListModel.swift` |
| L37 Mehr (Sheet): Profil, Alle Lager | `CampMoreSheet.swift` |
| U1 bis U4 (Zuordnung `APIError` zu Zustand), U6 Banner, U7 Konflikt, U8 Banner | `CampScreenState.swift`, `CampBanners.swift`, `CampConflictView.swift` |
| U5 Lädt länger (nach 5 s zweite Zeile im Overlay) | `BusyState.isSlow`, `BusyOverlay(slow:)` |
| Push `lager_*` öffnet das Lager | `CampRouter.swift` (404 beim Auflösen zeigt U3) |

Nicht gebaut, weil das Ziel fehlt (kein totes Ziel in der Tab-Leiste und im Mehr-Sheet): Tabs Aufgaben und Pinnwand; Mehr-Einträge Hoecks, Anwesenheit, Zimmer und Zelte, Fahrten, Programmgruppen, Diensttausch, Abzählen, Tagesseiten, Einkaufsliste, «Als Team ansehen», Einstellungen, Feedback zur App; U6 als eigener Bildschirm «Änderungen» (Liste der Warteschlange; nur das Banner ist da); U7 «Beide ansehen» (Zusammenführen von Hand).

## Schnitt B1 Start und Aufgaben: Bildschirme (Issue #82)

Gebaut (Boards L2, L3, L5, L7, L8, L9, L10, L35, T1, T3) mit den Zuständen Normal, Leer, Laden, Fehler, Ohne Netz, Lager abgeschlossen, ohne Recht, Konflikt, Eingabefehler, Aktion läuft:

| Was | Code (`Screens/Camp/Start`, `Screens/Camp/Tasks`) |
| --- | --- |
| L2 Start Lagerleitung (Countdown, Fortschritt, «Für dich», nächster Hoeck), L3 Start Team (Dienste, Aufgaben, nächster Hoeck) | `CampStartModel`, `CampStartView` (`GET …/start`, `GET …/meine-woche`) |
| L5 Liste (Liste, Meine, Personen, Ressort; Sortieren, Filter lokal) und T1 Kanban | `CampTasksModel`, `CampTasksView`, `CampTaskRow` |
| L9 Mehrfachauswahl (Fertig, Status, Frist, Ressort, Löschen; «Rückgängig» für Status) | `CampTasksModel` (je Aufgabe ein Aufruf, es gibt keine Sammelroute) |
| L7 Aufgabe Detail (Status, Stern, Frist, Ressort, Wiederholung, Checkliste mit Nach oben/unten, Links, Notiz, Verlauf, Löschen) | `CampTaskDetailModel`, `CampTaskDetailView` |
| L8 Schnelleingabe und L10 Duplikat-Hinweis (Zusammenführen: Aufgabe anlegen, dann `…/zusammenfuehren`) | `CampQuickEntryModel`, `CampQuickEntryView` |
| L35 Ressort-Seite (Verantwortliche, Notizen) | `CampPortfolioModel`, `CampPortfolioView` |
| T3 Zeitplan und Kalender (Meilensteine und Fristen, Monatsraster) | `CampScheduleModel`, `CampScheduleView` |
| Rechte nach Rolle, gemeinsames Schreiben mit Konflikt und Warteschlange | `CampTaskRights`, `CampTaskWriter` (`CampTaskSupport.swift`) |

Hinweise:

- Rechte: Lagerleitung alles. Leitung: anlegen, ändern, Status, nicht löschen und nicht zusammenführen. Team: nur der Status der eigenen Aufgaben. Lesen: nichts. Fehlende Aktion ist ein fehlender Knopf. Das ist eine Annahme aus dem Entwurf und der Beschreibung (die Matrix darf nur die Lagerleitung lesen); der Server entscheidet am Ende.
- Statusänderung läuft über `CampOutbox` (`aufgabe.aendern`), aber nur als Rückfall bei fehlendem Netz: erst der direkte Aufruf `PUT …/status`. Die Nutzlast `{id, version, status}` ist eine Annahme (die Beschreibung nennt die Felder nicht). Abgelehnte Einträge der Warteschlange zeigt noch kein Bildschirm.
- Alle anderen Schreibaufrufe gehen direkt über den Dienst, weil die Beschreibung ihre `typ`-Werte nicht nennt.
- Aufgaben-Tab nur für Lagerleitung und Leitung; Team und Lesen sehen ihre Aufgaben auf dem Start (`meine-woche`). Der Entwurf zeigt für das Team keinen Aufgaben-Tab.
- Zeitplan und Kanban liegen im Aufgaben-Tab unter dem Menü «Ansicht» (der Entwurf nennt keinen Einstieg). Der Zeitplan liest nur die erste Seite (100) der Aufgaben.
- Ziehen (Kanban, Checkliste) ist nicht gebaut; die sichtbare Alternative («Verschieben nach», «Nach oben/unten») ist die einzige Bedienung.

Nicht gebaut oder weggelassen, weil die API es nicht hergibt oder das Ziel in einem anderen Schnitt liegt:

- L2: Hinweiskarte «Samstag Gewitter möglich» (Pinnwand), Knöpfe «Notiz», «Protokoll», «Mitteilung», Block «Neu für dich» (Benachrichtigungen mit Text). «7 für dich» ohne Zahl: «Für dich» zeigt die eigenen offenen Aufgaben der nächsten sieben Tage.
- L3: Zimmer, Fahrt, Gruppe, Ressorts, Packliste, «Seit deinem letzten Besuch», «Feedback an die Lagerleitung» (andere Schnitte). Tab-Leiste: Pinnwand und Anwesenheit fehlen bis zu ihren Schnitten.
- L5/T1: «Checkliste 2 von 4» in der Liste (die Liste hat keine Zähler, nur das Detail), «Wartet» als eigene Gruppe in der Liste, Wischgeste zum Wechseln der Spalte als echtes Blättern (es gilt ein Wisch auf der Liste und die Chips).
- L7: Verantwortliche und Unterstützung ändern (keine Mitgliederliste für Nicht-Admins, siehe A3), Links hinzufügen, Zurückholen früherer Fassungen (L0e), «Beide ansehen» im Konflikt. Konflikt bei Checklisten-Punkten: Die Ansicht lädt neu und zeigt den Fehlertext.
- L8: «Ohne Netz» (Aufgabe wartet): Die Vorschläge brauchen Netz, und die Beschreibung nennt keinen `typ` zum Anlegen.
- L9: «Person» (keine Mitgliederliste).
- L35: «Dokumente, 3», «Feedback, 1 neu» (andere Schnitte).
- T3: Hoeck im Zeitplan und im Kalender, Hinweis «Ruhige Ressorts» (Regel nicht beschrieben); Meilensteine anlegen und verschieben (der Entwurf zeigt es nicht).
- L5-G: Name der Lagerleitung im Text («Wende dich an Mara») ist nicht bekannt.

## Schnitt B2 Sitzungen und Kommunikation: Bildschirme (Issue #84)

Gebaut (Boards L11 bis L19) mit den Zuständen Normal, Leer, Laden, Fehler, Ohne Netz, Lager abgeschlossen, ohne Recht, Konflikt, Eingabefehler, Aktion läuft:

| Was | Code (`Screens/Camp/Meetings`, `Screens/Camp/Communication`) |
| --- | --- |
| L11 Hoeck-Liste (Kommend, Vergangen, «Neuer Hoeck», «Wie der letzte») | `CampMeetingsModel`, `CampMeetingsView` |
| L12 Traktandenliste (Nach oben/unten, «Auf nächsten Höck» mit Rückgängig, wartende übernehmen, bearbeiten) | `CampAgendaModel`, `CampAgendaView` |
| L13 Protokoll (Zeile speichern, Anwesende, Traktanden mit Entscheid, Beschlüsse, Konflikt) | `CampProtocolModel`, `CampProtocolView` |
| L14 Hoeck-Modus (Anwesende abhaken, Traktanden besprochen, Ressort-Runde) | `CampMeetingModeModel`, `CampMeetingModeView` |
| L15 Erwähnungen («Als Aufgabe», «Erledigt») | `CampMentionsModel`, `CampMentionsView` |
| L16 Pinnwand (Tab; Wichtig, Anheften, Zeitfenster, Dateien als Verweis, Umfrage, Reaktionen) | `CampNoticesModel`, `CampNoticesView` |
| L17 Mitteilung mit Umfrage (Empfänger nach Rolle, Optionen, Sichtbar bis) | `CampNoticeFormModel`, `CampNoticeFormView` |
| L18 Eingang (Antworten, Ressort zuweisen, «Als Traktandum» mit Rückgängig, Status, Löschen) | `CampInboxModel`, `CampInboxView` |
| L19 Benachrichtigungen (Neu, Einstellungen je Art) | `CampNotificationsModel`, `CampNotificationsView` |
| Rechte nach Rolle, Schreiben mit Konflikt | `CampCommsRights`, `CampCommsWrite` (`CampCommsSupport.swift`) |

Navigation: Pinnwand ist ein Tab; Hoecks, Erwähnungen, Eingang (nur Lagerleitung), Benachrichtigungen liegen im Mehr-Sheet. Ein Push `lager_pinnwand`, `lager_erwaehnung` oder `lager_eingang` öffnet das Ziel (`ActiveCamp.destination`). Datenschicht neu: Schalter der Benachrichtigungen (`GET`/`PUT /api/v1/ich/lager-benachrichtigungen`, `campNotificationSettings`); die Arten `diensttausch_anfrage`, `diensttausch_entscheid`, `adressbuch_aufraeumen` fehlten in `CampNotificationKind` (die Art `diensttausch` gibt es in der API nicht).

Abweichungen vom Entwurf:

- Rechte: Annahme nach den Standardwerten der Matrix (Hoecks, Protokolle, Pinnwand bearbeiten: Lagerleitung und Leitung; Stimmen und Reaktionen: auch Team; Eingang lesen und antworten: nur Lagerleitung). Der Server entscheidet am Ende.
- L13: Die API hat keine Abschnitte und keinen Protokolltext. Der Bildschirm zeigt die Zeile (Titel, Art, Datum) zum Speichern, dazu Anwesende, Traktanden mit Entscheid und Beschlüsse. Nicht gebaut: «Lea schreibt gerade hier», gesperrter Abschnitt, To-dos, «Als Word», «Für den Kalender» (eine Datei ohne lokalen Speicher), «Beide ansehen». Ein Protokoll lässt sich nicht anlegen (braucht eine Datei, L0g).
- «Ohne Netz» (Wartet): Für diese Änderungen kennt die Beschreibung keine Warteschlangen-Operationen (L0c). Ein Schreibfehler zeigt «Das hat nicht geklappt. Deine Eingabe ist noch da.»; Lesen zeigt den Stand und den Hinweis «Ohne Netz».
- L12: Ziehen nicht gebaut (nur Pfeile). «Aus Aufgaben hinzufügen» fehlt.
- L14: Die Ressort-Runde zeigt Zahlen je Ressort (die API liefert keine Aufgaben darin); die Knöpfe «Erledigt», «Läuft», «+1 Woche», «Verantwortliche ändern» fehlen.
- L15: «Als Aufgabe» ohne «Rückgängig» (Löschen der Aufgabe braucht deren Version).
- L16: «18 gesehen» (keine Lesezahl in der API); «Text für WhatsApp kopieren» heisst «Text teilen» (Teilen-Blatt, kein UIKit). Dateien nur als Link anzeigen, nicht hinzufügen (L0g).
- L17: Empfänger nur nach Rolle (Leitung, Team, Lesende), keine Gruppen oder Personen (keine Mitgliederliste, L4).
- L18: Die API liefert nur den Tag, daher «anonym, heute» ohne Uhrzeit. Das Senden durch das Team (Feedback, Rückfrage mit Code) ist nicht gebaut; der Entwurf zeigt nur den Eingang der Lagerleitung.
- L19: Zeilen tragen keinen Text und keine Namen; der Text kommt aus der Art («Jemand hat dich erwähnt.»). Tippen auf eine Zeile öffnet das Ziel nicht (nur «Gelesen»). Einstellungen: ein Schalter je bekannter Art; der Entwurf zeigt den Reiter nicht, die Liste folgt der API.
- Kein Zeilenzähler «3» am Pinnwand-Tab (kein Lagerzähler für die Pinnwand).

## Offene Fragen zum Entwurf

- L1: «62 Prozent erledigt, 4 überfällig» braucht `GET …/start` je Lager; «Übungslager» (Abschnitt, Chip «Übung») hat kein Feld in der API. Beides fehlt in der App.
- A10: Untertitel «Cevi Beispielstadt» (Abteilungsname) und die Zahl «3 neu» am Lager (ungelesene Benachrichtigungen je Lager) sind nicht angeschlossen; der Umschalter zeigt «Programme».
- U7: Der Name der Person, die zuletzt geändert hat («Lea hat …»), steht nicht in der Konflikt-Antwort; der Titel kommt vom Aufrufer.
- U4: Die Endzeit der Wartung («bis 22:00») liefert die API nicht; der Text nennt sie nicht.

## Route fehlt (blockiert)

| Gebraucht für | Fehlt | Backend-Issue |
| --- | --- | --- |
| A0b: Namen der `typ`-Werte und Nutzlast-Felder der Operationen | Beschreibung nennt nur das Beispiel `aufgabe.aendern`; Module melden ihre Operationen an | L0c |
| Papierkorb, Verlauf, Fassungen | Revisionen | L0e |
| Dateien (Dokumente, Bilder) | Lager-Dateien im Medienspeicher | L0g |
| A1: Lager-Check «Sind wir bereit?» | keine Route in der Beschreibung | L1 |
| A1: Vorlagen auflisten (Auswahl für `anwenden`) | nur `/api/v1/admin/vorlagen` (Admin), die App ruft Admin nie auf | L1 |
| A1: frühere Fassungen einer Aufgabe, Zurückholen | Verlauf kennt nur Art, Version, Zeitpunkt; keine Inhalte | L0e |
| A2: Protokoll-Abschnitte (Text im Protokoll) | nur Zeile mit Dateiverweis, kein Inhalt, keine Abschnitte | L2 |
| A2: Dateien zum Hochladen (Pinnwand, Protokoll) | `dateiIds` setzen vorhandene Dateien voraus, Hochladen: Lager-Dateien | L0g |
| A2: Reaktionen auf anderes als Pinnwand | `zielTyp` kennt nur `pinnwand_beitrag` | L3 |
| A3: Namen der Mitglieder (Schichtplan, Diensttausch, Gruppen-Auswahl) | Liste der Lagermitglieder für Nicht-Admins; `…/lager/{id}/mitglieder` gibt es nur unter `/api/v1/admin` (die App ruft Admin nie auf). Schichten tragen `name`, ein Tausch nur `personId`s | L4 |
| A3: Tauschanfrage mit Namen, Zimmer-Namen der Teilnehmenden im Team | Tausch liefert keine Namen und keine Schicht-Details; Fahrer nur als `fahrer.name` | L4 |
| A4: Namen der Anwesenheits-Matrix, des Tageschefs im Team und der Einkäufer-Auswahl | Matrix nennt nur IDs (Mitglieder und Teilnehmende löst die App über Listen auf); Mitglieder-Liste fehlt für Nicht-Admins | L4 |
| A5: Wissen früherer Lager übernehmen | keine Route in der Beschreibung | L6 |
| A5: Papierkorb ansehen, Wiederherstellen, Verlauf (ausser `…/aufgaben/{id}/verlauf`) | keine Routen (Löschen ist weich, aber nicht abrufbar) | L0e |
| A5: Exporte als Word und Excel | nur Aushänge als PDF (`…/aushaenge/{art}`) | L7 |
| A5: Dateien hochladen oder per signierter Adresse laden | nur Verknüpfungen auf den Ablageort, keine Bytes | L0g |

Nicht ableitbar: Welche Rechte die eigene Rolle hat. Die Matrix darf nur die Lagerleitung lesen. Die Aufgaben-Routen sollen laut Auftrag die erlaubten Aktionen in der Antwort liefern (fehlt die Aktion, fehlt der Knopf).

## Entscheide, die der Auftraggeber treffen muss

1. Lokaler Speicher für das Lager (SwiftData, mit Dateischutz) für Offline-Lesen und die Warteschlange (`CampOutbox` liegt bis dahin nur im Arbeitsspeicher hinter `CampOutboxStore`). Widerspricht `docs/architektur.md` (Serverdaten nur im Arbeitsspeicher).
2. Zwischenspeicher für Widgets (App-Gruppe), nötig erst für A7.
3. Design-Entwurf «Cevi Lager iOS» liefern (Bildschirme erst danach).
