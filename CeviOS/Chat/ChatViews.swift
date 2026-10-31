import SwiftUI

struct ChatListView: View {
    @Environment(AppState.self) private var appState
    let model: ChatListModel
    let profile: Profile
    @Binding var path: [UUID]
    @State private var showsNewMessage = false

    private var groupChats: [ChatSummary] { model.chats.filter { $0.kind == .group } }
    private var directChats: [ChatSummary] { model.chats.filter { $0.kind == .direct } }
    private var isParent: Bool { !profile.children.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !model.hasLoaded, let error = model.error {
                    ErrorRow(text: error).padding()
                } else if !model.hasLoaded {
                    ProgressView().accessibilityLabel(Text("Lädt"))
                } else if model.chats.isEmpty && !isParent {
                    ContentUnavailableView("Keine Chats", systemImage: "bubble.left.and.bubble.right")
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ceviScreenBackground()
            .navigationTitle("Chat")
            .toolbar {
                if isParent {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsNewMessage = true } label: {
                            Label("Neue Nachricht", systemImage: "square.and.pencil")
                        }
                        .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
                    }
                }
            }
            .sheet(isPresented: $showsNewMessage) {
                NewMessageSheet(model: model, profile: profile) { id in
                    showsNewMessage = false
                    path.append(id)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let chat = model.chats.first(where: { $0.id == id }) { ChatView(chat: chat, profile: profile) }
            }
        }
    }

    private var list: some View {
        List {
            if !groupChats.isEmpty {
                Section { rows(groupChats) } header: { SectionTitle(text: "Gruppen") }
            }
            if !directChats.isEmpty {
                Section { rows(directChats) } header: { SectionTitle(text: "Mit der Stufenleitung") }
            }
            if isParent && directChats.isEmpty {
                Section {} footer: {
                    Text("Neue Nachricht an die Stufenleitung: Stift oben rechts.")
                        .font(.footnote)
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(client: appState.client) }
    }

    private func rows(_ chats: [ChatSummary]) -> some View {
        ForEach(chats) { chat in
            NavigationLink(value: chat.id) { ChatRow(chat: chat, profile: profile) }
                .listRowBackground(Color.ceviSurfaceContainerLow)
        }
    }
}

private struct SectionTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ceviOnSurfaceVariant)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

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
                }
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
            let id = try await client.openDirectChat(unitId: unitId)
            // The destination looks the chat up in the list, so the new chat must be loaded first.
            await model.load(client: client)
            open(id)
        } catch let apiError as APIError {
            error = apiError.displayText
        } catch {
            self.error = APIError.network.displayText
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

/// Short time stamps in Swiss German: today the time, yesterday "Gestern", this week the weekday, else the date.
nonisolated enum ChatDate {
    private static let locale = Locale(identifier: "de_CH")

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: DateFormats.timeZone))
    }

    static func listStamp(_ date: Date, now: Date = .now) -> String {
        let calendar = DateFormats.calendar
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if calendar.isDateInYesterday(date) { return String(localized: "Gestern") }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).weekday(.abbreviated))
        }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, timeZone: DateFormats.timeZone))
    }

    static func day(_ date: Date) -> String {
        let calendar = DateFormats.calendar
        if calendar.isDateInToday(date) { return String(localized: "Heute") }
        if calendar.isDateInYesterday(date) { return String(localized: "Gestern") }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: DateFormats.timeZone))
    }
}

struct ChatRow: View {
    let chat: ChatSummary
    let profile: Profile

