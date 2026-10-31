import Foundation

nonisolated struct PushTokenBody: Encodable, Sendable {
    let token: String
    let platform = "ios"

    enum CodingKeys: String, CodingKey { case token, platform = "plattform" }
}

extension APIClient {
    /// `PUT /push-token`. One token per session; a new one replaces the old.
    func registerPushToken(_ token: String) async throws {
        guard PushToken.isValid(token) else { return }
        try await send("PUT", "/api/v1/push-token", body: PushTokenBody(token: token))
    }
}
