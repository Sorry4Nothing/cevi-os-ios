import SwiftUI

/// Sets units and visibility of a program. Shown to admins and unit leaders only; the API checks again.
struct AssignmentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let program: Program
    let profile: Profile
    let onSaved: () -> Void

    @State private var allUnits: [UnitInfo] = []
    @State private var selectedUnits: Set<UUID> = []
    @State private var visibility: Visibility = .internalOnly
    @State private var action = ActionState()
    @State private var loaded = false

    private var permissions: LeadershipPermissions { LeadershipPermissions(profile: profile) }

    private var validity: (ok: Bool, message: String?) {
        if !LeadershipPermissions.isValidAssignment(units: selectedUnits, visibility: visibility) {
            return (false, String(localized: "Ohne Stufe ist nur «Intern» möglich."))
        }
        let allowed = permissions.canSaveAssignment(
            oldUnits: Set(program.units.map(\.id)), newUnits: selectedUnits,
            oldVisibility: program.visibility, newVisibility: visibility
        )
        return allowed ? (true, nil) : (false, String(localized: "Du kannst nur Stufen ändern, in denen du Stufenleitung bist."))
    }

    /// Section title in the design style: footnote, semibold, on-surface-variant (enough contrast on the screen background).
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.ceviOnSurfaceVariant)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sichtbar für", selection: $visibility) {
                    Text("Intern (Admin und Stufenleitung)").tag(Visibility.internalOnly)
                    Text("Leitende").tag(Visibility.leaders)
                    Text("Eltern").tag(Visibility.parents)
                }
            } header: {
                sectionTitle("Sichtbarkeit")
            }
            .listRowBackground(Color.ceviSurfaceContainerLow)
            Section {
                ForEach(permissions.assignableUnits(from: allUnits)) { unit in
                    Toggle(isOn: Binding(
                        get: { selectedUnits.contains(unit.id) },
                        set: { isOn in if isOn { selectedUnits.insert(unit.id) } else { selectedUnits.remove(unit.id) } }
                    )) {
                        HStack(spacing: Spacing.s3) {
                            UnitLogo(unitId: unit.id, size: Size.avatar * 0.75)
                            Text(unit.name)
                        }
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                sectionTitle("Stufen")
            }
            .listRowBackground(Color.ceviSurfaceContainerLow)
            if let message = validity.message { Section { ErrorRow(text: message) } }
            if let error = action.error { Section { ErrorRow(text: error) } }
            Section {
                Button {
                    Task {
                        await action.perform(message: { LeadershipMessages.message(for: $0).text }) {
                            try await appState.client?.assign(programId: program.id, unitIds: Array(selectedUnits), visibility: visibility)
                            onSaved()
                            dismiss()
                        }
                    }
                } label: {
                    Text("Speichern").frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!validity.ok || action.isRunning)
            }
        }
        .scrollContentBackground(.hidden)
        .ceviScreenBackground()
        .navigationTitle("Stufen und Sichtbarkeit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            loaded = true
            selectedUnits = Set(program.units.map(\.id))
            visibility = program.visibility
            allUnits = (try? await appState.client?.units()) ?? []
        }
    }
}
