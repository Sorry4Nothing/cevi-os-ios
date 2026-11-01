import Foundation
import Security

/// Storage for cookies (`name=value`, without attributes). The Keychain in production, memory in tests.
nonisolated protocol CookieStore: Sendable {
    func read() -> [String: String]
    func write(_ cookies: [String: String])
    func delete()
}

/// Pure cookie logic: take over from `Set-Cookie` and emit as `Cookie` header.
nonisolated enum CookieJar {
    /// Takes over all `Set-Cookie` headers of the response. A new cookie replaces the old one, `Max-Age=0` (or an
    /// expiry in the past) deletes it.
    static func updated(_ existing: [String: String], from response: HTTPURLResponse, now: Date = .now) -> [String: String] {
        guard let url = response.url else { return existing }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let name = pair.key as? String, let value = pair.value as? String {
                result[name] = value
            }
        }
        var result = existing
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            let maxAge = cookie.properties?[.maximumAge] as? String
            let expired = maxAge.flatMap(Int.init).map { $0 <= 0 } ?? false
                || (cookie.expiresDate.map { $0 <= now } ?? false)
            if expired {
                result[cookie.name] = nil
            } else {
                result[cookie.name] = cookie.value
            }
        }
        return result
    }

    /// Value for the `Cookie` header, pairs separated by `; `. `nil` without cookies.
    static func header(_ cookies: [String: String]) -> String? {
        guard !cookies.isEmpty else { return nil }
        return cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}

/// Stores the cookies as one entry in the Keychain: only after unlock, only this device, no biometric requirement.
nonisolated struct KeychainCookieStore: CookieStore {
    private let service: String
    private let account = "cookies"

    init(service: String = (Bundle.main.bundleIdentifier ?? "ch.cevios") + ".sitzung") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> [String: String] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let cookies = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return cookies
    }

    func write(_ cookies: [String: String]) {
        guard !cookies.isEmpty else {
            delete()
            return
        }
        guard let data = try? JSONEncoder().encode(cookies) else { return }
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

/// iOS keeps Keychain entries after an uninstall. On the first launch after an install we delete them.
nonisolated enum FirstLaunchCleanup {
    static let key = "installationBereinigt"

    static func run(cookieStore: some CookieStore, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        cookieStore.delete()
        defaults.set(true, forKey: key)
    }
}
