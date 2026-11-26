import CryptoKit
import Foundation
import Security

/// Where the key of the cache lives. The Keychain in production, memory in tests.
nonisolated protocol CampCacheKeyStore: Sendable {
    /// The key; a new one if there is none yet.
    func key() -> SymmetricKey
    func delete()
}

/// The key is one Keychain entry: only after unlock, only this device (like the session cookies).
nonisolated struct KeychainCampCacheKeyStore: CampCacheKeyStore {
    private let service = (Bundle.main.bundleIdentifier ?? "ch.cevios") + ".lagercache"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "key"]
    }

    func key() -> SymmetricKey {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        var new = query
        new[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        SecItemAdd(new as CFDictionary, nil)
        return key
    }

    func delete() { SecItemDelete(query as CFDictionary) }
}

nonisolated final class MemoryCampCacheKeyStore: CampCacheKeyStore {
    private let value = SymmetricKey(size: .bits256)
    func key() -> SymmetricKey { value }
    func delete() {}
}

/// One encrypted file per camp (and one for the camp list) in Application Support: AES-GCM, the file name is part of the
/// authenticated data, so a file moved to another name does not open. Complete file protection, excluded from the device
/// backup. A file that does not open (changed, wrong key) is deleted. Writes nothing to the log.
actor CampFileCache: CampCache {
    private let directory: URL
    private let keys: any CampCacheKeyStore

    init(
        directory: URL = URL.applicationSupportDirectory.appending(path: "LagerCache", directoryHint: .isDirectory),
        keys: any CampCacheKeyStore = KeychainCampCacheKeyStore()
    ) {
        self.directory = directory
        self.keys = keys
    }

    func entry(scope: UUID?, key: String) -> CampCacheEntry? { read(scope)[key] }

    func store(_ entry: CampCacheEntry, scope: UUID?, key: String) {
        var all = read(scope)
        all[key] = entry
        write(all, scope)
    }

    func remove(scope: UUID?, key: String) {
        var all = read(scope)
        guard all.removeValue(forKey: key) != nil else { return }
        write(all, scope)
    }

    func removeCamp(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }

    func keepOnly(campIds ids: Set<UUID>) {
        let keep = Set(ids.map { url($0).lastPathComponent } + [url(nil).lastPathComponent])
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        keys.delete()
    }

    func url(_ scope: UUID?) -> URL {
        directory.appending(path: (scope?.uuidString.lowercased() ?? "list") + ".cache", directoryHint: .notDirectory)
    }

    private func read(_ scope: UUID?) -> [String: CampCacheEntry] {
        let file = url(scope)
        guard let blob = try? Data(contentsOf: file) else { return [:] }
        guard
            let box = try? AES.GCM.SealedBox(combined: blob),
            let plain = try? AES.GCM.open(box, using: keys.key(), authenticating: Data(file.lastPathComponent.utf8)),
            let all = try? JSONDecoder().decode([String: CampCacheEntry].self, from: plain)
        else {
            try? FileManager.default.removeItem(at: file)
            return [:]
        }
        return all
    }

    private func write(_ all: [String: CampCacheEntry], _ scope: UUID?) {
        let file = url(scope)
        guard
            let plain = try? JSONEncoder().encode(all),
            let box = try? AES.GCM.seal(plain, using: keys.key(), authenticating: Data(file.lastPathComponent.utf8)),
            let blob = box.combined
        else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            try? folder.setResourceValues(excluded)
            try blob.write(to: file, options: [.atomic, .completeFileProtection])
            var item = file
            try? item.setResourceValues(excluded)
        } catch {}
    }
}
