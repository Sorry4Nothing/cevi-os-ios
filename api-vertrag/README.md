# API-Beschreibung (Kopie)

`openapi.yaml` und `endpunkte.md` sind eine Kopie aus dem Backend `Sorry4Nothing/cevi-os`, Ordner `docs/api/`. **Nie von Hand ändern.** Ändert das Backend die Beschreibung, wird die Kopie neu übernommen.

Der Test `CeviOSTests/Core/Networking/ApiContractTests.swift` liest `openapi.yaml` und prüft, dass jeder Aufruf der App darin steht (Methode und Pfad).

Die Adresse des Servers steht nie im Repo (nur in `Config/Secrets.xcconfig`, nicht eingecheckt).
Stand der Kopie: aafd844 vom 2026-11-01
