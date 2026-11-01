import SwiftUI

/// Who said yes, no or nothing yet. The server computes the numbers.
struct ParticipationOverviewView: View {
    @Environment(AppState.self) private var appState
    let programId: UUID
    @State private var model = ParticipationOverviewModel()

    var body: some View {
        Group {
            if let overview = model.overview {
                ParticipationContent(overview: overview)
                    .refreshable { await model.load(programId: programId, client: appState.client) }
            } else if let error = model.error {
                ErrorRow(text: error).padding()
            } else {
                LoadingView(label: "Lädt")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ceviScreenBackground()
        .navigationTitle("Anmeldungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(programId: programId, client: appState.client) }
    }
}
