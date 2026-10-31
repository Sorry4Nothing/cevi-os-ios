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

struct AppLockTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func lockIsDueAfterFiveMinutes() {
        #expect(AppLock.lockDue(backgroundSince: start, now: start.addingTimeInterval(300)))
        #expect(AppLock.lockDue(backgroundSince: start, now: start.addingTimeInterval(3600)))
    }

    @Test func notBefore() {
        #expect(!AppLock.lockDue(backgroundSince: start, now: start.addingTimeInterval(299)))
        #expect(!AppLock.lockDue(backgroundSince: nil, now: start))
    }

    @MainActor @Test func coldStartIsLockedAndSceneChangeLocksAfterTimeout() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let lock = AppLock(defaults: defaults)
        #expect(lock.isLocked)
        lock.scenePhase(.background, now: start)
        lock.scenePhase(.active, now: start.addingTimeInterval(10))
        #expect(lock.isLocked) // Cold start: only unlock() lifts the lock.
    }

    @MainActor @Test func parentsCanDisableTheLockLeadersCannot() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let lock = AppLock(defaults: defaults)
        let parent = try Samples.profile()
        let leader = try Samples.profile(roles: #"[{"stufeId":"22222222-2222-2222-2222-222222222222","typ":"leitung"}]"#)
        #expect(lock.parentsLockEnabled)
        #expect(lock.isRequired(for: parent))
        lock.parentsLockEnabled = false
        #expect(!lock.isRequired(for: parent))
        #expect(lock.isRequired(for: leader))
    }
}

struct AuthServiceTests {
    @Test func secondFactorPromptIsRecognized() {
        let data = Data(#"{"twoFactorRedirect":true,"twoFactorMethods":["totp"]}"#.utf8)
        #expect(APIClient.signInResult(from: data) == .secondFactor)
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

    @Test func secondFactorErrorsDistinguishWrongCodeFromExpiredStep() {
        let wrong = APIError(kind: .unauthorized, status: 401, code: "INVALID_CODE", message: "Invalid code")
        #expect(AuthMessages.secondFactor(wrong).restartSignIn == false)
        let tooMany = APIError(kind: .invalidInput, status: 400, code: "TOO_MANY_ATTEMPTS_REQUEST_NEW_CODE", message: "x")
        #expect(AuthMessages.secondFactor(tooMany).restartSignIn)
    }

    @Test func serverPagesGetTheBaseURL() {
        let base = URL(string: "https://api.example.org")
        #expect(ServerPage.privacy.url(base: base)?.absoluteString == "https://api.example.org/datenschutz")
        #expect(ServerPage.support.url(base: nil) == nil)
    }
}
