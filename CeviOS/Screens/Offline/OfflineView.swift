import SwiftUI

/// ZT4: no connection at launch.
struct OfflineView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        StateView.offline { Task { await state.start() } }
    }
}
