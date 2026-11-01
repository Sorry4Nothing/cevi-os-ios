import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// App lock with Face ID or Touch ID only (no device-code fallback). Opt-in, off by default.
/// A hurdle inside the app, not encryption of the session; the password is never stored.
/// It applies on cold start and after at least 30 seconds in the background, and only while there is a session.
@MainActor @Observable
final class AppLock {
    nonisolated static let timeout: TimeInterval = 30
    private static let enabledKey = "biometricLockEnabled"

    private(set) var isLocked = true
    private(set) var failed = false
    private(set) var isEnabled: Bool
    private var backgroundSince: Date?
    private let defaults: UserDefaults
    private let credential: any BiometricCredential
    /// Called when the biometric set changed: sign out and explain why. Wired in `CeviOSApp`.
    var biometryChanged: @MainActor () async -> Void = {}

    init(defaults: UserDefaults = .standard, credential: any BiometricCredential = KeychainBiometricCredential()) {
        self.defaults = defaults
        self.credential = credential
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    #if DEBUG
    /// UI tests: the automatic unlock on appear is skipped once, so a locked start shows the lock screen.
    private var holdsLockOnce = false

    /// UI-test backend: no Keychain and no Face ID; a locked start switches the lock on.
    convenience init(uiTestLocked isLocked: Bool) {
        let defaults = UserDefaults(suiteName: "uitest.applock") ?? .standard
        defaults.set(isLocked, forKey: Self.enabledKey)
        self.init(defaults: defaults, credential: FakeBiometricCredential())
        self.isLocked = isLocked
        holdsLockOnce = isLocked
    }
    #endif

    /// Face ID or Touch ID enrolled. Without biometrics the toggle is hidden and nothing locks.
    var biometryType: LABiometryType { credential.biometryType }
    var isAvailable: Bool { biometryType != .none }

    /// The lock screen is shown only while this is true.
    var requiresUnlock: Bool { isEnabled && isAvailable && isLocked }

    var toggleTitle: LocalizedStringKey {
        biometryType == .touchID ? "Mit Touch ID entsperren" : "Mit Face ID entsperren"
    }

    var symbol: String { biometryType == .touchID ? "touchid" : "faceid" }

    /// Toggle: on creates the key, off deletes it. The setting survives sign-out.
    func setEnabled(_ on: Bool) {
        if on {
            do { try credential.create() } catch { return }
            isLocked = false
        } else {
            credential.delete()
        }
        isEnabled = on
        defaults.set(on, forKey: Self.enabledKey)
    }

    nonisolated static func lockDue(backgroundSince: Date?, now: Date) -> Bool {
        guard let backgroundSince else { return false }
        return now.timeIntervalSince(backgroundSince) >= timeout
    }

    /// Returns true when the app just locked; the caller then drops the in-memory session data.
    @discardableResult
    func scenePhase(_ phase: ScenePhase, hasSession: Bool, now: Date = .now) -> Bool {
        switch phase {
        case .background:
            backgroundSince = backgroundSince ?? now
        case .active:
            defer { backgroundSince = nil }
            if isEnabled, isAvailable, hasSession, !isLocked, Self.lockDue(backgroundSince: backgroundSince, now: now) {
                isLocked = true
                return true
            }
        default:
            break
        }
        return false
    }

    /// Signing in with the password counts as unlocked; a key lost to a biometry change is created anew.
    func signedInWithPassword() {
        isLocked = false
        failed = false
        if isEnabled, !credential.exists { try? credential.create() }
    }

    /// Signs a challenge with the key; the system asks for Face ID or Touch ID.
    func unlock() async {
        #if DEBUG
        // UI tests: «Entsperren» unlocks; the automatic attempt of a locked start is skipped once.
        if holdsLockOnce {
            holdsLockOnce = false
            return
        }
        #endif
        failed = false
        switch await credential.unlock(reason: String(localized: "Cevi OS entsperren")) {
        case .success:
            isLocked = false
        case .failed:
            failed = true
        case .invalidated:
            credential.delete()
            isLocked = false
            await biometryChanged()
        }
    }
}

enum BiometricUnlockResult: Sendable, Equatable {
    case success
    /// Cancelled, not recognized or locked out; trying again is possible.
    case failed
    /// The biometric set changed, the key is gone for good.
    case invalidated
}

/// Key that is only usable after Face ID or Touch ID.
nonisolated protocol BiometricCredential: Sendable {
    var biometryType: LABiometryType { get }
    var exists: Bool { get }
    func create() throws
    func delete()
    func unlock(reason: String) async -> BiometricUnlockResult
}

/// P-256 key in the Secure Enclave with `.biometryCurrentSet`. Unlock signs a random challenge.
/// The simulator has no Secure Enclave: there a plain Keychain item with the same access control stands in.
nonisolated struct KeychainBiometricCredential: BiometricCredential {
    private static let tag = Data("ch.cevi.os.applock".utf8)
    private static let account = "applock"

    var biometryType: LABiometryType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        return context.biometryType
    }

