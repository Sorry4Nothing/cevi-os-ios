import Foundation
import Testing
@testable import CeviOS

nonisolated enum Samples {
    static func profile(
        mustChangePassword: Bool = false,
        privacy: String? = "2026-10-01T10:00:00.000Z",
        roles: String = "[]"
    ) throws -> Profile {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Test Person","ceviName":null,"benutzername":"test.person",
         "mussPasswortAendern":\(mustChangePassword),"datenschutzGelesenAm":\(privacy.map { "\"\($0)\"" } ?? "null"),
         "telefon":null,"bildUrl":null,"pushChat":true,"pushProgramme":true,"admin":false,"zweiterFaktor":false,
         "rollen":\(roles),"stufen":[],"kinder":[]}
        """
        return try JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
    }
}

struct PhaseTests {
    @Test func pendingPasswordChangeComesBeforePrivacy() throws {
        let profile = try Samples.profile(mustChangePassword: true, privacy: nil)
        #expect(AppState.phase(for: profile) == .changePassword(profile))
    }

    @Test func withoutAcknowledgementPrivacyComes() throws {
        let profile = try Samples.profile(privacy: nil)
        #expect(AppState.phase(for: profile) == .privacy(profile))
    }

    @Test func otherwiseTheAppIsReady() throws {
        let profile = try Samples.profile()
        #expect(AppState.phase(for: profile) == .ready(profile))
    }
}

struct ProfileTests {
    @Test func rolesMakeAPersonALeader() throws {
        let unit = "22222222-2222-2222-2222-222222222222"
        let profile = try Samples.profile(roles: #"[{"stufeId":"\#(unit)","typ":"stufenleitung"}]"#)
        let id = try #require(UUID(uuidString: unit))
        #expect(profile.isLeader)
        #expect(profile.isUnitLeader(of: id))
        #expect(profile.isLeader(of: id))
        #expect(!profile.isLeader(of: UUID()))
    }

    @Test func withoutRolesItIsAParent() throws {
        #expect(try !Samples.profile().isLeader)
    }
}

@MainActor
struct AppLockTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func makeLock(enabled: Bool = true) throws -> (AppLock, FakeBiometricCredential) {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let credential = FakeBiometricCredential()
        let lock = AppLock(defaults: defaults, credential: credential)
        if enabled { lock.setEnabled(true) }
        return (lock, credential)
    }

    @Test func lockIsDueAfterThirtySeconds() {
        #expect(AppLock.lockDue(backgroundSince: start, now: start.addingTimeInterval(30)))
        #expect(!AppLock.lockDue(backgroundSince: start, now: start.addingTimeInterval(29)))
        #expect(!AppLock.lockDue(backgroundSince: nil, now: start))
    }

    @Test func offByDefaultAndColdStartIsLocked() throws {
        let (lock, _) = try makeLock(enabled: false)
        #expect(!lock.isEnabled)
        #expect(!lock.requiresUnlock)
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(true, forKey: "biometricLockEnabled")
        #expect(AppLock(defaults: defaults, credential: FakeBiometricCredential()).requiresUnlock)
    }

    @Test func toggleCreatesAndDeletesTheKey() throws {
        let (lock, credential) = try makeLock()
        #expect(credential.exists)
        #expect(!lock.requiresUnlock)
        lock.setEnabled(false)
        #expect(!credential.exists)
        #expect(!lock.isEnabled)
    }

    @Test func withoutBiometricsNothingLocks() throws {
        let (lock, credential) = try makeLock()
        credential.biometryType = .none
        #expect(!lock.isAvailable)
        lock.scenePhase(.background, hasSession: true, now: start)
        lock.scenePhase(.active, hasSession: true, now: start.addingTimeInterval(60))
        #expect(!lock.requiresUnlock)
    }

    @Test func locksAfterThirtySecondsInBackgroundWithSession() throws {
        let (lock, _) = try makeLock()
        lock.scenePhase(.background, hasSession: true, now: start)
        #expect(!lock.scenePhase(.active, hasSession: true, now: start.addingTimeInterval(29)))
        #expect(!lock.requiresUnlock)
        lock.scenePhase(.background, hasSession: true, now: start)
        #expect(lock.scenePhase(.active, hasSession: true, now: start.addingTimeInterval(30)))
        #expect(lock.requiresUnlock)
    }

    @Test func withoutSessionNothingIsAsked() throws {
        let (lock, _) = try makeLock()
        lock.scenePhase(.background, hasSession: false, now: start)
        #expect(!lock.scenePhase(.active, hasSession: false, now: start.addingTimeInterval(600)))
    }

    @Test func unlockSuccessAndFailure() async throws {
        let (lock, credential) = try makeLock()
        lock.scenePhase(.background, hasSession: true, now: start)
        lock.scenePhase(.active, hasSession: true, now: start.addingTimeInterval(60))
        credential.result = .failed
        await lock.unlock()
        #expect(lock.requiresUnlock)
        #expect(lock.failed)
        credential.result = .success
        await lock.unlock()
        #expect(!lock.requiresUnlock)
        #expect(!lock.failed)
    }

    @Test func invalidatedKeySignsOutAndIsRecreatedAfterPassword() async throws {
        let (lock, credential) = try makeLock()
        lock.scenePhase(.background, hasSession: true, now: start)
        lock.scenePhase(.active, hasSession: true, now: start.addingTimeInterval(60))
        var signedOut = false
        lock.biometryChanged = { signedOut = true }
        credential.result = .invalidated
        await lock.unlock()
        #expect(signedOut)
        #expect(!credential.exists)
        #expect(lock.isEnabled) // The toggle stays on.
        lock.signedInWithPassword()
        #expect(credential.exists)
        #expect(!lock.requiresUnlock)
    }

    @Test func passwordSignInCountsAsUnlocked() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(true, forKey: "biometricLockEnabled")
        let lock = AppLock(defaults: defaults, credential: FakeBiometricCredential())
        #expect(lock.requiresUnlock)
        lock.signedInWithPassword()
        #expect(!lock.requiresUnlock)
    }

    @Test func biometryChangedNotice() {
        #expect(AuthMessages.biometryChanged == "Deine Biometrie hat sich geändert. Bitte melde dich mit dem Passwort an.")
    }
}

struct AuthServiceTests {
    /// Only admins have a second factor; the app sends them to the web admin area.
    @Test func secondFactorPromptMeansAdminOnly() {
        let data = Data(#"{"twoFactorRedirect":true,"twoFactorMethods":["totp"]}"#.utf8)
        #expect(APIClient.signInResult(from: data) == .adminOnly)
        #expect(AuthMessages.adminOnly == "Admins melden sich im Admin-Bereich an. Die App ist für Eltern und Leitende.")
    }

    @Test func regularSignInIsRecognized() {
        let data = Data(#"{"redirect":false,"token":"x","user":{"id":"1","name":"A"}}"#.utf8)
        #expect(APIClient.signInResult(from: data) == .signedIn)
    }

    @Test func nullSessionMeansNoSession() {
        #expect(!APIClient.sessionExists(in: Data("null".utf8)))
        #expect(!APIClient.sessionExists(in: Data(" null\n".utf8)))
        #expect(APIClient.sessionExists(in: Data(#"{"session":{},"user":{}}"#.utf8)))
    }

    @Test func passwordErrorsGetGermanTexts() {
        let tooShort = APIError(kind: .invalidInput, status: 400, code: "PASSWORD_TOO_SHORT", message: "Password too short")
        #expect(AuthMessages.changePassword(tooShort) == "Das neue Passwort muss mindestens 12 Zeichen haben.")
        let same = APIError(kind: .invalidInput, status: 400, code: "PASSWORT_UNVERAENDERT", message: "Das neue Passwort muss sich vom bisherigen unterscheiden.")
        #expect(AuthMessages.changePassword(same) == "Das neue Passwort muss sich vom bisherigen unterscheiden.")
    }

    @Test func serverPagesGetTheBaseURL() {
        let base = URL(string: "https://api.example.org")
        #expect(ServerPage.privacy.url(base: base)?.absoluteString == "https://api.example.org/datenschutz")
        #expect(ServerPage.support.url(base: nil) == nil)
    }
}
