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
| Wetter lesen (Ort bestimmt der Server aus dem Lagerort, `Camp.weatherPlace`) | `GET …/wetter` | `CampWeather`, `CampWeatherPlace` |
| Mitglieder mit Anzeigenamen (Recht `einteilung.lesen`) | `GET …/mitglieder` | `campMembers`, `ActiveCamp.memberNames` |
| Vorlagen als Auswahl (Recht `vorlagen.anwenden`) | `GET …/vorlagen` | `campTemplates` |
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

## Schnitt B3 Einteilung: Bildschirme (Issue #86)

Gebaut mit den Zuständen Normal, Leer, Laden, Fehler, Ohne Netz (Hinweis «Ohne Netz» mit Stand), Fehler beim Speichern, ohne Recht («Nur lesen.»), Lager abgeschlossen, Textgrösse AX3, Tag und Nacht (Vorschauen):

| Was | Code (`Screens/Camp/Roster`) |
| --- | --- |
| L20 Zimmer und Zelte (Belegung, «Nicht eingeteilt», «Person zuweisen», «Herausnehmen», Überbelegung als Wort) | `CampRoomsModel`, `CampRoomsView` |
| L21 Fahrten (Hin-/Rückfahrt, Mitfahrende einteilen und herausnehmen, «Fahrplan öffnen» nur für `https`) | `CampTripsModel`, `CampTripsView` |
| L22 Programmgruppen («Automatisch mischen»: Vorschau, «Neu mischen», «Übernehmen» mit demselben `seed`) | `CampGroupsModel`, `CampGroupsView` |
| L24 Diensttausch (entscheiden, zurückziehen, «Tausch anfragen») | `CampSwapsModel`, `CampSwapsView` |
| L25 Abzählliste (gemeinsame Haken, Filter, Rückmeldung bei gleichzeitigem Abhaken, Zurücksetzen mit Rückgängig) | `CampCountModel`, `CampCountView` |
| T2 Schichtplan (Liste je Tag, «Person wählen», «Leere Dienste füllen» als Vorschlag, «Verteilung», «Dienst anlegen»; VoiceOver liest je Dienst einen ganzen Satz aus `CampShiftText`) | `CampShiftsModel`, `CampShiftsView` |
| Rechte nach Rolle, gemeinsame Bausteine | `CampRosterRights`, `CampRosterModel`, `CampPersonPicker` (`CampRosterSupport.swift`) |

Navigation: Alle sechs Einträge liegen im Mehr-Sheet (Abschnitt «Einteilung»); der Entwurf zeigt sie unter «Mehr», nicht als Tab. Ein Push `lager_einteilung` öffnet den Diensttausch (die Benachrichtigungen der Einteilung sind Tauschanfragen und -entscheide; `CampRouter`).

Abweichungen vom Entwurf:

- Rechte (Annahme, der Server entscheidet am Ende): Einteilen in Zimmer, Fahrten, Gruppen und Tausch entscheiden nur die Lagerleitung; Schichten bearbeitet auch die Leitung; Abhaken: Lagerleitung, Leitung, Team; Zurücksetzen: Lagerleitung, Leitung. Fehlende Aktion ist ein fehlender Knopf.
- Namen: Wo die API nur `personId` liefert, steht «Person». Der Diensttausch löst Namen über die Schichten des Schichtplans auf. «Person wählen» (Schichten) bietet nur Personen aus der Statistik des Plans und die Leitenden der Gruppen an (Mitgliederliste fehlt, B1). Offene Anfragen ohne Gegenüber lassen sich nicht annehmen (man müsste die übernehmende Person wählen), nur ablehnen.
- Ohne Netz: «Wartet» an einzelnen Zeilen fehlt, die Warteschlange kennt für diese Änderungen keine Operationen (L0c). Es erscheinen Warteschlangen-Banner und Stand-Hinweis.
- L24 «Rückgängig» nach Annehmen fehlt (die API kennt keine Rücknahme einer Entscheidung). L25 «Rückgängig» nach Zurücksetzen setzt die vorher gesetzten Haken wieder.
- L25: Filter «Leitung» ist die Art Team; die weiteren Chips sind die Programmgruppen (der Entwurf nennt «Wölfe», «Adler»). Die Stufe ist kein Filter.
- L22: «Vorschau: gemischt» ohne «nach Stufe» (die API nennt das Kriterium nicht).
- T2: Ziehen nicht gebaut (Board T2-D); die Alternative «Person wählen» ist die einzige Einteilung. Der Vorschlag gilt für alle Lagertage und hat die Schalter «Nur Anwesende» und «Auch Teilnehmende» (Optionen der API).
- Neu ohne Board: «Tausch anfragen» (eigener Dienst, Notiz), «Verteilung» (Statistik), «Dienst anlegen» wie im Leerzustand des Entwurfs.

