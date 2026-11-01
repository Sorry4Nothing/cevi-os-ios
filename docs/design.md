# Design: Entwurf und Umsetzung

Stil «Nachthimmel»: Nacht ist die Hauptrichtung, Tag folgt der Systemeinstellung, kein dynamisches Farbschema. Das Design System gilt vor den einzelnen Bildschirm-Vorlagen. Quellen (nicht im Repo): das Design System «Cevi OS iOS» (`tokens.json`) und die Vorlagen der Bildschirme (Tag und Nacht).

## Entschieden

| Thema | Entscheid |
| --- | --- |
| Mindestversion | **iOS 26** (Liquid Glass, `Tab`, `@Entry`). Die Vorgabe nannte iOS 17; der Auftraggeber hat iOS 26 beibehalten (1. November 2026). |
| Geräte und Ausrichtung | Nur iPhone, nur Hochformat. Weicht von der Checkliste Barrierefreiheit 5.8 ab. |
| Sprache | Deutsch, Schweizer Schreibweise, «du». Code, Kommentare und Tests englisch. |

## Design → Code

| Entwurf | Code |
| --- | --- |
| Farb-Token (4 Erscheinungen: Nacht, Tag, je mit mehr Kontrast) | Farbsets `cevi-<token>` in `Assets.xcassets`, Symbole `Color.cevi…`. `accent` ist zusätzlich `AccentColor` (App-Tint). |
| `glass`, `glass-stroke`, `tab-selected`, `scrim` | Nicht umgesetzt: iOS zeichnet Glas und Abdunkelung selbst. |
| Titel in Archivo (800, Kartentitel 700) | `Font.title(_:)` in `Design/TitleStyle.swift`, Schrift in `Fonts/` (OFL), `UIAppFonts` in `Config/Info.plist`. |
| Text in SF Pro | Systemstile (`.body`, `.subheadline` …). |
| Abstände, Radien, Grössen | `Design/Spacing.swift`, `Radius.swift` (kontinuierliche Ecken), `Size.swift`. |
| Tab Bar, Navigationsknöpfe | Systemelemente (Liquid Glass), nicht nachgezeichnet. |
| Start | Launch Screen mit `cevi-surface`, dann `StartView`. |
| Zustände (Laden, Leer, Offline, Fehler, nicht gefunden, kein Zugriff, Sitzung beendet) | `Components/States/` (`StateView`, `LoadingView` mit Skelett-Puls). |

## Abweichungen von den Vorlagen

| Vorlage | Umsetzung | Grund |
| --- | --- | --- |
| Detailseiten schieben ein Sechstel der Breite herein | Nativer Wechsel des `NavigationStack` | `navigationTransition` bietet auf iOS 26 nur `automatic` und `zoom`. |
| Überblendung der Reiter | Der neue Inhalt blendet ein | `TabView` hat keine eigene Animation. |
| Anwesenheit (Matrix) | Entfällt | Entscheid des Auftraggebers. |
| Zweiter Faktor, Admin-Bereich | Entfällt | Admins melden sich nicht in der App an. |
| Eigene Zurück- und Kalender-Knöpfe, Untertitel in der Leiste | Systemleiste | Native Navigation. |
| Cevi-Logo als Ersatz für fehlende Stufenlogos | **Platzhalter** (Symbol) | Das echte Logo (im Nachtmodus das hellere Blau `#7C7DE8`) ist zu liefern. |
| Kontakt: Rolle der Person | Entfällt | Die API liefert keine Rolle. |

## Muster

- Kein Zustand nur über Farbe: immer Symbol und Wort.
- Jede ausgelöste Aktion zeigt sofort einen Ladekreis im Knopf. Dauert sie länger als 250 ms, liegt ein Overlay über der App (nie bei Hintergrundanfragen).
- Neue Interaktionsmuster (Dialog, Sheet, Popup) nicht ungefragt einführen.
- Wo der Entwurf mehr zeigt, als die API oder das Issue hergibt, gilt das Issue.

## Nachführen

Dieses Dokument ändert sich mit jeder Design-Änderung. Neue Abweichungen gehören in die zweite Tabelle, mit Grund.
