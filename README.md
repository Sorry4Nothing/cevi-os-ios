# Cevi OS iOS

Native iOS (Swift, SwiftUI)-App für Cevi OS: Programme aus dem Google-Kalender, Ja/Nein-Anmeldung pro Kind und Chat zwischen Eltern und Stufenleitung.

Das Backend liegt in [Sorry4Nothing/cevi-os](https://github.com/Sorry4Nothing/cevi-os). Die API-Beschreibung steht dort unter `docs/api/`.

## Stand

Der Aufbau beginnt. Das Projektgerüst mit den Umgebungen Dev, Int und Prod steht. Die Funktionen folgen Issue für Issue.

## Voraussetzungen

- Xcode 27.2 oder neuer
- iPhone mit iOS 26 oder neuer (nur iPhone)

## Einrichten

1. `Config/Secrets.example.xcconfig` nach `Config/Secrets.xcconfig` kopieren und die Adressen der API eintragen. Die Datei wird nicht eingecheckt. In URLs `:/$()/` statt `://` schreiben, sonst gilt der Rest der Zeile als Kommentar.
2. `CeviOS.xcodeproj` öffnen und ein Scheme wählen. Für ein Gerät in Xcode unter «Signing & Capabilities» das eigene Team wählen.

## Umgebungen

Jedes Scheme hat eine eigene Build Configuration mit Werten aus `Config/<Umgebung>.xcconfig`. Die drei Apps lassen sich gleichzeitig auf einem Gerät installieren.

| Scheme | Bundle-ID | Anzeigename | Zweck |
|---|---|---|---|
| Dev | `io.github.sorry4nothing.cevios.dev` | Cevi OS Dev | tägliche Entwicklung, Tests |
| Int | `io.github.sorry4nothing.cevios.int` | Cevi OS Int | Integration und Vorabtest |
| Prod | `io.github.sorry4nothing.cevios` | Cevi OS | Produktion |

Die Unit- und UI-Tests laufen im Scheme Dev (`Product > Test`). Die Icons sind vorerst einfarbige Platzhalter.

## UI-Tests

`CeviOSUITests/` fährt die ganze App gegen ein simuliertes Backend (nur Debug-Builds, erfundene Daten) und prüft auf jedem Bildschirm die Barrierefreiheit: eine Datei pro Bildschirm unter `Screens/`, die Abläufe zentral in `Flows/AppFlowTests.swift`. Aufbau, Startargumente, Abläufe und Lücken: [docs/barrierefreiheit.md](docs/barrierefreiheit.md).

## Struktur

Regel: ein Ordner pro Seite, wiederverwendbare Bausteine in `Components`. Pro Datei ein Typ.

- `CeviOS/App/`: Einstieg der App (`CeviOSApp`, `AppState`, `RootView`, `MainView` mit den Tabs, `AppDelegate`)
- `CeviOS/Screens/<Seite>/`: je Seite ein Ordner mit View, Model und Teilen, die nur diese Seite braucht (z. B. `SignIn`, `ProgramList`, `ProgramDetail`, `Chat`, `Profile`)
- `CeviOS/Components/`: wiederverwendbare Bausteine, gruppiert nach `Buttons`, `Inputs`, `Labels`, `Cards`, `States`, `Layout`, `Web`, `Media`
- `CeviOS/Core/`: alles ohne Oberfläche: `Networking`, `Configuration`, `Models`, `Services` (API-Aufrufe), `Formatting`, `Security`, `Push`
- `CeviOS/Design/`: Design-Tokens (`Spacing`, `Radius`, `Size`, `TitleStyle`) und gemeinsame Modifier
- `CeviOSTests/`: spiegelt `Core/`, Hilfen für Netzwerk-Tests unter `Helpers/`

## Farben, Icons und Texte

Alles liegt an einer Stelle, nichts davon im Code:

- **Farben:** nur in `CeviOS/Assets.xcassets` (je mit Hell- und Dunkelwert, nach Bedeutung benannt: `AccentColor`, `cevi-<Token>` laut Design-System). Im Code nur die generierten Symbole (`Color.ceviSurface`), keine Hex- oder RGB-Werte.
- **App-Icons:** je Umgebung ein Set im selben Asset Catalog (`AppIcon`, `AppIcon-Int`, `AppIcon-Dev`), gewählt über `ASSETCATALOG_COMPILER_APPICON_NAME` in `Config/<Umgebung>.xcconfig`.
- **Texte:** alle Nutzertexte in `CeviOS/Localizable.xcstrings` (Deutsch, Schweizer Schreibweise). Neue Texte als Literal in `Text("…")` oder `String(localized:)` schreiben; Xcode trägt sie beim Build in den Catalog ein.

## Push

Push-Nachrichten laufen über Firebase Cloud Messaging (FCM).

## Mitwirken

- Branches: `main` und `develop`. Änderungen gehen als Pull Request nach `develop`.
- Pro Issue ein Branch (`feature/<nr>-<kurzname>`, für Fehler `fix/<nr>-<kurzname>`) und ein Pull Request.
- Nie ins Repo, in Issues oder PRs: echte Namen, Kalender-ID, iCal-Adresse, Zugangsdaten, Serverzugang, `.env`-Inhalte.
