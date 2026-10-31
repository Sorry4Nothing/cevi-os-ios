# App-Store-Vorbereitung

Alles hier ist ohne Zugangsdaten, echte Namen oder Adressen. Die Basis-Adresse der API steht nur in `Config/Secrets.xcconfig` (nicht im Repo).

## Technisch erledigt

- **Privacy Manifest:** `CeviOS/PrivacyInfo.xcprivacy`. Kein Tracking, keine Tracking-Domains. Erhobene Daten (alle mit Zweck «App-Funktionalität», mit der Person verknüpft, nicht zum Tracking): Name, Benutzer-ID, Telefonnummer (nur Stufenleitung, freiwillig), Foto (Profilbild, freiwillig), Inhalte (Chat-Nachrichten), Geräte-ID (Push-Token). Genutzte API mit Begründung: UserDefaults (`CA92.1`: Einstellungen der App selbst).
- **Verschlüsselung:** `ITSAppUsesNonExemptEncryption = NO` (nur HTTPS des Systems). Damit entfällt die Exportfrage bei jedem Build.
- **Face ID:** Text für `NSFaceIDUsageDescription` ist gesetzt.
- **Links:** Datenschutz, Support und «Konto löschen» sind in der App erreichbar (Profil und Anmeldung). Die Seiten liefert der Server: `/datenschutz`, `/support`, `/konto-loeschen`.
- **Konto löschen:** Die App löscht keine Konten. Das erklärt `/konto-loeschen` (Weg über die Leitung).
- **Universal Links:** Die Apple-App-Site-Association des Backends ist leer. Es gibt nichts zu tun, bis das Backend sie füllt.

## App Privacy in App Store Connect (Antworten)

| Datenart | Erhoben | Mit Person verknüpft | Tracking | Zweck |
| --- | --- | --- | --- | --- |
| Name | ja | ja | nein | App-Funktionalität |
| Benutzer-ID | ja | ja | nein | App-Funktionalität |
| Telefonnummer | ja (freiwillig, nur Stufenleitung) | ja | nein | App-Funktionalität |
| Fotos oder Videos | ja (Profilbild, freiwillig) | ja | nein | App-Funktionalität |
| Weitere Nutzerinhalte | ja (Chat) | ja | nein | App-Funktionalität |
| Geräte-ID | ja (Push-Token) | ja | nein | App-Funktionalität |

Alles andere: nicht erhoben. Die Antworten müssen mit der Datenschutzerklärung des Servers (`/datenschutz`) übereinstimmen. Das prüft die Abteilung.

## Review-Hinweise (Vorlage, Zugangsdaten nur in App Store Connect)

- Die App ist für genau eine Abteilung des Cevi (Jugendverband) und für Eltern, Leitende und Stufenleitung gedacht. Konten legt die Leitung im Browser an. Es gibt keine Selbstregistrierung.
- Demo-Konto: Benutzername und Passwort tragen Sie in App Store Connect unter «Anmeldeinformationen» ein (nicht im Repo, nicht in diesem Dokument).
- Push-Benachrichtigungen enthalten nie Nachrichtentext oder Namen von Kindern.
- Konto löschen: Auf Anfrage über die Leitung (Seite `/konto-loeschen`).
- **Moderation (Richtlinie 1.2):** Die App enthält Chat mit Inhalten von Nutzern. Der Rahmen: geschlossener Kreis aus Eltern und Leitung einer Abteilung, Konten verwaltet die Leitung, jede Nachricht trägt den Namen der Person, die Stufenleitung liest in jedem Einzelchat mit, ein Wortfilter lehnt unpassende Nachrichten auf dem Server ab, Kontakt über `/support`.
  **Lücke:** Die App hat kein Melden und kein Blockieren, weil die API keine Routen dafür bietet. Ob die Prüfung den Rahmen genügen lässt, ist offen. Fällt sie negativ aus, braucht es im Backend Routen zum Melden und Blockieren und danach in der App die Bedienung dafür.

## Altersfreigabe (Vorschlag, die Abteilung entscheidet)

Der Fragebogen in App Store Connect fragt nach nutzergenerierten Inhalten und Chat. Zu erwarten ist eine Freigabe ab 12 oder 13 Jahren wegen unbeschränkter Kommunikation unter Nutzern, trotz geschlossenem Kreis. Das ist vor der Einreichung gemeinsam mit der Abteilung zu beantworten.

## Screenshots

- Nur aus der Demo-Abteilung mit erfundenen Namen. Nie echte Kinder, Eltern oder Orte.
- Grössen für iPhone gemäss App Store Connect (6,9 Zoll).

## Was noch von der Abteilung oder vom Inhaber kommen muss

Siehe die Liste am Ende des Pull Requests zu Issue #10.