Nicht gebaut: Anlegen, Bearbeiten und Löschen von Zimmern, Zelten, Fahrten und Gruppen (kein Board im Entwurf; die Texte der Leerzustände nennen es trotzdem), Zuordnung einzelner Teilnehmender zu Gruppen, Abwählen, Import der Teilnehmenden, Konfliktbildschirm für diese Boards (Konflikt zeigt «Jemand hat das gerade geändert» und lädt neu), Board L23 (heisst jetzt T2).

## Schnitt B4 Im Lager: Bildschirme (Issue #88)

Gebaut mit den Zuständen Normal, Leer, Laden, Fehler, Ohne Netz, Aktion läuft, Fehler beim Speichern, Rückgängig, Anfrage nötig, ohne Recht, Lager abgeschlossen, Textgrösse AX3, Tag und Nacht (Vorschauen):

| Was | Code (`Screens/Camp/OnSite`) |
| --- | --- |
| L4 Heute (Dienst mit Zeit, «Wichtig heute», eigene To-dos abhaken, Knopf «Notfall») | `CampTodayModel`, `CampTodayView` |
| L26 Anwesenheit (Tag wählen, «Ganzer Tag da», Da/Frei je Abschnitt im Menü, Anfrage bei gesetztem Feld oder nach der Frist, Entscheid der Lagerleitung) | `CampAttendanceModel`, `CampAttendanceView` |
| L27 Tagesseite (Tageschef, Wetter, Wichtig, Ideen, Programmbild, Notiz, To-dos, «In den nächsten Tag schieben») und Liste der Tage | `CampDayPageModel`, `CampDayPageView` |
| L28 Einkaufsliste (nach Abteilung, «Nur was ich einkaufe», Abhaken mit Rückgängig, «Artikel hinzufügen» mit Vorschlägen) | `CampShoppingModel`, `CampShoppingView` |
| L29 Packliste (abhaken, eigene Punkte, Punkt hinzufügen) | `CampPackingModel`, `CampPackingView` |
| L30 Notfall (Rettung 144 und 1414, Kontakte, Route; ohne Netz der zuletzt geladene Stand aus dem Arbeitsspeicher) | `CampEmergencyModel`, `CampEmergencyView`, `ActiveCamp.emergencySnapshot` |
| L32 Infos (Abschnitte, Links, «Sortieren» mit «Nach oben»/«Nach unten») | `CampInfosModel`, `CampInfosView` |
| Wetterwarnung auf L2 («Samstag Gewitter möglich.») und «Heute»-Karte im Start-Tab | `CampStartModel.weatherWarning`, `CampStartView` |
| Rechte nach Rolle, gemeinsame Bausteine | `CampOnSiteRights`, `CampTodoModel`, `CampOnSiteSupport.swift` |

Navigation: «Heute» ist die erste Karte im Start-Tab, solange das Lager läuft. «Anwesenheit» ist für das Team ein Tab (wie im Board L3), für die Lagerleitung ein Eintrag im Mehr-Sheet. «Tagesseiten», «Einkaufsliste» (nur Lagerleitung und Leitung), «Packliste», «Notfall» und «Infos» stehen im Mehr-Sheet (Abschnitt «Im Lager»). Ein Push `lager_anwesenheit` öffnet die Anwesenheit (`CampRouter`, `ActiveCamp.destination`).

Datenschutz: Kindernamen und Telefonnummern stehen in keinem Log. Anrufen und Route öffnen nur über `Link` mit `phoneURL` und `routeURL`. Der Notfall-Stand liegt nur im Arbeitsspeicher und wird beim Verlassen des Lagers verworfen. Das Wetter kennt nur den Ort.

Abweichungen vom Entwurf:

