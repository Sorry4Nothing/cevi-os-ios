import SwiftUI

/// K5 Raumanfragen entscheiden, built without a design draft from the existing building blocks (`docs/termine.md`).
struct RoomDecisionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: RoomDecisionsModel
    @State private var declining: RoomRequest?

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Raumanfragen")
            .navigationSubtitle("Entscheide über offene Anfragen")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.load(client: appState.client) }
            .sheet(item: $declining) { request in
                DeclineRoomSheet(model: model, request: request, client: appState.client) { declining = nil }
                    .presentationDetents([.medium, .large])
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Anfragen werden geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .loaded:
            ScrollView {
                VStack(spacing: Spacing.s3) {
                    if let notice = model.notice { noticeBar(notice) }
                    if model.requests.isEmpty {
                        StateView(symbol: "door.left.hand.open", title: "Keine offenen Anfragen", message: "Über alle Anfragen ist entschieden.").frame(minHeight: 320)
                    }
                    ForEach(model.requests) { request in card(request) }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load(client: appState.client) }
        }
    }

    private func noticeBar(_ text: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Color.ceviOnSuccessContainer)
            Spacer(minLength: Spacing.s2)
            Button("Schliessen", systemImage: "xmark") { model.dismissNotice() }.labelStyle(.iconOnly).frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
        }
        .padding(.leading, Spacing.s4)
        .background(Color.ceviSuccessContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .contain)
    }

    private func card(_ request: RoomRequest) -> some View {
        let busy = model.busyId == request.id
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(request.roomName).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                if let name = request.requesterName { Text("Von \(name)").foregroundStyle(Color.ceviOnSurfaceVariant) }
                Text(EventFormat.range(start: request.start, end: request.end)).foregroundStyle(Color.ceviOnSurfaceVariant)
                Text(request.purpose).foregroundStyle(Color.ceviOnSurface)
            }
            .accessibilityElement(children: .combine)
            if let error = model.rowErrors[request.id] { ErrorRow(text: error) }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.s1)) : AnyLayout(HStackLayout(spacing: Spacing.s2))
            layout {
                if model.retryable[request.id] != nil {
                    Button("Nochmals versuchen", systemImage: "arrow.clockwise") { Task { await model.retry(request, client: appState.client) } }
                        .buttonStyle(.ceviPrimary)
                } else if !model.bookedIds.contains(request.id) {
                    Button("Bestätigen") { Task { await model.accept(request, client: appState.client) } }.buttonStyle(.ceviPrimary)
                        .accessibilityLabel(Text("\(request.roomName) bestätigen"))
                }
                Button("Ablehnen") { declining = request }.buttonStyle(.ceviText)
                    .accessibilityLabel(Text("\(request.roomName) ablehnen"))
            }
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }
}

/// The reason for declining: the requester sees it. 1 to 500 characters.
struct DeclineRoomSheet: View {
    let model: RoomDecisionsModel
    let request: RoomRequest
    let client: APIClient?
    let close: () -> Void
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text("\(request.roomName), \(EventFormat.range(start: request.start, end: request.end))").foregroundStyle(Color.ceviOnSurfaceVariant)
                    if let error = model.rowErrors[request.id] { ErrorRow(text: error) }
                    Text("Grund").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Grund", text: $reason, axis: .vertical).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                        .onChange(of: reason) { _, value in if value.count > RoomDecisionsModel.maxReason { reason = String(value.prefix(RoomDecisionsModel.maxReason)) } }
                    Text("Die anfragende Person sieht diesen Grund.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                    Button("Ablehnen") { Task { if await model.decline(request, reason: reason, client: client) { close() } } }.buttonStyle(.ceviPrimary)
                }
                .padding(Spacing.s4)
            }
            .ceviScreenBackground()
            .navigationTitle("Anfrage ablehnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark", action: close) } }
        }
    }
}
