import SwiftUI

/// «LO» in a frame: the short code of a portfolio.
struct CampCodeChip: View {
    let code: String

    var body: some View {
        Text(code).font(.caption.bold()).foregroundStyle(Color.ceviOnSurface)
            .padding(.horizontal, Spacing.s2).padding(.vertical, 2)
            .overlay(Radius.shape(6).stroke(Color.ceviOutline, lineWidth: Size.border))
            .accessibilityHidden(true)
    }
}

/// A word with a symbol on a tinted capsule (never color alone).
struct CampStatusChip: View {
    let text: String
    let symbol: String
    /// Error colors (overdue). Without it the chip is a hint (warning colors), or neutral with `isNeutral`.
    var isWarning = false
    var isNeutral = false

    var body: some View {
        Label(text, systemImage: symbol).font(.caption.bold())
            .foregroundStyle(isNeutral ? Color.ceviOnSecondaryContainer : isWarning ? Color.ceviOnErrorContainer : Color.ceviOnWarningContainer)
            .padding(.horizontal, Spacing.s2).padding(.vertical, Spacing.s1)
            .background(isNeutral ? Color.ceviSecondaryContainer : isWarning ? Color.ceviErrorContainer : Color.ceviWarningContainer, in: .capsule)
    }
}

/// One task as a card: check circle, title, portfolio, person, deadline. Actions appear only if the role has them.
struct CampTaskRow: View {
    let task: CampTask
    let today: Date
    var rights: CampTaskRights
    var isQueued = false
    var isSelecting = false
    var isSelected = false
    let open: () -> Void
    var toggleDone: () -> Void = {}
    var move: () -> Void = {}
    var toggleStar: () -> Void = {}
    var select: () -> Void = {}
    var openPortfolio: (UUID) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var hint: (text: String, isOverdue: Bool)? { CampTaskText.dueHint(task, today: today) }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            leading
            Button(action: isSelecting ? select : open) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(summary))
                .accessibilityHint(Text(isSelecting ? "Wählt die Aufgabe aus." : "Öffnet die Aufgabe."))
                .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
            if !isSelecting { menu }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard(padding: Spacing.s3)
        .overlay(Radius.shape(Radius.md).stroke(isSelected ? Color.ceviAccent : Color.ceviOutlineVariant, lineWidth: isSelected ? Size.focusBorder : Size.border))
    }

    @ViewBuilder private var leading: some View {
        if isSelecting {
            Button(action: select) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(isSelected ? Color.ceviAccent : Color.ceviOnSurfaceVariant)
                    .frame(width: Size.touchTarget, height: Size.touchTarget)
            }
            .accessibilityLabel(Text(isSelected ? "Auswahl aufheben" : "Auswählen"))
        } else if rights.canSetStatus(task) {
            Button(action: toggleDone) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(task.status == .done ? Color.ceviAccent : Color.ceviOnSurfaceVariant)
                    .frame(width: Size.touchTarget, height: Size.touchTarget)
            }
            .accessibilityLabel(Text(task.status == .done ? "Wieder öffnen" : "Als erledigt markieren"))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(task.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                .strikethrough(task.status == .done).multilineTextAlignment(.leading)
            if task.portfolio != nil || task.responsible != nil {
                // At accessibility sizes the facts stack, so no word breaks letter by letter.
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s1)) : AnyLayout(HStackLayout(spacing: Spacing.s2))) {
                    if let portfolio = task.portfolio { HStack(spacing: Spacing.s2) { CampCodeChip(code: portfolio.code); Text(portfolio.name) } }
                    if let person = CampTaskText.person(task.responsible) { Text(person) }
                }
                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            if let due = task.due { Text("Frist \(CampTaskText.day(due))").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            if let hint { CampStatusChip(text: hint.text, symbol: hint.isOverdue ? "exclamationmark.triangle" : "clock", isWarning: hint.isOverdue) }
            if isQueued { Label("Wartet auf Netz", systemImage: "clock").font(.caption.bold()).foregroundStyle(Color.ceviOnSecondaryContainer) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var menu: some View {
        Menu {
            Button("Öffnen", systemImage: "arrow.up.right", action: open)
            if let portfolio = task.portfolio { Button("Ressort \(portfolio.name)", systemImage: "folder") { openPortfolio(portfolio.id) } }
            if rights.canSetStatus(task) { Button("Status ändern", systemImage: "arrow.left.arrow.right", action: move) }
            if rights.canEdit { Button(task.starred ? "Stern entfernen" : "Stern setzen", systemImage: task.starred ? "star.slash" : "star", action: toggleStar) }
            if rights.canSetStatus(task) { Button("Auswählen", systemImage: "checkmark.circle", action: select) }
        } label: {
            Image(systemName: task.starred ? "star.fill" : "ellipsis").foregroundStyle(Color.ceviOnSurfaceVariant)
                .frame(width: Size.touchTarget, height: Size.touchTarget)
        }
        .accessibilityLabel(Text("Weitere Aktionen für \(task.title)"))
    }

    /// One sentence for VoiceOver.
    private var summary: String {
        var parts = [task.title, String(localized: "Status \(CampTaskText.statusName(task.status))")]
        if let portfolio = task.portfolio { parts.append(String(localized: "Ressort \(portfolio.name)")) }
        if let person = CampTaskText.person(task.responsible) { parts.append(String(localized: "verantwortlich \(person)")) }
        if let due = task.due { parts.append(String(localized: "Frist \(CampTaskText.day(due))")) }
        if let hint { parts.append(hint.text) }
        if task.starred { parts.append(String(localized: "mit Stern")) }
        if isQueued { parts.append(String(localized: "Änderung wartet auf Netz")) }
        return parts.joined(separator: ", ")
    }
}
