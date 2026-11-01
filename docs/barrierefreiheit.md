# Barrierefreiheit

Stand der Prüfung für Issue #10. Massgebend sind die Regeln aus dem Design-System «Cevi OS iOS» und die Vorgaben aus dem Auftrag: VoiceOver-Labels und Reihenfolge, Dynamic Type bis zur grössten Stufe, Kontrast, mindestens 44 pt Tippfläche, Zustände nie nur durch Farbe.

## Wie geprüft wird

Die UI-Tests in `CeviOSUITests/` fahren die ganze App durch, mit dem echten App-Code (APIClient, Dekodierung, Phasen des `AppState`, alle Views) gegen ein simuliertes Backend. Auf jedem Bildschirm läuft Apples Prüfung `performAccessibilityAudit()`, dazu prüfen die Tests Beschriftungen, «ausgewählt»-Zustände, Tippflächen und dass Zustände als Wort dastehen («Ja», «Nein», «Offen», «Abgesagt», «Wird geprüft», «Da», «Nicht da», «2 ungelesen»).

### Aufbau

- `Support/AppRobot.swift`: startet die App mit Startargumenten (Persona, Schriftgrösse, Dunkelmodus, Fehlerfall, Sperre).
- `Support/Screen.swift`: Protokoll `Screen` mit `isDisplayed`, `waitUntilDisplayed()`, Tippen, Tippen in Felder, Scrollen bis erreichbar, `auditAccessibility()`, `snapshotLabels()` und Prüfhilfen (Wort sichtbar, Tippfläche ≥ 44 pt, ausgewählt).
- `Support/AccessibilityAudit.swift`: der Audit mit der einen, begründeten Liste von Fehlmeldungen (siehe unten).
- `Screens/`: eine Datei pro Bildschirm (Seitenobjekt): `SignInScreen`, `ChangePasswordScreen`, `WelcomeScreen`, `LockScreen`, `ProgramListScreen`, `ProgramDetailScreen`, `ParticipationOverviewScreen`, `AssignmentScreen`, `ChatListScreen`, `ChatScreen`, `NewMessageScreen`, `ProfileScreen`, `StateScreen` (offline, Fehler, leer, veraltet, Sitzung beendet), `TabBar`. Jede Datei kennt die Elemente ihres Bildschirms und bietet Handlungen wie `signIn(username:password:)`, `answer(child:yes:)`, `send(message:)`.
- `Flows/AppFlowTests.swift`: die zentrale Testdatei. Jeder Test liest sich wie ein Drehbuch und ruft die Seitenobjekte der Reihe nach auf.
- `LaunchTests.swift`: Start ohne simuliertes Backend, Audit des Anmeldebildschirms.

### Simuliertes Backend

`CeviOS/App/UITestBackend.swift` gibt es nur in Debug-Builds (`#if DEBUG`); in Release und Prod wird nichts davon kompiliert. Mit dem Startargument `-UITestBackend YES` registriert die App ein `URLProtocol` über `APIClient.makeSession(protocolClasses:)`. Es beantwortet alle Endpunkte, die die App nutzt, mit erfundenen Daten im Speicher (Eva, Lena und Noah Beispiel, Jan Muster, `example.org`) und merkt sich Änderungen bis zum Ende des Starts. Ohne das Argument ändert sich nichts.

Die Persona folgt dem Benutzernamen, den der Test eintippt: `eltern…` Elternteil mit zwei Kindern, `leitung…` Stufenleitung, `neu…` erste Anmeldung (Passwort ändern, Datenschutz noch nicht bestätigt). Jedes nicht leere Passwort gilt; die Tests erzeugen es zufällig, es gibt keine Zugangsdaten im Code.

Startargumente:

| Argument | Wirkung |
|---|---|
| `-UITestBackend YES` | simuliertes Backend statt Netzwerk, Cookies nur im Speicher, keine Gesichtserkennung |
| `-UITestFailure offline` | erste Anfrage ohne Verbindung (Startbildschirm «Keine Verbindung») |
| `-UITestFailure server` | erste Programmliste mit Status 500 |
| `-UITestFailure unauthorized` | erstes Programmdetail mit Status 401: Sitzung beendet |
| `-UITestFailure outdated` | jede Anfrage mit Status 426: App veraltet |
| `-UITestFailure empty` | leere Programmliste |
| `-UITestSignedIn <name>` | Start mit gespeicherter Sitzung dieser Persona |
| `-UITestLocked YES` | Sperre einschalten, Sperrbildschirm einmal zeigen; «Entsperren» entsperrt |
| `-AppleInterfaceStyle Dark` | Dunkelmodus |
| `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` | grösste Schrift (AX5) |

