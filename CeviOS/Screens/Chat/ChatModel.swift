import SwiftUI

/// One open chat. Polled every 5 seconds while it is open and the app is in the foreground.
@MainActor @Observable
final class ChatModel {
    let chatId: UUID
    private(set) var messages: [ChatMessage] = []
    private(set) var older = PageSequence<ChatMessage>()
    private(set) var error: String?
    private(set) var hasLoaded = false
    private(set) var isSending = false
    private(set) var isLoadingOlder = false
    var sendError: String?
    private var lastReadId: UUID?

    init(chatId: UUID) {
        self.chatId = chatId
    }

    /// Oldest first, for display.
    var displayMessages: [ChatMessage] { messages.reversed() }
    var canLoadOlder: Bool { hasLoaded && !older.isAtEnd }

    func loadNewest(client: APIClient?) async {
        guard let client else { return }
        do {
            let page = try await client.messages(chatId: chatId)
            if !hasLoaded {
                older.append([], next: page.next)
                hasLoaded = true
            }
            messages = ChatRules.merge(existing: messages, newest: page.messages)
            error = nil
        } catch is CancellationError {
            return
        } catch let apiError as APIError {
            error = apiError.displayText
            return
        } catch {
            self.error = APIError.network.displayText
            return
        }
        await markReadIfNeeded(client: client)
    }

    func loadOlder(client: APIClient?) async {
        guard let client, let cursor = older.next, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await client.messages(chatId: chatId, before: cursor)
            older.append([], next: page.next)
            messages = ChatRules.merge(existing: messages, newest: page.messages)
        } catch {
            self.error = (error as? APIError)?.displayText ?? APIError.network.displayText
        }
    }

    /// Returns true if the message was sent.
    func send(_ input: String, programId: UUID? = nil, client: APIClient?) async -> Bool {
        guard let client, !isSending, let text = ChatRules.sendableText(input) else { return false }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await client.sendMessage(chatId: chatId, text: text, programId: programId)
        } catch let apiError as APIError {
            sendError = ChatRules.sendError(apiError)
            return false
        } catch {
            sendError = APIError.network.displayText
            return false
        }
        await loadNewest(client: client)
        return true
    }

    /// Marks as read when the newest message is new since the last time.
    private func markReadIfNeeded(client: APIClient) async {
        guard let newest = messages.first?.id, newest != lastReadId else { return }
        if (try? await client.markRead(chatId: chatId)) != nil { lastReadId = newest }
    }

    func poll(client: APIClient?) async {
        while !Task.isCancelled {
            await loadNewest(client: client)
            try? await Task.sleep(for: ChatRules.openChatPollInterval)
        }
    }
}
