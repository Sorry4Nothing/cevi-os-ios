# App-Nachweis (App Attest)

Beim Anmelden belegt die App dem Server mit Apple App Attest, dass sie die echte App auf einem echten Gerät ist. Anleitung des Backends: `docs/app-nachweis.md` im Backend-Repository (Stand 25.11.2026, Issue #785). Code: `Core/Networking/AppAttest.swift`, `Core/Services/AuthService.swift` (`appProofTicket`).

## Ablauf bei jedem Anmeldeversuch

1. `POST /api/v1/app/nachweis/challenge` `{ plattform: "ios" }`: neue Herausforderung (nie auf Vorrat). 404: Nachweis am Server aus, Anmeldung ohne Ticket.
2. `bindung = SHA-256(nonce + "\n" + benutzername in Kleinbuchstaben)` ist der `clientDataHash`.
3. Ohne gemerkten Schlüssel: `generateKey`, dann `attestKey` (Attestation). Mit Schlüssel: `generateAssertion`. Den Zähler der Assertions führt das Betriebssystem, die App zählt nichts.
4. `POST /api/v1/app/nachweis`: Ticket (2 Minuten, einmal). Erst nach 200 wird die Schlüssel-ID im Keychain gemerkt (`WhenUnlockedThisDeviceOnly`, Dienst `<Bundle-ID>.nachweis`).
5. `POST /api/auth/sign-in/username` mit Header `X-Cevi-Nachweis`. Nur die Anmeldung trägt den Header.

Fehler blockieren die Anmeldung nie: Simulator oder `isSupported == false`, 404, Netz, Apple-Fehler, 4xx/5xx beim Nachweis führen zur Anmeldung ohne Ticket. Der Server verweigert dann selbst (Modus `pflicht`), und die App zeigt seinen Text. 401 beim Nachweis (Attestation für bekannten Schlüssel, Assertion mit unbekanntem Schlüssel oder zurückgegangenem Zähler) und `DCError.invalidKey` verwerfen den Schlüssel; die App holt eine neue Herausforderung und bestätigt einen neuen Schlüssel (ein Wiederholungsversuch je Anmeldung). Ein 401 des Nachweises beendet nie die Sitzung (`/api/v1/app/*` löst kein `sessionEnded` aus).

Weder Schlüssel-ID, Beleg, Nonce noch Ticket werden geloggt oder in Fehlertexte übernommen.

## Entitlement und Build

`Config/CeviOS.entitlements` setzt `com.apple.developer.devicecheck.appattest-environment = production`. `CODE_SIGN_ENTITLEMENTS` steht nur in `Config/Int.xcconfig` und `Config/Prod.xcconfig`, nicht in `Dev.xcconfig`: Ein kostenloses «Personal Team» kann die Entitlement nicht signieren, Dev-Builds laufen weiter (auf dem Gerät mit Dev schlägt App Attest vermutlich fehl, ungeprüft; die Anmeldung geht dann ohne Ticket). Ein Dev-Build mit bezahltem Team braucht nichts Eigenes; soll App Attest dort laufen, die Entitlement mit `development` in einer eigenen Datei für Dev eintragen.

## Was getestet ist

Unit-Tests (`AppAttestTests`, `ApiContractTests.appProofCallsAreInTheDescription`) mit einer Test-Umsetzung von `AppAttestProviding`: Prüfsumme der Bindung mit Testvektor, 404 gleich ohne Ticket, Ticket im Header, neue Herausforderung je Versuch, Attestation beim ersten Mal und Assertion danach, Schlüssel-ID erst nach 200 gespeichert, Neu-Attestierung nach 401, Fehler bei Apple oder Server gleich Anmeldung ohne Ticket, kein Ticket oder Beleg in `APIError`. Der Testserver der UI-Tests antwortet auf die Herausforderung mit 404.

## Was nicht getestet ist

- **Gegen einen echten Apple-Beleg nie geprüft.** `DeviceCheckAppAttest` ist nur übersetzt, nie auf einem Gerät gelaufen; App Attest geht nicht auf dem Simulator.
- Die Entitlement im Provisioning-Profil, die Umgebung `development` oder `production` gegenüber `umgebung` der Herausforderung und das Verhalten nach einer Neuinstallation (Apple verwirft die Schlüssel, der Keychain-Eintrag bleibt; die App erkennt es an `invalidKey` oder 401).

## Betriebsmodi des Servers (`APP_NACHWEIS`)

- `aus`: Herausforderung antwortet 404, alles wie bisher; die Sitzung gilt als `app_ungeprueft`.
- `pruefen`: Das Ticket wird geprüft und das Ergebnis gelogged (`app_nachweis`, Feld `grund`); ohne Ticket geht die Anmeldung noch.
- `pflicht`: Ohne gültiges Ticket 401 `APP_NACHWEIS_FEHLT` oder `APP_NACHWEIS_UNGUELTIG`.

## Erster Lauf auf einem echten Gerät

1. Release- oder Int-Build mit bezahltem Team auf ein Gerät bringen (siehe Pull Request für die Schritte in Xcode).
2. Betreiber stellt `APP_NACHWEIS=pruefen`.
3. Anmelden. Server-Log lesen: Eintrag `app_nachweis` mit `grund`. Erwartet: erste Anmeldung Attestation, `GET /api/v1/ich` zeigt `clientArt: app_nachgewiesen`.
4. Abmelden und nochmals anmelden: jetzt Assertion.
5. Erst wenn beides sauber läuft, `pflicht`.
