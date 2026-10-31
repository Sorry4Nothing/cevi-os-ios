import Foundation

nonisolated enum SignInResult: Equatable, Sendable {
    case signedIn
    /// Second factor required; the intermediate cookie is stored.
    case secondFactor
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
        return probe?.twoFactorRedirect == true ? .secondFactor : .signedIn
    }

    /// `verify-totp` (6 digits) or `verify-backup-code` (`xxxxx-xxxxx`).
    func confirmSecondFactor(code: String, isBackupCode: Bool) async throws {
        let path = isBackupCode ? "/api/auth/two-factor/verify-backup-code" : "/api/auth/two-factor/verify-totp"
        try await send("POST", path, body: ["code": code])
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
    func signOut(everywhere: Bool = false) async {
        _ = try? await send("POST", everywhere ? "/api/auth/revoke-sessions" : "/api/auth/sign-out", body: [String: String]())
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

    /// `restartSignIn` is true when the intermediate step is invalid and the person has to start over.
    static func secondFactor(_ error: APIError) -> (text: String, restartSignIn: Bool) {
        switch error.code {
        case "INVALID_CODE", "INVALID_BACKUP_CODE":
            (String(localized: "Der Code stimmt nicht."), false)
        case "TOO_MANY_ATTEMPTS_REQUEST_NEW_CODE", "INVALID_TWO_FACTOR_COOKIE", "TOTP_NOT_ENABLED", "BACKUP_CODES_NOT_ENABLED":
            (String(localized: "Bitte noch einmal anmelden."), true)
        default:
            (error.displayText, false)
        }
    }
}
