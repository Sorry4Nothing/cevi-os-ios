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

## Push

Push-Nachrichten laufen über Firebase Cloud Messaging (FCM).

## Mitwirken

- Branches: `main` und `develop`. Änderungen gehen als Pull Request nach `develop`.
- Pro Issue ein Branch (`feature/<nr>-<kurzname>`, für Fehler `fix/<nr>-<kurzname>`) und ein Pull Request.
- Nie ins Repo, in Issues oder PRs: echte Namen, Kalender-ID, iCal-Adresse, Zugangsdaten, Serverzugang, `.env`-Inhalte.
