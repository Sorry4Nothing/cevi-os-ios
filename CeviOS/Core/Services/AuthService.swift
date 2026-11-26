import DeviceCheck
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
        let ticket = try await appProofTicket(username: username)
        let data = try await send(
            "POST", "/api/auth/sign-in/username",
            body: ["username": username, "password": password],
            headers: ticket.map { ["X-Cevi-Nachweis": $0] } ?? [:]
        )
        return Self.signInResult(from: data)
    }

    /// The app proof (App Attest) for this sign-in attempt: a fresh challenge, a proof bound to it and the user name, and
    /// the ticket for the header. `nil` means «sign in without a ticket»: no App Attest here (simulator), proof switched
    /// off on the server (404), or any error on the way (network, Apple, server). The proof never blocks a sign-in; the
    /// server decides whether it accepts the app without one. Only cancellation is passed on.
    /// Nothing here is logged or put into an error: not the key ID, not the proof, not the ticket.
    func appProofTicket(username: String) async throws -> String? {
        guard let setup = appAttest, setup.provider.isSupported else { return nil }
        var keyId = setup.keyStore.read()
        // Second round: after a 401 the key is replaced (an attestation is accepted once per key, a lost assertion key is gone).
        for _ in 0..<2 {
            do {
                let challenge: AppAttestChallenge = try await load("POST", "/api/v1/app/nachweis/challenge", body: AppAttestChallengeRequest())
                let hash = AppAttestBinding.hash(nonce: challenge.nonce, username: username)
                let attesting = keyId == nil
                let id: String
                if let keyId { id = keyId } else { id = try await setup.provider.generateKey() }
                let proof: Data
                do {
                    proof = attesting
                        ? try await setup.provider.attestKey(id, clientDataHash: hash)
                        : try await setup.provider.generateAssertion(id, clientDataHash: hash)
                } catch {
                    // Apple no longer knows the key (e.g. after a reinstall): forget it, the next attempt attests a new one.
                    if (error as? DCError)?.code == .invalidKey { setup.keyStore.delete() }
                    throw error
                }
                let request = AppAttestProofRequest(
                    nonce: challenge.nonce, benutzername: username, schluesselId: id,
                    attestation: attesting ? proof.base64EncodedString() : nil,
                    assertion: attesting ? nil : proof.base64EncodedString()
                )
                do {
                    let ticket: AppAttestTicket = try await load("POST", "/api/v1/app/nachweis", body: request)
                    // Remember the key only once the server has accepted it.
                    if attesting { setup.keyStore.write(id) }
                    return ticket.ticket
                } catch let error as APIError where error.kind == .unauthorized {
                    setup.keyStore.delete()
                    keyId = nil
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return nil
            }
        }
        return nil
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

    /// Shown after the app lock key was invalidated by a new Face ID or Touch ID enrollment.
    static var biometryChanged: String {
        String(localized: "Deine Biometrie hat sich geändert. Bitte melde dich mit dem Passwort an.")
    }
}