    private var title: String { ChatTitle.title(for: chat, profile: profile) }
    private var preview: String? {
        chat.lastMessage.map { "\($0.isOwn ? String(localized: "Du") : $0.author.displayName): \($0.text)" }
    }
    private var stamp: String? { chat.lastMessage.map { ChatDate.listStamp($0.createdAt) } }
    private var isUnread: Bool { chat.unread > 0 }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(.body.weight(isUnread ? .bold : .semibold))
                    .foregroundStyle(Color.ceviOnSurface)
                if let preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? Color.ceviOnSurface : Color.ceviOnSurfaceVariant)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Spacing.s2)
            VStack(alignment: .trailing, spacing: Spacing.s2) {
                if let stamp {
                    Text(stamp).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                if isUnread {
                    // Number plus bold title, so the unread state does not rely on color.
                    Text("\(chat.unread)")
                        .font(.caption.bold())
                        .foregroundStyle(Color.ceviOnPrimary)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, Spacing.s1)
                        .background(Color.ceviPrimary, in: .capsule)
                }
            }
        }
        // Design row height 72 pt, built from tokens (44 + 32 - 4) since Design.swift has no row token.
        .frame(minHeight: Size.touchTarget + Spacing.s8 - Spacing.s1, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [title]
        if isUnread { parts.append(String(localized: "\(chat.unread) ungelesen")) }
        if let preview { parts.append(preview) }
        if let stamp { parts.append(stamp) }
        return parts.joined(separator: ", ")
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
        .ceviScreenBackground()
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

    private var leaderNames: String { chat.unitLeaders.map(\.displayName).joined(separator: ", ") }

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
                if let newest { withAnimation { proxy.scrollTo(newest, anchor: .bottom) } }
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
                TextField("Nachricht", text: $draft, prompt: Text("Nachricht schreiben"), axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s2)
                    .frame(minHeight: Size.touchTarget)
                    .background(Color.ceviSurfaceContainerLow, in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border))
                Button {
                    Task { if await model.send(draft, client: appState.client) { draft = "" } }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.ceviOnPrimary)
                        .frame(minWidth: Size.button, minHeight: Size.touchTarget)
                        .background(Color.ceviPrimary, in: .capsule)
                }
                .accessibilityLabel(Text("Senden"))
                .disabled(ChatRules.sendableText(draft) == nil || model.isSending)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.ceviSecondaryContainer)
    }
}

struct MessageRow: View {
    let message: ChatMessage

    private var bubbleShape: UnevenRoundedRectangle {
        // The corner towards the sender stays small, like a speech bubble tail.
        UnevenRoundedRectangle(
            topLeadingRadius: Radius.lg,
            bottomLeadingRadius: message.isOwn ? Radius.lg : Spacing.s2,
            bottomTrailingRadius: message.isOwn ? Spacing.s2 : Radius.lg,
            topTrailingRadius: Radius.lg,
            style: .continuous
        )
    }

    private var senderLabel: String {
        let name = message.author.ceviName ?? message.author.name
        return message.author.isUnitLeader ? String(localized: "\(name) · SL") : name
    }

    private var senderAccessibility: String {
        message.author.displayName + (message.author.isUnitLeader ? String(localized: " (Stufenleitung)") : "")
    }

    var body: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: Spacing.s1) {
            // Own messages sit on the right and are read as "Du", so the difference does not rely on color.
            if !message.isOwn {
                Text(senderLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ceviAccent)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.isOwn ? Color.ceviOnSecondary : Color.ceviOnSurface)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
                .background(message.isOwn ? Color.ceviSecondary : Color.ceviSurfaceContainerLow, in: bubbleShape)
                .overlay {
                    if !message.isOwn { bubbleShape.strokeBorder(Color.ceviOutlineVariant, lineWidth: Size.border) }
                }
            if let program = message.program {
                Label(program.title, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            Text(message.isOwn ? "\(ChatDate.time(message.createdAt)) · Gesendet" : "\(ChatDate.time(message.createdAt))")
                .font(.caption)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
        .padding(message.isOwn ? .leading : .trailing, Spacing.s8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [message.isOwn ? String(localized: "Du") : senderAccessibility, message.text]
        if let program = message.program { parts.append(program.title) }
        parts.append(ChatDate.time(message.createdAt))
        if message.isOwn { parts.append(String(localized: "Gesendet")) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Nachrichten") {
    let leader = ChatAuthor(id: UUID(), name: "Sarah Muster", ceviName: "Sarah", imageURL: nil, isUnitLeader: true)
    let me = ChatAuthor(id: UUID(), name: "Robin Lehmann", ceviName: nil, imageURL: nil, isUnitLeader: false)
    ScrollView {
        VStack(spacing: Spacing.s3) {
            MessageRow(message: ChatMessage(id: UUID(), text: "Hoi zäme, Noah kommt am Samstag etwas später, etwa 14:30.",
                                            createdAt: .now, author: me, program: nil, isOwn: true))
            MessageRow(message: ChatMessage(id: UUID(), text: "Kein Problem, wir sind bis 15:00 beim Gemeindehaus.",
                                            createdAt: .now, author: leader, program: nil, isOwn: false))
        }
        .padding(Spacing.s4)
    }
    .ceviScreenBackground()
}
