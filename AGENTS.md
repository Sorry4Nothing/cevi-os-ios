# Anweisungen für KI-Agenten

Diese Datei lesen Claude Code, Codex, Cursor, GitHub Copilot und andere Agenten automatisch. Sie gilt für jede Arbeit in diesem Repo.

## UX und Design: Pflicht bei jeder UI-Arbeit

Bei **jeder** Arbeit, die Oberfläche, Abläufe, Texte, Formulare, Navigation, Design oder Barrierefreiheit berührt – auch nur nebenbei –, gilt:

1. **Zuerst das UX- und Design-Handbuch lesen:** [`.claude/skills/ux-handbuch/SKILL.md`](.claude/skills/ux-handbuch/SKILL.md). Claude Code lädt es als Skill `ux-handbuch` automatisch; andere Agenten lesen die Datei direkt. Mindestens: «Verbindlichkeit», der Plattformteil (Teil 4 iOS) und Teil 9 (Cevi OS).
2. **Rangfolge bei Widersprüchen:** Projekt-Doku in diesem Repo (unten) → Handbuch → allgemeines Wissen. Weicht das Handbuch von einer Projektregel ab, gilt die Projektregel; den Widerspruch im PR nennen, wenn er die UX spürbar verschlechtert.
3. **Vor dem Abschluss** das Qualitätstor (Handbuch Teil 11) durchgehen und im PR unter «Evidence» und «Barrierefreiheit» festhalten, was geprüft wurde und was nicht.
4. **Für Reviews** die Methode und das Ausgabeformat aus Teil 8 verwenden.

## Verbindliche Projekt-Doku

- [Design](docs/design.md): Stil «Nachthimmel», Entscheide (iOS 26, nur iPhone, Hochformat), Design → Code, Abweichungen mit Grund. Bei jeder Design-Änderung nachführen.
- [Barrierefreiheit](docs/barrierefreiheit.md): wie die UI-Tests prüfen (`performAccessibilityAudit()` auf jedem Bildschirm) und bekannte Lücken.
- [Checkliste Barrierefreiheit](https://github.com/Sorry4Nothing/cevi-os/blob/develop/docs/barrierefreiheit.md) (im Backend-Repo): Prüfpunkte mit festen Nummern; im PR die geprüften Nummern, Gerät und iOS-Version angeben.
- `api-vertrag/`: Die App zeigt nur, was die API erlaubt – fehlt eine Aktion, fehlt der Button (nicht ausgegraut).
- `Design/` (Spacing, Radius, Size, TitleStyle) und Farbsets `cevi-<token>`: Werte nur dort, nie direkt in Views.

## Weitere Regeln

- Nur Deutsch, Schweizer Schreibweise (ss, «»), «du», kurze Sätze, Buttons sind Verben, keine Emojis. Bezeichner im Code englisch.
- Das Repo ist öffentlich und Cevi OS verwaltet Daten von Kindern: **keine echten Namen, Zugangsdaten, Kalender-Adressen, Exporte, Server-Zugänge oder `.env`-Werte** in Code, Tests, Issues, PRs oder Screenshots. Screenshots nur aus der Demo-Abteilung.
- Git: ein Branch und ein PR pro Issue nach `develop`, PR-Abschnitte Summary, Evidence, Merge Danger, Barrierefreiheit; Conventional Commits mit deutschem Betreff und Issue-Nummer (Details: [Git-Workflow](https://github.com/Sorry4Nothing/cevi-os/blob/develop/docs/GIT_WORKFLOW.md)).

## Handbuch aktuell halten

Das Handbuch liegt als identische Kopie in allen drei Repos (`cevi-os`, `cevi-os-android`, `cevi-os-ios`) unter `.claude/skills/ux-handbuch/SKILL.md`. Änderungen immer in allen drei Repos gleich nachführen. Ändert sich ein Projektentscheid, Teil 9 des Handbuchs anpassen.
