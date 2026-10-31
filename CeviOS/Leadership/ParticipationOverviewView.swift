import SwiftUI

@MainActor @Observable
final class ParticipationOverviewModel {
    private(set) var overview: ParticipationOverview?
    private(set) var error: String?

    func load(programId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            overview = try await client.participationOverview(programId: programId)
            error = nil
        } catch is CancellationError {
        } catch let apiError as APIError {
            error = LeadershipMessages.message(for: apiError).text
        } catch {
            self.error = APIError.network.displayText
        }
    }
}

/// Who said yes, no or nothing yet. The server computes the numbers.
struct ParticipationOverviewView: View {
    @Environment(AppState.self) private var appState
    let programId: UUID
    @State private var model = ParticipationOverviewModel()

    var body: some View {
        Group {
            if let overview = model.overview {
                List {
                    Section("Kinder") {
                        counts(overview.totals.children)
                        ForEach(overview.children) { child in
                            answerLabel("\(child.firstName) \(child.lastName)", child.answer)
                        }
                    }
                    Section("Leitende") {
                        counts(overview.totals.leaders)
                        ForEach(overview.leaders) { leader in
                            answerLabel(leader.ceviName.map { "\(leader.name) (\($0))" } ?? leader.name, leader.answer)
                        }
                    }
                }
                .refreshable { await model.load(programId: programId, client: appState.client) }
            } else if let error = model.error {
                ErrorRow(text: error).padding()
            } else {
                ProgressView().accessibilityLabel(Text("Lädt"))
            }
        }
        .navigationTitle("Teilnahmen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(programId: programId, client: appState.client) }
    }

    private func counts(_ counts: ParticipationCounts) -> some View {
        Text("Ja: \(counts.yes), Nein: \(counts.no), Offen: \(counts.open)")
            .font(.headline)
    }

    @ViewBuilder
    private func answerLabel(_ name: String, _ answer: OverviewAnswer) -> some View {
        switch answer {
        case .yes: Label("\(name): Ja", systemImage: "checkmark.circle.fill")
        case .no: Label("\(name): Nein", systemImage: "xmark.circle.fill")
        case .open: Label("\(name): Offen", systemImage: "circle.dashed")
        }
    }
}
