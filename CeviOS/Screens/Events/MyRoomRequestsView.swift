import SwiftUI

/// K3 Meine Raumanfragen.
struct MyRoomRequestsView: View {
    @Environment(AppState.self) private var appState
    @State private var model = MyRoomRequestsModel()
    @State private var showsForm = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Meine Raumanfragen")
            .navigationSubtitle("Deine Anfragen und ihr Stand")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Raum anfragen", systemImage: "plus") { showsForm = true }
                }
            }
            .navigationDestination(isPresented: $showsForm) { RequestRoomView(fromList: true) }
            .task { await model.load(client: appState.client) }
            // Back from the form: a new request shows up right away.
            .onChange(of: showsForm) { _, shown in
                if !shown { Task { await model.load(client: appState.client) } }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Anfragen werden geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .loaded where model.requests.isEmpty:
            StateView(symbol: "door.left.hand.closed", title: "Keine Anfragen", message: "Du hast noch keinen Raum angefragt.")
        case .loaded:
            ScrollView {
                VStack(spacing: Spacing.s3) {
                    ForEach(model.requests) { request in row(request) }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load(client: appState.client) }
        }
    }

    private func row(_ request: RoomRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s1))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s2))
            layout {
                Text(request.roomName).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s2) }
                RequestStatusChip(kind: MyRoomRequestsModel.chip(for: request.status))
            }
            Text(EventFormat.range(start: request.start, end: request.end)).foregroundStyle(Color.ceviOnSurfaceVariant)
            Text(request.purpose).foregroundStyle(Color.ceviOnSurfaceVariant)
            if request.status == .confirmed {
                Label("Im Kalender eingetragen", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ceviOnSuccessContainer)
            }
            if request.status == .declined, let reason = request.reason, !reason.isEmpty {
                Text("Grund: \(reason)").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .combine)
    }
}