### Abläufe

| Test | Ablauf |
|---|---|
| `testParentFlow` | Anmelden als Elternteil, Programmliste (Zusagen, Abgesagt, Wird geprüft, mehrtägiges Programm), Detail, Ja für Lena und Nein für Noah, Liste und erneut geöffnetes Detail zeigen die Antworten, abgesagtes Programm ohne Antwortknöpfe, Chatliste mit «2 ungelesen», Gruppenchat mit älteren Nachrichten und Senden, neue Nachricht an die Stufenleitung, Profil mit Mitteilungs-Schaltern, Abmelden |
| `testParentFlowLargestText` | derselbe Ablauf bei der grössten Schrift (AX5) |
| `testMainScreensDark` | Anmeldung, Liste, Detail, Chatliste, Chat, neue Nachricht und Profil im Dunkelmodus |
| `testFirstLoginFlow` | leere Anmeldung (Fehlermeldung), erste Anmeldung, Passwort zu kurz, ungleich, dann gespeichert, Willkommen mit Einwilligung, App |
| `testLeaderFlow` | Anmelden als Stufenleitung, eigene Anmeldung «Ja», Anmeldungen (Zahlen, Kinder, Leitende), Stufen und Sichtbarkeit (ohne Stufe gesperrt, dann «Leitende» gespeichert), Chatliste |
| `testFailureStates` | offline mit Wiederholen, Serverfehler mit Wiederholen, leere Liste, Sitzung beendet mit erneuter Anmeldung |
| `testOutdatedApp` | Hinweis «Bitte die App aktualisieren» |
| `testLockScreen` | Sperrbildschirm, Entsperren, App |

Die Tests warten nur auf Elemente und Zustände (`waitForExistence`, Erwartungen), nie eine feste Zeit.

### Gefundene und behobene Mängel

Die Abläufe haben im App-Code gefunden und behoben:

- **Antwortknöpfe lasen «Lena, LocalizedStringKey(key: "Ja" …)»** vor. Ursache: ein `LocalizedStringKey` in eine Textinterpolation gesteckt. Jetzt ein übersetzter `String`.
- **Textfelder liessen sich nur auf der 22 pt hohen Textzeile antippen**, nicht im ganzen 50 pt hohen Feld. `CeviField` setzt den Fokus jetzt bei einem Tipp irgendwo im Feld. Der Test tippt bewusst unter die Textzeile.
- **Programmliste: Dynamic Type nur teilweise unterstützt.** Die Tageszeile wechselte bei grossen Schriften die Ansicht (`if`), dadurch gingen die Texte verloren; jetzt ein Layoutwechsel (`AnyLayout`). Die Liste ist nicht mehr «lazy», damit alle Karten im Bedienungshilfen-Baum bleiben.
- **Antworten erschienen erst nach dem Aktualisieren in der Liste.** Die Liste lädt neu, wenn man aus dem Detail zurückkommt.
- **Passwort ändern:** Bei offener Tastatur verdeckt die Aktionsleiste das letzte Feld. Die Eingabetaste springt jetzt ins nächste Feld.
- Mehrzeilige Texte (Zustandsmeldungen, Orte im Detail, Hinweis in der Chatliste, Vorschau in der Chatliste) brechen um statt abgeschnitten zu werden.
- Fehler im Testfilter: `case .dynamicType, .textClipped where …` galt nur für `textClipped`, damit war `dynamicType` bisher immer ausgeblendet. Jetzt gilt der Filter wie beschrieben.

## Was im Code umgesetzt ist

