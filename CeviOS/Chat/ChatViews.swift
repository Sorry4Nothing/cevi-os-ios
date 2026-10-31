import SwiftUI

struct ChatListView: View {
    @Environment(AppState.self) private var appState
    let model: ChatListModel
    let profile: Profile

    var body: some View {
        NavigationStack {
            Group {
                if !model.hasLoaded, let error = model.error {
                    ErrorRow(text: error).padding()
                } else if !model.hasLoaded {
                    ProgressView().accessibilityLabel(Text("Lädt"))
                } else if model.chats.isEmpty {
                    ContentUnavailableView("Keine Chats", systemImage: "bubble.left.and.bubble.right")
                } else {
                    List(model.chats) { chat in
                        NavigationLink(value: chat.id) { ChatRow(chat: chat, profile: profile) }.frame(minHeight: 44)
                    }
                    .refreshable { await model.load(client: appState.client) }
                }
            }
            .navigationTitle("Chat")
            .navigationDestination(for: UUID.self) { id in
                if let chat = model.chats.first(where: { $0.id == id }) { ChatView(chat: chat, profile: profile) }
            }
        }
    }
}

nonisolated enum ChatTitle {
    /// Group chat: the unit. Direct chat: for parents the unit leaders, for unit leaders the parent.
    static func title(for chat: ChatSummary, profile: Profile) -> String {
        switch chat.kind {
        case .group:
            String(localized: "Gruppenchat \(chat.unit.name)")
        case .direct:
            if let parent = chat.parent, profile.isUnitLeader(of: chat.unit.id) {
                parent.displayName
            } else {
                String(localized: "Stufenleitung \(chat.unit.name)")
            }
        }
    }
}

struct ChatRow: View {
    let chat: ChatSummary
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ChatTitle.title(for: chat, profile: profile)).font(.headline)
                Spacer()
                if chat.unread > 0 {
                    // Number in text form, so the unread state does not rely on color.
                    Text("\(chat.unread) ungelesen").font(.caption.bold())
                }
            }
            if let last = chat.lastMessage {
                Text("\(last.isOwn ? String(localized: "Du") : last.author.displayName): \(last.text)")
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    let chat: ChatSummary
    let profile: Profile
    @State private var model: ChatModel
    @State private var draft = ""

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
        .navigationTitle(ChatTitle.title(for: chat, profile: profile))
        .navigationBarTitleDisplayMode(.inline)
        // Pushes for this chat stay hidden while it is open.
        .onAppear { appState.openChatId = chat.id }
        .onDisappear { if appState.openChatId == chat.id { appState.openChatId = nil } }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.poll(client: appState.client)
        }
    }

    private var directNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bitte nur das Nötigste schreiben, keine Diagnosen.").font(.callout.bold())
            if !chat.unitLeaders.isEmpty {
                Text("Mitlesen: \(chat.unitLeaders.map(\.displayName).joined(separator: ", "))").font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .combine)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.canLoadOlder {
                        Button("Ältere Nachrichten laden") { Task { await model.loadOlder(client: appState.client) } }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(model.isLoadingOlder)
                    }
                    if let error = model.error { ErrorRow(text: error) }
                    ForEach(model.displayMessages) { message in
                        MessageRow(message: message).id(message.id)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.first?.id) { _, newest in
                if let newest { withAnimation { proxy.scrollTo(newest, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = model.sendError { ErrorRow(text: error) }
            if draft.count >= ChatRules.counterFrom {
                Text("\(draft.count) von \(ChatRules.maxLength) Zeichen").font(.caption)
            }
            HStack(alignment: .bottom) {
                TextField("Nachricht", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                Button {
                    Task { if await model.send(draft, client: appState.client) { draft = "" } }
                } label: {
                    Image(systemName: "paperplane.fill").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Senden"))
                .disabled(ChatRules.sendableText(draft) == nil || model.isSending)
            }
        }
        .padding()
        .background(.bar)
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
            // Own messages sit on the right and say "Du", so the difference does not rely on color.
            Text(message.isOwn ? String(localized: "Du") : message.author.displayName + (message.author.isUnitLeader ? String(localized: " (Stufenleitung)") : ""))
                .font(.caption.bold())
            Text(message.text)
                .padding(10)
                .background(message.isOwn ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 12))
            if let program = message.program {
                Label(program.title, systemImage: "calendar").font(.caption)
            }
            Text(message.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone))
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}