- Rechte (Annahme, der Server entscheidet am Ende): Matrix lesen und für alle setzen, Anfragen entscheiden, Packliste-Vorlage schreiben und Infos sortieren nur die Lagerleitung; Anwesenheit setzt auch Leitung und Team für sich selbst; Einkaufsliste sehen und ändern Lagerleitung und Leitung (die API antwortet dem Team mit 403); Packliste abhaken alle ausser «Lesen».
- L4: «Dein Dienst» führt in den Schichtplan; die Zeit kommt aus dem Tagesabschnitt (`zeit`), ohne Zeitplan steht nur der Dienstname. Zusätzlich «Tagesseite» als Link. Das Board zeigt kein Wetter, L4 auch nicht.
- L26: Namen der Matrix kommen aus der Abzählliste (Art Team), sonst «Person». Teilnehmende stehen nicht in der Matrix. Die Boards zeigen keine Anfragen der Lagerleitung; sie stehen als Karten «Anfrage» mit «Annehmen»/«Ablehnen» über der Matrix. Das Board «Versionskonflikt» ist der Dialog «Anfrage an die Lagerleitung nötig» (Text: «…schon etwas eingetragen»); ein echter 409 `VERSION_KONFLIKT` lädt die Liste neu. «Wartet» an Zellen fehlt (keine Operation in der Warteschlange, L0c), wie in B3.
- L27: Der Block «Tagesprogramm» (Uhrzeiten) und «Fotos vom Tag, 14 Bilder» haben keine Quelle in der API; gezeigt werden Tageschef, Wetter, Wichtig, Ideen, Programmbilder (als Link), Notiz und To-dos. Der Leerzustand sagt nicht «Trage … ein» (Bearbeiten ist nicht gebaut). «Wartet» gilt nur fürs Abhaken.
- L28: Abteilungsnamen wie im Board («Früchte und Gemüse», «Trockenes», «Milch»; `CampShoppingGroup.title` angepasst). «Wartet» an Artikeln und die Schaltfläche oben rechts fehlen. Der Hinweis «Reis, 12 kg vorhanden» kommt aus der geladenen Liste, die Vorschläge vom Server.
- L29: «Vorlage übernehmen» fehlt (keine Route für Vorlagen, L1). Die Lagerleitung fügt der Vorlage Punkte hinzu, alle anderen fügen eigene Punkte hinzu. «Wartet» fehlt.
- L30: Der Text ohne Netz lautet «Das ist der zuletzt geladene Stand. Anrufen geht trotzdem.» (nicht «auf dem Gerät gespeichert»: es gibt noch keinen lokalen Speicher). Ohne bisherigen Stand und ohne Netz zeigt der Bildschirm den Fehlerzustand, nicht die Nummern. Zusätzlich «Wichtig im Notfall» (Infos mit Merkmal «Notfall»). Die Nummern 144 und 1414 stehen fest im Code (öffentliche Notrufnummern).
- L32: «Gesperrt wegen Rolle»: Der Hinweis erscheint für alle ausser Lagerleitung und Leitung. Ziehen ist nicht gebaut, nur «Nach oben»/«Nach unten» (Knopf «Sortieren»). «Wartet» fehlt.
- L2: Die Wetterwarnung zeigt nur den ersten Satz des Boards; «Plane das Waldspiel mit Ausweichort.» hat keine Quelle.

Nicht gebaut: Tageschef, Notiz und Blöcke bearbeiten, Wetterort setzen, Frist der Anwesenheit setzen, Anwesenheit von Teilnehmenden, Zusammenfassung (Zahlen) der Anwesenheit, Einkäufer wählen, Artikel ändern oder löschen, Punkte der Packliste entfernen oder ändern, Notfall-Kontakte, Kartenlink und Infos anlegen, ändern oder löschen (kein Board dafür), Konfliktbildschirm für diese Boards.

## Schnitt B5 Ablage und Querschnitt: Bildschirme (Issue #90)

Gebaut mit den Zuständen Normal, Leer, Laden, Fehler, Ohne Netz (Stand-Hinweis, wo schon Daten da sind), Fehler beim Speichern, Gesperrt wegen Rolle, Lager abgeschlossen, Textgrösse AX3, Tag und Nacht (Vorschauen):

| Was | Code (`Screens/Camp/Storage`) |
| --- | --- |
| L33 Dokumente (Liste, Suche nach Titel und Stichwort, Filter nach Typ, «neu», Verweis auf den Ablageort nur über `openableLink`) | `CampDocumentsModel`, `CampDocumentsView` |
| L34 Adressbuch (nur Lagerleitung; Telefon und E-Mail nur über `Link`; «Fürs nächste Lager behalten», Hinweis zur Aufräumfrist; «Neuer Kontakt») | `CampAddressBookModel`, `CampAddressBookView` |
| L36 Suche (tippfehlertolerant durch den Server, gruppiert nach Art, Typ-Filter, Treffer öffnen den Bildschirm der Art, wo es ihn gibt) | `CampSearchModel`, `CampSearchView` |
| Rechte, Texte, gemeinsame Bausteine | `CampStorageRights`, `CampStorageText`, `CampStorageSupport.swift` |