- Alle Farben sind Design-Token mit Varianten für «Mehr Kontrast» (Asset Catalog, vier Erscheinungen).
- Zustände (Ja, Nein, Offen, Abgesagt, Wird geprüft, Ungelesen, Fehler) tragen SF Symbol und Wort.
- Tippflächen mindestens 44 pt, Hauptschaltflächen 52 pt, Felder 50 pt.
- Schriften skalieren mit Dynamic Type (Archivo über `relativeTo`, sonst Textstile). Zeilen stapeln sich bei grossen Schriftgrössen.
- «Bewegung reduzieren»: Skelett-Puls und Übergänge fallen weg (Überblenden der Tabs und der Anmeldeschritte, 0,26 s). Beim Abmelden gibt es nie einen Übergang.
- Dauert eine Aktion, die du ausgelöst hast, länger als 250 ms, liegt eine abgedunkelte Ebene mit Ladeanzeige über der ganzen App. Sie fängt alle Berührungen ab, nimmt den Fokus aus Textfeldern und VoiceOver sagt «Einen Moment …» an. Hintergrundarbeit (Aktualisieren, Bilder, ältere Nachrichten) blockiert nie.
- Profilbilder sind Zierde und für VoiceOver verborgen. Der Name trägt die Information.
- Überschriften sind als solche markiert, Karten und Chat-Zeilen sind zu einem Element zusammengefasst.

## Ausnahmen in den automatischen Prüfungen

Diese Ausnahmen stehen begründet in `CeviOSUITests/Support/AccessibilityAudit.swift`. Kein Prüftyp ist ganz abgeschaltet.

- **Kontrast ohne Element:** Systemflächen (Tab Bar im «Liquid Glass» mit Abzeichen), die die App nicht zeichnet.
- **Text unter der Tab Bar:** Der Kontrast wird gegen das Glas gemessen und nicht gegen den eigenen Hintergrund.
- **Beschnittener Text bei der grössten Schrift:** Die Prüfung vergrössert Text über die grösste Stufe hinaus. Meldungen «dynamicType» und «textClipped» werden bei AX5 **nicht gewertet**; bei normaler Schrift und im Dunkelmodus schon.
- **Von Hand geprüfte Texte:** Einige Texte meldet die Prüfung als abgeschnitten, weil sie die Schrift vergrössert, ohne neu zu layouten. Auf den Bildschirmaufnahmen der Testläufe stehen sie vollständig. Die Liste steht namentlich im Code (z. B. «Ganztägig · …» auf der Programmkarte).
- **Segmentierte Auswahl (Kinder/Leitende):** Systemsteuerelement, 32 pt hoch. Apples Prüfung akzeptiert es; der eigene 44-pt-Test lässt es aus.

Das heisst: Bei der grössten Schrift gibt es keinen automatischen Nachweis gegen abgeschnittene Texte. Das ist die Lücke, die von Hand zu schliessen ist.

## Nicht geprüft

- VoiceOver auf einem echten iPhone, Reihenfolge und Ansagen im Ablauf.
- Sprachsteuerung (Voice Control), Schalter-Steuerung (Switch Control), Tastatur.
- Eine echte Anmeldung mit Server (alle Bildschirme sind nur mit erfundenen Daten geprüft).
- **«Mehr Kontrast»:** Es gibt kein Startargument und keine XCUITest-Schnittstelle, die «Mehr Kontrast» einschaltet; die Farbvarianten im Asset Catalog folgen der Trait Collection, die sich ohne UIKit nicht überschreiben lässt. `-UIAccessibilityDarkerSystemColorsEnabled` wirkt nicht verlässlich. Von Hand prüfen.
- Überschriften-Eigenschaft (`isHeader`): XCUITest liest sie nicht aus. Nur Apples Prüfung (Typ «trait») und der Code decken sie ab.
- Nicht in den Abläufen: Profilbild (Fotoauswahl), Telefonnummer der Stufenleitung, Push-Erklärung, Webseiten im Browser (Support, Konto löschen, Datenschutzerklärung), Hinweis für Admins bei der Anmeldung.
- Bei offener Tastatur verdeckt die Aktionsleiste auf «Passwort ändern» das letzte Feld; die Eingabetaste hilft, das Layout selbst ist noch ein Design-Entscheid.
- Archivo-Schrift in den Gewichten auf dem Gerät.
- iPad und Querformat: Die App läuft nur auf dem iPhone und nur im Hochformat.

## Vorschlag für die manuelle Gesamtprüfung

1. VoiceOver einschalten, Anmeldung bis Chat einmal durchgehen, auf Reihenfolge und Beschriftungen achten.
2. Schrift auf die grösste Zugänglichkeitsstufe stellen und jeden Bildschirm ansehen.
3. «Mehr Kontrast», «Transparenz reduzieren», «Bewegung reduzieren» und «Ohne Farbe unterscheiden» einzeln einschalten.
4. Ergebnis im PR unter «Barrierefreiheit» festhalten.