    private func accessControl(_ flags: SecAccessControlCreateFlags) throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error
        ) else { throw error!.takeRetainedValue() as Error }
        return access
    }

    #if targetEnvironment(simulator)
    // Simulator only: no Secure Enclave. Reading the item needs biometrics, which is the unlock.
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: Self.account,
         kSecAttrService as String: "ch.cevi.os.applock"]
    }

    var exists: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var q = query
        q[kSecReturnAttributes as String] = true
        q[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(q as CFDictionary, nil) != errSecItemNotFound
    }

    func create() throws {
        delete()
        var q = query
        q[kSecAttrAccessControl as String] = try accessControl(.biometryCurrentSet)
        q[kSecValueData as String] = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func delete() { SecItemDelete(query as CFDictionary) }

    @concurrent
    func unlock(reason: String) async -> BiometricUnlockResult {
        let context = LAContext()
        context.localizedReason = reason
        var q = query
        q[kSecReturnData as String] = true
        q[kSecUseAuthenticationContext as String] = context
        switch SecItemCopyMatching(q as CFDictionary, nil) {
        case errSecSuccess: return .success
        case errSecItemNotFound: return .invalidated
        default: return .failed
        }
    }
    #else
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: Self.tag,
         kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom]
    }

    var exists: Bool { SecItemCopyMatching(keyQuery as CFDictionary, nil) == errSecSuccess }

    func create() throws {
        delete()
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Self.tag,
                kSecAttrAccessControl as String: try accessControl([.privateKeyUsage, .biometryCurrentSet]),
            ] as [String: Any],
        ]
        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            throw error!.takeRetainedValue() as Error
        }
    }

    func delete() { SecItemDelete(keyQuery as CFDictionary) }

    @concurrent
    func unlock(reason: String) async -> BiometricUnlockResult {
        let context = LAContext()
        context.localizedReason = reason
        var q = keyQuery
        q[kSecReturnRef as String] = true
        q[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let item else { return status == errSecItemNotFound ? .invalidated : .failed }
        let key = item as! SecKey // swiftlint:disable:this force_cast
        var error: Unmanaged<CFError>?
        let challenge = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        if SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, challenge as CFData, &error) != nil {
            return .success
        }
        let nsError = error?.takeRetainedValue() as Error? as NSError?
        // A key invalidated by a new biometric set reports item-not-found; a lockout is only a failure.
        return nsError?.domain == NSOSStatusErrorDomain && nsError?.code == Int(errSecItemNotFound) ? .invalidated : .failed
    }
    #endif
}

#if DEBUG
/// UI tests and unit tests: no Keychain, no prompt.
nonisolated final class FakeBiometricCredential: BiometricCredential, @unchecked Sendable {
    // shortcut: unguarded state, used from one test or the UI-test app at a time; add a lock if tests run it concurrently.
    var biometryType: LABiometryType = .faceID
    var exists = false
    var result: BiometricUnlockResult = .success

    func create() throws { exists = true }
    func delete() { exists = false }
    func unlock(reason: String) async -> BiometricUnlockResult { result }
}
#endif
