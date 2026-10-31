import SwiftUI

/// Chat list. Polled every 30 seconds while the app is in the foreground.
@MainActor @Observable
final class ChatListModel {
    private(set) var chats: [ChatSummary] = []
    private(set) var error: String?
    private(set) var hasLoaded = false

    var totalUnread: Int { ChatRules.totalUnread(chats) }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            chats = try await client.chats()
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let apiError as APIError {
            error = apiError.displayText
        } catch {
            self.error = APIError.network.displayText
        }
    }

    /// Runs until cancelled. Started with `.task(id: scenePhase)`, so it only runs in the foreground.
    func poll(client: APIClient?) async {
        while !Task.isCancelled {
            await load(client: client)
            try? await Task.sleep(for: ChatRules.listPollInterval)
        }
    }
}
