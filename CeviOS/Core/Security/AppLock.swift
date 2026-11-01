import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// App lock: Face ID or Touch ID with the device code as fallback. A hurdle inside the app, not encryption.
/// It applies on cold start and after 5 minutes in the background.
@MainActor @Observable
final class AppLock {
    nonisolated static let timeout: TimeInterval = 5 * 60
    // The stored key string stays as is so existing installs keep their setting.
    private static let parentsKey = "sperreFuerElternAktiv"

    private(set) var isLocked = true
    private(set) var failed = false
    private var backgroundSince: Date?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    #if DEBUG
    /// UI tests: the automatic unlock on appear is skipped once, so a locked start shows the lock screen.
    private var holdsLockOnce = false

    /// UI-test backend: starts unlocked (or locked) without Face ID.
    init(defaults: UserDefaults, isLocked: Bool) {
        self.defaults = defaults
        self.isLocked = isLocked
        holdsLockOnce = isLocked
    }
    #endif

    /// Parents can switch the lock off; it is suggested (on) anyway. Leaders and unit leaders cannot.
    var parentsLockEnabled: Bool {
        get { defaults.object(forKey: Self.parentsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.parentsKey) }
    }

    func isRequired(for profile: Profile) -> Bool {
        profile.isLeader || parentsLockEnabled
    }

    /// Is a device code set? Without it nothing can be locked.
    static var deviceCodeSet: Bool {
        #if DEBUG
        // The simulator has no device code; the UI tests still need the lock screen.
        if UITestLaunch.isActive { return true }
        #endif
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    nonisolated static func lockDue(backgroundSince: Date?, now: Date) -> Bool {
        guard let backgroundSince else { return false }
        return now.timeIntervalSince(backgroundSince) >= timeout
    }

    func scenePhase(_ phase: ScenePhase, now: Date = .now) {
        switch phase {
        case .background:
            backgroundSince = backgroundSince ?? now
        case .active:
            if Self.lockDue(backgroundSince: backgroundSince, now: now) { isLocked = true }
            backgroundSince = nil
        default:
            break
        }
    }

    /// Asks for Face ID, Touch ID or the device code.
    func unlock() async {
        #if DEBUG
        // UI tests: no system authentication sheet. «Entsperren» unlocks; the automatic attempt of a locked start is skipped once.
        if UITestLaunch.isActive {
            if holdsLockOnce {
                holdsLockOnce = false
            } else {
                isLocked = false
                failed = false
            }
            return
        }
        #endif
        failed = false
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Cevi OS entsperren")
            )
            isLocked = !ok
            failed = !ok
        } catch {
            failed = true
        }
    }

    /// After sign-out the next person starts locked again.
    func reset() {
        isLocked = true
        failed = false
        backgroundSince = nil
    }
}
