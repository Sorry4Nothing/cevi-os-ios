# Barrierefreiheit

Stand der Prüfung für Issue #10. Massgebend sind die Regeln aus dem Design-System «Cevi OS iOS» und die Vorgaben aus dem Auftrag: VoiceOver-Labels und Reihenfolge, Dynamic Type bis zur grössten Stufe, Kontrast, mindestens 44 pt Tippfläche, Zustände nie nur durch Farbe.

## Wie geprüft wird

- `CeviOSUITests/AccessibilityAuditTests.swift` startet je ein Szenario und führt `performAccessibilityAudit()` aus: bei normaler Schrift, bei der grössten Schrift (`AccessibilityXXXL`) und bei den Hauptbildschirmen zusätzlich im Dunkelmodus.
- Die Szenarien kommen aus `CeviOS/App/UITestScenario.swift`. Es gibt sie nur in Debug-Builds (`#if DEBUG`), mit erfundenen Daten, ohne Netzwerk. In Prod-Builds gibt es den Code nicht.
- Szenarien: Anmeldung, Passwort ändern, Datenschutz, Programmliste, Programmdetail, Anmeldungen, Anwesenheit, Chatliste, Chat, Neue Nachricht, Profil, Sperre, Offline, Leer, Fehler.
- Lauf: `xcodebuild test -scheme Dev` auf dem Simulator. Zuletzt 103 Tests, alle bestanden.

## Was im Code umgesetzt ist

- Alle Farben sind Design-Token mit Varianten für «Mehr Kontrast» (Asset Catalog, vier Erscheinungen).
- Zustände (Ja, Nein, Offen, Abgesagt, Wird geprüft, Ungelesen, Da, Nicht da, Fehler) tragen SF Symbol und Wort.
- Tippflächen mindestens 44 pt, Hauptschaltflächen 52 pt, Felder 50 pt.
- Schriften skalieren mit Dynamic Type (Archivo über `relativeTo`, sonst Textstile). Zeilen stapeln sich bei grossen Schriftgrössen.
- «Bewegung reduzieren»: Skelett-Puls und Übergänge fallen weg.
- Profilbilder sind Zierde und für VoiceOver verborgen. Der Name trägt die Information.
- Überschriften sind als solche markiert, Karten und Chat-Zeilen sind zu einem Element zusammengefasst.

## Ausnahmen in den automatischen Prüfungen

Diese Ausnahmen sind in `AccessibilityAuditTests.swift` im Code begründet:

- **Kontrast ohne Element:** Systemflächen (Tab Bar im «Liquid Glass» mit Abzeichen), die die App nicht zeichnet.
- **Text unter der Tab Bar:** Der Kontrast wird gegen das Glas gemessen und nicht gegen den eigenen Hintergrund.
- **Beschnittener Text bei der grössten Schrift:** Die Prüfung vergrössert Text über die grösste Stufe hinaus, was nicht möglich ist. Sie meldet dann «dynamicType» oder «textClipped». Diese Meldungen werden bei der grössten Schrift **nicht gewertet**. Bei normaler Schrift gilt die Prüfung ohne diese Ausnahme. Einzelne Texte sind zusätzlich namentlich von Hand auf Bildschirmfotos geprüft.

Das heisst: Bei der grössten Schrift gibt es keinen automatischen Nachweis gegen abgeschnittene Texte. Das ist die Lücke, die von Hand zu schliessen ist.

## Nicht geprüft

- VoiceOver auf einem echten iPhone, Reihenfolge und Ansagen im Ablauf.
- Sprachsteuerung (Voice Control), Schalter-Steuerung (Switch Control), Tastatur.
- Eine echte Anmeldung mit Server (alle Bildschirme sind nur mit erfundenen Daten geprüft).
- Archivo-Schrift in den Gewichten auf dem Gerät.
- iPad.

## Vorschlag für die manuelle Gesamtprüfung

1. VoiceOver einschalten, Anmeldung bis Chat einmal durchgehen, auf Reihenfolge und Beschriftungen achten.
2. Schrift auf die grösste Zugänglichkeitsstufe stellen und jeden Bildschirm ansehen.
3. «Mehr Kontrast», «Transparenz reduzieren», «Bewegung reduzieren» und «Ohne Farbe unterscheiden» einzeln einschalten.
4. Ergebnis im PR unter «Barrierefreiheit» festhalten.
