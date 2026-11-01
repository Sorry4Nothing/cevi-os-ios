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
                    LoadingView(label: "Lädt")
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
                    // Without the shared glass the button keeps its own 44 pt frame (iOS 27 sizes the glass at 36 pt).
                    .sharedBackgroundVisibility(.hidden)
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
                // A plain row instead of a section footer: footers do not follow Dynamic Type reliably.
                Section {
                    Text("Neue Nachricht an die Stufenleitung: Stift oben rechts.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                        .listRowBackground(Color.clear)
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
