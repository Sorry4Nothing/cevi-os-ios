import SwiftUI

/// A8/A10: top left of the main screens. Switches between the program view and a camp. Only for members of a camp.
private struct CampSwitcher: ViewModifier {
    // Optional: screens without the camp module in the environment (previews) show no switcher.
    @Environment(CampListModel.self) private var list: CampListModel?
    @Environment(ActiveCamp.self) private var active: ActiveCamp?
    @Environment(AppState.self) private var state: AppState?

    func body(content: Content) -> some View {
        content.toolbar {
            if let list, let active, list.showsSwitcher {
                ToolbarItem(placement: .topBarLeading) { menu(list, active) }
            }
        }
    }

    private func menu(_ list: CampListModel, _ active: ActiveCamp) -> some View {
        Menu {
            Button { active.leave() } label: {
                Label("Programme", systemImage: active.isOpen ? "calendar" : "checkmark")
            }
            .accessibilityAddTraits(active.isOpen ? [] : .isSelected)
            ForEach(list.openCamps) { entry in
                let isCurrent = active.camp?.id == entry.id
                Button { active.open(entry, client: state?.client) } label: {
                    Label(entry.camp.title, systemImage: isCurrent ? "checkmark" : "tent")
                    Text("Lager-Ansicht")
                }
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
            Button { active.showsChooser = true } label: {
                Label("Alle Lager", systemImage: "tent.2")
                Text("Lagerwahl, auch abgeschlossene")
            }
        } label: {
            Label(active.isOpen ? active.title : String(localized: "Programme"), systemImage: active.isOpen ? "tent" : "calendar")
        }
        .accessibilityLabel(Text("Ansicht wechseln, jetzt \(active.isOpen ? active.title : String(localized: "Programme"))"))
    }
}

extension View {
    /// The switcher between program and camp view in the top left of the navigation bar.
    func campSwitcher() -> some View { modifier(CampSwitcher()) }
}