Navigation: Mehr-Sheet, Abschnitt «Ablage»: «Dokumente», «Adressbuch» (nur Lagerleitung) und «Suche». Ein Push öffnet nichts Neues. Die Boards zeigen im Start und im Mehr kein Suchfeld; deshalb gibt es keines dort.

Datenschutz: Die Adresse des Ablageorts geht nur an das System (`Link`), nie in einen Log und nie in einen Zwischenspeicher; es werden keine Bytes geladen. Nur `https`-Adressen sind öffnbar, alles andere ist eine Zeile ohne Verweis («Kein sicherer Link»). Kontaktdaten stehen in keinem Widget, Log oder Absturzbericht und liegen nur im Arbeitsspeicher.

Abweichungen vom Entwurf:

- L33: «Hochladen» fehlt samt den Zuständen «Aktion läuft» (S, Fortschritt) und «Fehler beim Speichern» (X, Dateityp, 20 MB): die API kennt kein Hochladen, nur Verknüpfungen auf den Ablageort (siehe «Route fehlt»). Das Board «Gesperrt wegen Rolle» (G) sagt «Hochladen kann …» und entfällt damit auch. Der Leertext lautet «Hier erscheinen die Dokumente des Lagers, sobald sie eingetragen sind.» statt «Lade eine Datei hoch …». Der Typ-Filter (Menü oben rechts) und die Zeile «Nur …» sind neu (Wunsch des Auftrags, kein Board).
- L34: Das Board «Gesperrt wegen Rolle» nennt «Mara» als Ansprechperson; der Text lautet «Wende dich an die Lagerleitung.», der Knopf «Zurück» statt «Zum Start» (das Mehr-Sheet hat keinen Start). Der Schalter steht je Kontakt (das Board zeigt einen unter den Karten); die Aufräumfrist («Wird ab … gelöscht.») steht zusätzlich je Kontakt. Das Formular «Neuer Kontakt» hat Name, Telefon und E-Mail; Funktion, Gruppe und Notiz setzt die App nicht. Bearbeiten und Löschen von Kontakten fehlt (kein Board).
- L36: «Zuletzt angesehen» fehlt (bräuchte lokalen Speicher, Entscheid offen), «Personen, 0» fehlt (die Suche liefert keine Personen), der Treffer zeigt keine hervorgehobenen Wörter (die Antwort nennt keine Fundstellen) und der Leerzustand schlägt kein Wort vor («Meintest du …»: die API liefert keinen Vorschlag). Vor der Eingabe zeigt der Bildschirm «Im Lager suchen» (kein Board). Aufgaben, Notizen und Protokolle haben keinen eigenen Bildschirm im Mehr-Sheet; diese Treffer sind nicht antippbar.
- L37: Die Boards zeigen die Einträge von Start, nicht die Ablage; das Mehr-Sheet bekommt den Abschnitt «Ablage».

Nicht gebaut: **L38 Papierkorb** (alle Boards: Normal, Laden, Leer, Fehler, Erfolg und Rückgängig, Aktion läuft). Es gibt keine Route zum Ansehen oder Wiederherstellen (Revisionen, L0e), und das Entwurf-Set hat keinen Zustand «nicht verfügbar». Der Stichwort-Filter (`stichwort`) der Dokumente (die Suche findet Stichworte über `q`), Dokumente anlegen, ändern und löschen, Dateien verknüpfen (Datenschicht ist da, kein Board ausser dem Hochladen).

## Schnitt C3 Testserver, UI-Tests, Abgleich mit dem Entwurf (Issue #94)

