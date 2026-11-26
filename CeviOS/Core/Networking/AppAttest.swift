import CryptoKit
import DeviceCheck
import Foundation
import Security

/// What the app needs from Apple App Attest. The real implementation sits on `DCAppAttestService`; tests use a fake.
/// Neither the key ID nor any proof is ever logged.
nonisolated protocol AppAttestProviding: Sendable {
    /// `false` on the simulator and on devices without App Attest: sign-in then runs without proof.
    var isSupported: Bool { get }
    /// New key, base64 key ID.
    func generateKey() async throws -> String
    /// Attestation of a new key (first proof only).
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    /// Assertion of a confirmed key (every later proof).
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

nonisolated struct DeviceCheckAppAttest: AppAttestProviding {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }
    func generateKey() async throws -> String { try await DCAppAttestService.shared.generateKey() }
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

/// Where the confirmed key ID lives. The Keychain in production, memory in tests.
nonisolated protocol AppAttestKeyStore: Sendable {
    func read() -> String?
    func write(_ keyId: String)
    func delete()
}

/// Provider and key store of one client. `nil` in `APIClient` means: no proof, sign-in as before.
nonisolated struct AppAttestSetup: Sendable {
    let provider: any AppAttestProviding
    let keyStore: any AppAttestKeyStore

    static var device: AppAttestSetup { AppAttestSetup(provider: DeviceCheckAppAttest(), keyStore: KeychainAppAttestKeyStore()) }
}

/// The key ID in the Keychain: only after unlock, only this device (same care as `KeychainCookieStore`).
nonisolated struct KeychainAppAttestKeyStore: AppAttestKeyStore {
    private let service: String
    private let account = "schluessel"

    init(service: String = (Bundle.main.bundleIdentifier ?? "ch.cevios") + ".nachweis") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ keyId: String) {
        let data = Data(keyId.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var new = query
            new[kSecValueData as String] = data
            new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(new as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// `bindung = SHA-256(nonce + "\n" + lowercase username)`: ties the proof of the operating system to one challenge and one
/// user name (`clientDataHash` for App Attest).
nonisolated enum AppAttestBinding {
    static func hash(nonce: String, username: String) -> Data {
        Data(SHA256.hash(data: Data("\(nonce)\n\(username.lowercased())".utf8)))
    }
}

// MARK: Wire types (`AppNachweisChallengeAnfrage`, `AppNachweisChallenge`, `AppNachweisAnfrage`, `AppNachweisTicket`)

nonisolated struct AppAttestChallengeRequest: Encodable, Sendable {
    let plattform = "ios"
}

nonisolated struct AppAttestChallenge: Decodable, Equatable, Sendable {
    let nonce: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case nonce
        case expiresAt = "laeuftAb"
    }
}

/// Exactly one of `attestation` and `assertion` is set (the encoder leaves out the `nil` one).
nonisolated struct AppAttestProofRequest: Encodable, Sendable {
    let plattform = "ios"
    let nonce: String
    let benutzername: String
    let schluesselId: String
    let attestation: String?
    let assertion: String?
}

nonisolated struct AppAttestTicket: Decodable, Sendable {
    let ticket: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case ticket
        case expiresAt = "laeuftAb"
    }
}
