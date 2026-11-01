import Foundation

nonisolated enum SignInResult: Equatable, Sendable {
    case signedIn
    /// The account has a second factor (admins only). The app does not support it; admins use the web admin area.
    case adminOnly
}

extension APIClient {
    /// `POST /api/auth/sign-in/username`. Old cookies are discarded first.
    func signIn(username: String, password: String) async throws -> SignInResult {
        clearCookies()
        let data = try await send(
            "POST", "/api/auth/sign-in/username",
            body: ["username": username, "password": password]
        )
        return Self.signInResult(from: data)
    }

    nonisolated static func signInResult(from data: Data) -> SignInResult {
        struct Probe: Decodable { let twoFactorRedirect: Bool? }
        let probe = try? JSONDecoder().decode(Probe.self, from: data)
        return probe?.twoFactorRedirect == true ? .adminOnly : .signedIn
    }

    /// `GET /api/auth/get-session`: extends the session. `false` if the server knows no session.
    func checkSession() async throws -> Bool {
        let data = try await send("GET", "/api/auth/get-session")
        return Self.sessionExists(in: data)
    }

    nonisolated static func sessionExists(in data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text != "null"
    }

    func loadProfile() async throws -> Profile {
        try await load("GET", "/api/v1/ich")
    }

    func changePassword(current: String, new: String) async throws {
        try await send("POST", "/api/auth/change-password", body: ["currentPassword": current, "newPassword": new])
    }

    func acknowledgePrivacy() async throws {
        try await send("POST", "/api/v1/ich/datenschutz")
    }

    /// Ends the session on the server (errors don't matter, e.g. offline) and discards the cookie.
    func signOut() async {
        _ = try? await send("POST", "/api/auth/sign-out", body: [String: String]())
        clearCookies()
    }
}

/// Texts for sign-in errors. better-auth codes (English uppercase) are not meant for display;
/// a German text stands in for them here. Everything else shows the server's text.
nonisolated enum AuthMessages {
    static func changePassword(_ error: APIError) -> String {
        switch error.code {
        case "PASSWORD_TOO_SHORT": String(localized: "Das neue Passwort muss mindestens 12 Zeichen haben.")
        case "PASSWORD_TOO_LONG": String(localized: "Das neue Passwort darf höchstens 128 Zeichen haben.")
        case "INVALID_PASSWORD": String(localized: "Das aktuelle Passwort stimmt nicht.")
        case "PASSWORD_COMPROMISED": String(localized: "Dieses Passwort stammt aus einem bekannten Datenleck. Bitte ein anderes wählen.")
        default: error.displayText
        }
    }

    /// Shown when an admin signs in: admins work in the web admin area, not in the app.
    static var adminOnly: String {
        String(localized: "Admins melden sich im Admin-Bereich an. Die App ist für Eltern und Leitende.")
    }
}