- `CeviOS/App/UITestBackend.swift` (nur DEBUG) kennt zwei Lager: «Sommerlager Beispiel 2027» (aktiv, beginnt in 12 Tagen) und «Herbstlager Beispiel 2026» (abgeschlossen). Persona `leitung…` ist Lagerleitung, `team…` Team; Eltern haben kein Lager. Die Antworten stehen in `UITestCampFixtures.swift` (Pflichtfelder nach `api-vertrag/openapi.yaml`, Datums-Platzhalter `{{D+n}}`/`{{T-n}}`), der Zustand (Aufgaben, Checkliste, Pinnwand) in `UITestCampBackend.swift`.
- `CampTestServerTests` liest jede Route der Bildschirme gegen den Testserver und dekodiert sie mit den echten Modellen. Ein Fall (Status von «Busfahrt buchen») antwortet einmal mit 409 `VERSION_KONFLIKT`.
- UI-Abläufe: `CampFlowTests` (Lagerleitung, Team, abgeschlossenes Lager, grösste Schrift, Dunkelmodus, alle Einträge von «Mehr»).
- Lesende Routen liefern feste Beispieldaten. Schreibende Routen ausser Status, Checkliste und neuer Pinnwand-Beitrag antworten 204 ohne Inhalt (die Bildschirme zeigen dann einen Fehler beim Speichern).

## Schnitt D1 Lager-Check (Issue #108)

Ohne Entwurf gebaut: Das Design hat kein Board für den Lager-Check. Der Bildschirm besteht aus vorhandenen Bausteinen (Karten, Chips, `StateView`, `CampScroll`, Konfliktansicht) und folgt `docs/design.md` und dem UX-Handbuch.

| Was | Route | Code |
| --- | --- | --- |
| Gesamtstand und Stand je Prüfer, Hinweise, bis zu fünf Beispiele | `GET …/check` | `CampCheck`, `CampChecker`, `CampCheckNote`, `CampCheckExample` |
| Eigene Punkte lesen, anlegen, ändern (abhaken, umbenennen), löschen | `GET/POST …/check/punkte`, `PATCH/DELETE …/check/punkte/{punktId}` | `CampCheckPoint`, `CampCheckModel` |
| Bildschirm «Lager-Check» im Blatt «Mehr» | | `CampCheckView`, `CampCheckScreen` |

- Der Eintrag steht in «Mehr» für Lagerleitung, Leitung und Lesen (Vorgabe von `check.lesen`). Die Lagerleitung kann das Recht dem Team geben; die Antwort nennt die Rechte nicht, darum zeigt die App den Eintrag dem Team nicht (Route fehlt: Rechte der Person im Lager). Knöpfe zum Schreiben nur für die Lagerleitung (`zeitplan.bearbeiten` und `check.lesen`) im Lager ohne Schreibschutz.
- Schreibaktionen gehen direkt hinaus. Die Warteschlange kennt keine Operation für Check-Punkte und der Vertrag keine Idempotenz-Kennung: Ohne Netz scheitert die Aktion sichtbar mit «Nochmals versuchen»; nichts wird still wiederholt. `VERSION_KONFLIKT` beim Ändern öffnet die Konfliktansicht (Felder «Punkt» und «Erledigt»); beim Löschen lädt die Liste neu. Kein lokaler Speicher.
- Ein Prüfer, den die Rolle nicht lesen darf, fehlt in der Antwort und damit auf dem Bildschirm. Ein unbekannter Prüfer wird gezeigt (Fall `unknown`), ein unbekannter Stand ist ein Dekodierfehler.
- Wetter-Ort einstellen entfällt: `PUT …/wetter/ort` steht nicht mehr im Vertrag.
- Nicht gebaut: Umordnen der eigenen Punkte (`reihenfolge` ist im Vertrag, der Bildschirm bietet keine Bedienung), Testserver-Routen (kein UI-Ablauf braucht sie).

## Schnitt F5b Verschlüsselter Cache des zuletzt geladenen Lagers (Issue #116)

