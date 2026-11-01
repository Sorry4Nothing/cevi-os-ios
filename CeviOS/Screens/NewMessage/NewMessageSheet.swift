import SwiftUI

/// Sheet for parents: pick the unit whose leaders get the message, one row per child.
struct NewMessageSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let model: ChatListModel
    let profile: Profile
    let open: (UUID) -> Void
    @State private var error: String?
    @State private var openingUnitId: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profile.children) { child in
                        Button { Task { await openChat(unitId: child.unitId) } } label: {
                            HStack(spacing: Spacing.s3) {
                                VStack(alignment: .leading, spacing: Spacing.s1) {
                                    Text("Stufenleitung \(unitName(child.unitId))")
                                        .font(.body)
                                        .foregroundStyle(Color.ceviOnSurface)
                                    Text("Für \(child.firstName)")
                                        .font(.footnote)
                                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                                }
                                Spacer()
                                if openingUnitId == child.unitId {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: Size.touchTarget)
                            .contentShape(.rect)
                        }
                        .disabled(openingUnitId != nil)
                        .listRowBackground(Color.ceviSurfaceContainerLow)
                    }
                } header: {
                    Text("An welche Stufenleitung möchtest du schreiben? Die Nachricht lesen alle Leitenden dieser Stufe.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Section { ErrorRow(text: error) }
                }
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Neue Nachricht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen", systemImage: "xmark") { dismiss() }
                        .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
                }
                // Without the shared glass the button keeps its own 44 pt frame (iOS 27 sizes the glass at 36 pt).
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }

    private func unitName(_ unitId: UUID) -> String {
        profile.units.first { $0.id == unitId }?.name
            ?? model.chats.first { $0.unit.id == unitId }?.unit.name
            ?? ""
    }

    private func openChat(unitId: UUID) async {
        guard let client = appState.client else { return }
        openingUnitId = unitId
        defer { openingUnitId = nil }
        do {
            let id = try await BusyState.shared.track {
                let id = try await client.openDirectChat(unitId: unitId)
                // The destination looks the chat up in the list, so the new chat must be loaded first.
                await model.load(client: client)
                return id
            }
            open(id)
        } catch let apiError as APIError {
            error = apiError.displayText
        } catch {
            self.error = APIError.network.displayText
        }
    }
}
