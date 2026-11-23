import SwiftUI

/// K2 Raum anfragen.
struct RequestRoomView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var scrolledTo: String?
    @State private var model = RequestRoomModel()
    @State private var showsRequests = false
    /// Opened from the list of own requests: «Meine Raumanfragen» then goes back instead of opening it again.
    let fromList: Bool

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Raum anfragen")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showsRequests) { MyRoomRequestsView() }
            .task { await model.load(client: appState.client) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Räume werden geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .empty:
            StateView(symbol: "door.left.hand.closed", title: "Keine Räume", message: "Die Abteilungsleitung hat noch keine Räume erfasst.")
        case .ready:
            if model.sent != nil { result } else { form }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                banner.id("banner")
                rooms
                DateTimeFields(date: $model.date, start: $model.start, end: $model.end)
                if let text = model.bookedMessage ?? model.errors.time { FieldError(text: text) }
                EventTextField(label: "Zweck", accessibility: String(localized: "Zweck"), text: $model.purpose)
                if let text = model.errors.purpose { FieldError(text: text) }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition(id: $scrolledTo, anchor: .top)
        // Sending fails at the bottom of a long form: bring the banner with the reason into view.
        .onChange(of: [model.action.error ?? "", model.errors.isEmpty ? "" : "x", model.bookedMessage ?? ""]) { scrolledTo = nil; Task { scrolledTo = "banner" } }
        .formBar("Raum anfragen", isEnabled: !model.action.isRunning) { Task { await model.send(client: appState.client) } }
    }

    @ViewBuilder
    private var banner: some View {
        if model.bookedMessage != nil {
            InfoBanner(tone: .error, title: String(localized: "Dieser Raum ist schon belegt."), message: String(localized: "Wähle eine andere Zeit."))
        } else if let error = model.action.error, model.errors.isEmpty {
            InfoBanner(tone: .error, title: String(localized: "Das hat nicht geklappt"),
                       message: "\(error) \(String(localized: "Deine Eingabe ist noch da. Versuche es nochmals."))") {
                Button("Nochmals versuchen") { Task { await model.send(client: appState.client) } }.buttonStyle(.ceviText)
            }
        } else if !model.errors.isEmpty {
            InfoBanner(tone: .error, title: String(localized: "Prüfe deine Eingaben."), message: String(localized: "Ein Feld braucht noch eine Angabe."))
        } else {
            InfoBanner(tone: .info, title: String(localized: "Das zuständige Team bestätigt deine Anfrage."))
        }
    }

    private var rooms: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            FieldLabel("Raum").accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(model.rooms.enumerated()), id: \.element.id) { index, room in
                    if index > 0 { Divider() }
                    roomRow(room)
                }
            }
            .background(Color.ceviSurface, in: Radius.shape(Radius.md))
            .overlay { Radius.shape(Radius.md).strokeBorder(Color.ceviOutline, lineWidth: Size.border) }
            if let text = model.errors.room { FieldError(text: text) }
        }
    }

    private func roomRow(_ room: Room) -> some View {
        let isSelected = model.roomId == room.id
        let detail = [room.details, room.capacity.map { String(localized: "\($0) Plätze") }].compactMap { $0 }.joined(separator: ", ")
        return Button { model.roomId = room.id } label: {
            HStack(spacing: Spacing.s3) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.ceviSwitchOn : Color.ceviOutline)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(room.name).font(.body).foregroundStyle(Color.ceviOnSurface)
                    if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(minHeight: Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                InfoBanner(tone: .success, title: String(localized: "Anfrage gesendet."),
                           message: String(localized: "Das zuständige Team bestätigt deine Anfrage.")) {
                    Button("Rückgängig") { Task { await model.undo(client: appState.client) } }
                        .buttonStyle(.ceviText)
                        .disabled(model.action.isRunning)
                }
                if let error = model.action.error { ErrorRow(text: error) }
                if let sent = model.sent {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(sent.roomName).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                            Spacer(minLength: Spacing.s2)
                            RequestStatusChip(kind: .open)
                        }
                        Text(EventFormat.range(start: sent.start, end: sent.end)).foregroundStyle(Color.ceviOnSurfaceVariant)
                        Text("Zweck: \(sent.purpose)").foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ceviCard()
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .resultBar("Meine Raumanfragen") { if fromList { dismiss() } else { showsRequests = true } }
    }
}
