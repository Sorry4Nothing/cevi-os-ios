import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    let chat: ChatSummary
    let profile: Profile
    @State private var model: ChatModel
    @State private var draft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(chat: ChatSummary, profile: Profile) {
        self.chat = chat
        self.profile = profile
        _model = State(initialValue: ChatModel(chatId: chat.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            if chat.kind == .direct { directNotice }
            messageList
            composer
        }
        .ceviScreenBackground()
        .navigationTitle(ChatTitle.title(for: chat, profile: profile))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Spacing.s2) {
                    UnitLogo(unitId: chat.unit.id, size: Size.avatar * 0.75)
                    Text(ChatTitle.title(for: chat, profile: profile)).font(.headline).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        // Pushes for this chat stay hidden while it is open.
        .onAppear { appState.openChatId = chat.id }
        .onDisappear { if appState.openChatId == chat.id { appState.openChatId = nil } }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.poll(client: appState.client)
        }
    }

    private var leaderNames: String { chat.unitLeaders.map(\.shortName).joined(separator: ", ") }

    private var directNotice: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if !chat.unitLeaders.isEmpty {
                if profile.isUnitLeader(of: chat.unit.id) {
                    Text("Mitlesen: \(leaderNames)")
                } else {
                    Text("Deine Nachricht geht an die ganze Stufenleitung: **\(leaderNames)**")
                }
            }
            Text("Bitte nur das Nötigste schreiben, keine Diagnosen.").bold()
        }
        .font(.subheadline)
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .accessibilityElement(children: .combine)
    }

    /// Ids of the messages that start a new day, so a day separator goes above them.
    private var dayStarts: Set<UUID> {
        var result = Set<UUID>()
        var previous: Date?
        for message in model.displayMessages {
            if previous.map({ !DateFormats.calendar.isDate($0, inSameDayAs: message.createdAt) }) ?? true {
                result.insert(message.id)
            }
            previous = message.createdAt
        }
        return result
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s3) {
                    if model.canLoadOlder {
                        Button("Ältere Nachrichten laden") { Task { await model.loadOlder(client: appState.client) } }
                            .frame(maxWidth: .infinity, minHeight: Size.touchTarget)
                            .disabled(model.isLoadingOlder)
                    }
                    if let error = model.error { ErrorRow(text: error) }
                    let starts = dayStarts
                    ForEach(model.displayMessages) { message in
                        if starts.contains(message.id) {
                            Text(ChatDate.day(message.createdAt))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.ceviOnSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .accessibilityAddTraits(.isHeader)
                        }
                        MessageRow(message: message).id(message.id)
                    }
                }
                .padding(Spacing.s4)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.first?.id) { _, newest in
                if let newest { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(newest, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if let error = model.sendError { ErrorRow(text: error) }
            if draft.count >= ChatRules.counterFrom {
                Text("\(draft.count) von \(ChatRules.maxLength) Zeichen")
                    .font(.caption)
                    .foregroundStyle(Color.ceviOnSecondaryContainer)
            }
            HStack(alignment: .bottom, spacing: Spacing.s2) {
                TextField("Nachricht schreiben", text: $draft, prompt: Text("Nachricht schreiben"), axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s2)
                    .frame(minHeight: Size.touchTarget)
                    .background(Color.ceviSurfaceContainerLow, in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border))
                Button {
                    Task {
                        if await model.send(draft, client: appState.client) {
                            draft = ""
                            // Focus stays on the button; the new bubble alone is not announced.
                            AccessibilityNotification.Announcement(String(localized: "Nachricht gesendet")).post()
                        }
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.ceviOnPrimary)
                        .frame(minWidth: Size.button, minHeight: Size.touchTarget)
                        .background(Color.ceviPrimary, in: .capsule)
                }
                .accessibilityLabel(Text("Senden"))
                .accessibilityInputLabels([Text("Senden"), Text("Nachricht senden")])
                .disabled(ChatRules.sendableText(draft) == nil || model.isSending)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.ceviSecondaryContainer)
    }
}