Ohne Entwurf gebaut: Es gibt kein Board dafür. Der Hinweis «Ohne Netz» nutzt die vorhandene Karte (`CampOfflineNote`); sie nennt jetzt den Stand mit Tag («heute 18:02», «gestern 21:10»). Entscheid des Auftraggebers: Nichts bleibt offline, ausser man lädt es gezielt herunter oder es ist normaler Cache des zuletzt geladenen Lagers (Android: cevi-os-android#244). Sicherheit: SR-41, SR-43, SR-50, SR-42, SR-24, SR-54.

| Was | Code |
| --- | --- |
| Schnittstelle `CampCache` (Speicher für Rohantworten), Datei-Umsetzung und Speicher-Umsetzung für Tests | `CampCache.swift`, `CampFileCache.swift` |
| Regeln, was gespeichert werden darf (Positivliste), Zugriff, Löschen | `CampCachePolicy`, `APIClient+Cache.swift` |
| Hinweis «Ohne Netz» auf jedem Lager-Bildschirm | `ActiveCamp.cachedSince`, `CampBannerStack` |

- **Was liegt auf dem Gerät:** die Antworten des Servers, wie sie kamen, nur für die Bereiche Lagerdetail, Aufgaben, Pinnwand, Tagesseiten, Heute und Meine Woche, Zeitplan, Packliste, Einkauf, Notfall, Infos, Wetter, dazu die Lagerliste (Titel, Rolle, Zeitraum). Nur lesende Aufrufe (`GET`).
- **Nie zwischengespeichert:** Teilnehmende, Zimmer, Fahrten, Gruppen, Anwesenheit, Abzählliste, Diensttausch, Schichtplan, Adressbuch, anonymer Eingang, Suche, Rechtetabelle, Mitglieder, private To-dos. Es ist eine Positivliste: Was nicht genannt ist, wird nie geschrieben.
- **Verschlüsselung:** AES-GCM (CryptoKit), eine Datei je Lager in Application Support (`LagerCache`), der Dateiname gehört zu den authentisierten Daten. Der Schlüssel liegt im Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Dateischutz `complete`, Ordner und Datei sind vom Geräte-Backup ausgenommen. Eine Datei, die sich nicht öffnen lässt (verändert, falscher Schlüssel, umbenannt), wird gelöscht. Pro Antwort höchstens 1 MB.
- **Schreiben nur für offene Lager:** Geschrieben wird erst, wenn die frische Lagerliste das Lager als Entwurf oder aktiv nennt. Abgeschlossen oder archiviert: nichts wird geschrieben.
- **Löschen:** Die frische Lagerliste löscht alle Lager, die fehlen oder nicht mehr offen sind. 404 oder 403 auf dem Lager löscht das ganze Lager, 404 oder 403 auf einem Bereich nur diesen Eintrag. Abmelden, Sitzungsende (401) und Wechsel des Kontos löschen alles samt Schlüssel.
- **Ohne Netz:** Nur bei einem Netzfehler (nicht bei 5xx oder 4xx) antwortet der Client mit dem letzten Stand; die Bildschirme laden wie sonst und zeigen die Karte «Ohne Netz». Die Lagerliste kommt beim Kaltstart ohne Netz aus dem Cache.
- **Warteschlange:** `CampOutbox` bleibt im Arbeitsspeicher. Bei 403, 404, 409 (auch `LAGER_GESCHLOSSEN`) und 410 markiert sie die Einträge als abgelehnt und wiederholt nicht; bei 401 bleibt sie liegen, die Sitzung ist zu Ende und der Arbeitsspeicher geht mit der App.
- Grenze: Die Lagerliste im Cache kann ein Lager noch zeigen, das inzwischen geschlossen ist; sie wird beim nächsten Netz ersetzt.

## Schnitt F5a Gezielter Download von Dateien (Issue #118)

Ohne Entwurf gebaut: Es gibt kein Board dafür. Der Bildschirm «Aushänge» und die Liste «Heruntergeladene Dateien» bestehen aus Listenzeilen, Textknöpfen und dem Quick-Look-Fenster des Systems (`docs/design.md`, UX-Handbuch). Entscheid des Auftraggebers: Nichts bleibt offline, ausser man lädt es gezielt herunter (Android: cevi-os-android#245). Keine Rechtstexte, keine Auto-Downloads. Sicherheit: SR-41, SR-23, SR-24, SR-42, SR-50.

| Was | Code |
| --- | --- |
| Download-Speicher (Schnittstelle, Datei-Umsetzung), Herkunft und Art | `CampDownloads.swift`, `CampDownload.swift` |
| Herunterladen, Öffnen, Entfernen im offenen Lager | `CampDownloader`, `CampHandoutsView` («Mehr», Ablage, «Aushänge»), Menü der Traktanden («Kalenderdatei herunterladen») |
| Liste «Heruntergeladene Dateien» (Profil, Abschnitt «App») | `DownloadedFilesView` |

- **Was sich laden lässt:** die PDF-Aushänge (`GET …/aushaenge/{art}`) und die Kalenderdatei eines Hoecks (`GET …/hoecks/{id}.ics`). **Nicht** die «Dateien» im Lager (Dokumente, Protokolle, Infos): Das sind nur Verknüpfungen auf einen fremden Ablageort (`https`), die die App nicht selbst abruft (siehe Schnitt A2/A5). Der Eintrag «Aushänge» erscheint für Lagerleitung und Leitung; der Server entscheidet je Aushang (403 zeigt eine Fehlermeldung).
- **Speicherort:** Application Support, Ordner `Downloads`, vom Backup ausgenommen, Dateischutz `complete`. Dateinamen erzeugt die App (UUID und `pdf` oder `ics`), nie der Name vom Server. Eine Datei wird nur behalten, wenn die ersten Bytes zur Art passen (`%PDF-`, `BEGIN:VCALENDAR`) und sie höchstens 20 MB hat. Ein Eintrag im Index mit fremdem Dateinamen wird ignoriert.
- **Öffnen:** Quick Look des Systems, ohne Netz. Der Inhalt verlässt die App nur, wenn die Person ihn im Quick-Look-Fenster teilt.
- **Löschen:** «Entfernen» je Datei; Abmelden und Sitzungsende löschen alles; die frische Lagerliste löscht die Downloads von Lagern, die nicht mehr darin stehen (ein abgeschlossenes Lager steht weiter darin: seine Downloads bleiben); 404 auf dem Lager löscht seine Downloads, 403 nicht.
- **Hinweis:** Zimmerliste, Gruppenlisten und Fahrtenliste enthalten Namen von Kindern. Sie liegen nur nach einer ausdrücklichen Handlung der Person auf dem Gerät (Entscheid des Auftraggebers).

## Offene Fragen zum Entwurf

- L1: «62 Prozent erledigt, 4 überfällig» braucht `GET …/start` je Lager; «Übungslager» (Abschnitt, Chip «Übung») hat kein Feld in der API. Beides fehlt in der App.
- A10: Untertitel «Cevi Beispielstadt» (Abteilungsname) und die Zahl «3 neu» am Lager (ungelesene Benachrichtigungen je Lager) sind nicht angeschlossen; der Umschalter zeigt «Programme».
- U7: Der Name der Person, die zuletzt geändert hat («Lea hat …»), steht nicht in der Konflikt-Antwort; der Titel kommt vom Aufrufer.
- L38: Der Papierkorb hat keine Route in der API und im Entwurf keinen Zustand «nicht verfügbar»; die Bildschirme fehlen, bis die Revisionen (L0e) da sind und geklärt ist, ob ein Hinweis nötig ist.
- L33: «Hochladen» (Fortschritt, Dateityp, 20 MB) setzt Medienspeicher voraus (L0g); der Entwurf kennt keinen Bildschirm «Link hinzufügen» für das Verknüpfen eines Ablageorts.
- L36: «Personen» und «Zuletzt angesehen» haben keine Quelle (keine Route, kein lokaler Speicher).
- L2: Die Schnellzugriffe «Notiz», «Protokoll», «Mitteilung» und die Zahl «7 für dich» fehlen; die Aufgabenkarten zeigen kein «Checkliste 2 von 4» (die Aufgabenliste liefert keine Zähler der Checkliste).
- L2/L5: Der Entwurf setzt die Frist und den Hinweis «Fällig in …» in eine Zeile; die App stapelt sie. Der Umschalter hat keinen roten Punkt (ungelesen je Lager, siehe A10).
- L20/L28/L33/T3: Der Entwurf zeigt die Lagerbildschirme als Seiten des Tab «Mehr» mit Umschalter oben; die App öffnet sie im «Mehr»-Blatt ohne Umschalter. Der Entwurf fasst Zeilen in einer Karte mit Trennlinien zusammen (Einkauf, Zeitplan); die App zeigt je Zeile eine Karte.
- L33: Die Suche steht im Entwurf oben im Bildschirm, in der App unten (iOS-26-Suchleiste).
- Grosse Titel: Die Titelschrift der Navigationsleiste ist reines Schwarz, der Entwurf zeigt ein dunkles Grau.
- U4: Die Endzeit der Wartung («bis 22:00») liefert die API nicht; der Text nennt sie nicht.

## Route fehlt (blockiert)

| Gebraucht für | Fehlt | Backend-Issue |
| --- | --- | --- |
| A0b: Namen der `typ`-Werte und Nutzlast-Felder der Operationen | Beschreibung nennt nur das Beispiel `aufgabe.aendern`; Module melden ihre Operationen an | L0c |
| Papierkorb, Verlauf, Fassungen | Revisionen | L0e |
| Dateien (Dokumente, Bilder) | Lager-Dateien im Medienspeicher | L0g |
| ~~A1: Lager-Check «Sind wir bereit?»~~ | erledigt: `GET …/check` und Punkte (Stand 25.11.), siehe Schnitt D1; offen bleibt eine Rechteliste der Person im Lager | L1 |
| ~~A1: Vorlagen auflisten~~ | erledigt: `GET …/vorlagen` (Stand 25.11.), `campTemplates`; ein Bildschirm zur Vorlagenwahl fehlt noch | L1 |
| A1: frühere Fassungen einer Aufgabe, Zurückholen | Verlauf kennt nur Art, Version, Zeitpunkt; keine Inhalte | L0e |
| A2: Protokoll-Abschnitte (Text im Protokoll) | nur Zeile mit Dateiverweis, kein Inhalt, keine Abschnitte | L2 |
| A2: Dateien zum Hochladen (Pinnwand, Protokoll) | `dateiIds` setzen vorhandene Dateien voraus, Hochladen: Lager-Dateien | L0g |
| A2: Reaktionen auf anderes als Pinnwand | `zielTyp` kennt nur `pinnwand_beitrag` | L3 |
| ~~A3 (B1): Namen der Mitglieder~~ erledigt mit `GET …/mitglieder` (Stand 25.11.): `ActiveCamp.memberNames` füllt Diensttausch und Anwesenheit. Alt: | Liste der Lagermitglieder für Nicht-Admins; `…/lager/{id}/mitglieder` gibt es nur unter `/api/v1/admin` (die App ruft Admin nie auf). Schichten tragen `name`, ein Tausch nur `personId`s | L4 |
| A3: Tauschanfrage mit Namen, Zimmer-Namen der Teilnehmenden im Team | Tausch liefert keine Namen und keine Schicht-Details; Fahrer nur als `fahrer.name` | L4 |
| A4: Namen der Anwesenheits-Matrix, des Tageschefs im Team und der Einkäufer-Auswahl | Matrix nennt nur IDs (Mitglieder und Teilnehmende löst die App über Listen auf); Mitglieder-Liste fehlt für Nicht-Admins | L4 |
| ~~B3/B4: Namen~~ Diensttausch und Anwesenheit erledigt; Schichtauswahl, Zimmer und Fahrten zeigen den Namen der Liste. Das Team sieht über `…/mitglieder` nur Personen aus seinen Listen. Alt: wie A3: Mitgliederliste für Nicht-Admins fehlt; die App zeigt «Person», wo nur `personId` kommt | L4 |
| A5: Wissen früherer Lager übernehmen | keine Route in der Beschreibung | L6 |
| A5: Papierkorb ansehen, Wiederherstellen, Verlauf (ausser `…/aufgaben/{id}/verlauf`) | keine Routen (Löschen ist weich, aber nicht abrufbar) | L0e |
| A5: Exporte als Word und Excel | nur Aushänge als PDF (`…/aushaenge/{art}`) | L7 |
| A5: Dateien hochladen oder per signierter Adresse laden | nur Verknüpfungen auf den Ablageort, keine Bytes | L0g |

Nicht ableitbar: Welche Rechte die eigene Rolle hat. Die Matrix darf nur die Lagerleitung lesen. Die Aufgaben-Routen sollen laut Auftrag die erlaubten Aktionen in der Antwort liefern (fehlt die Aktion, fehlt der Knopf).

## Entscheide, die der Auftraggeber treffen muss

1. Lokaler Speicher: Entschieden für den verschlüsselten Cache des zuletzt geladenen Lagers (Schnitt F5b) und für gezielte Downloads. Offen bleibt die Warteschlange (`CampOutbox` liegt im Arbeitsspeicher hinter `CampOutboxStore`).
2. Zwischenspeicher für Widgets (App-Gruppe), nötig erst für A7.
3. Design-Entwurf «Cevi Lager iOS» liefern (Bildschirme erst danach).

## Stand 25.11. (Backend 31fb03f)

- Profilbilder (`bildUrl` bei Personen im Lager, `LagerBildUrl`) werden in den Lager-Bildschirmen noch nicht gezeigt: `ProfileAvatar` kann den Pfad sicher laden (`ImagePath`), aber jede Zeile müsste umgebaut werden. Bis dahin Initialen.
- Felder ohne Verwendung: `Lager.uebung`, `bildUrl` der Lager-Personen, `LagerAnwesenheitSeite.bilder`.
