import Foundation
import Observation

/// State of the whole app: server connection, sign-in status and profile.
@MainActor @Observable
final class AppState {
    /// Where the app stands. The screen follows from it.
    enum Phase: Equatable {
        case loading
        case configurationMissing
        case offline
        case signIn
        case secondFactor
        case changePassword(Profile)
        case privacy(Profile)
        case ready(Profile)
    }

    /// `nil` while the base URL of the environment is missing or invalid.
    let client: APIClient?
    private(set) var phase: Phase = .loading
    /// The server demands a newer app version; everything else is blocked.
    var appOutdated = false
    /// Push tokens and caches that must be dropped on sign-out hook in here.
    var onSignOut: [@MainActor () async -> Void] = []

    init(configuration: AppConfiguration = .current, cookieStore: some CookieStore = KeychainCookieStore()) {
        FirstLaunchCleanup.run(cookieStore: cookieStore)
        let hasCookies = !cookieStore.read().isEmpty

        guard let baseURL = configuration.apiBaseURL else {
            client = nil
            phase = .configurationMissing
            return
        }
        let version = APIClient.appVersion(from: Bundle.main.infoDictionary ?? [:])
        // The client calls back before `self` is ready; hence a relay whose target is filled in afterwards.
        let relay = EventRelay()
        client = APIClient(baseURL: baseURL, appVersion: version, cookieStore: cookieStore) { relay.report($0) }
        relay.target = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        phase = hasCookies ? .loading : .signIn
    }

    func handle(_ event: APIEvent) {
        switch event {
        case .sessionEnded: sessionDidEnd()
        case .appOutdated: appOutdated = true
        }
    }

    var profile: Profile? {
        switch phase {
        case .changePassword(let p), .privacy(let p), .ready(let p): p
        default: nil
        }
    }

    /// Cold start with a cookie: extend the session, then load the profile.
    func start() async {
        guard let client, phase == .loading || phase == .offline else { return }
        phase = .loading
        do {
            guard try await client.checkSession() else {
                phase = .signIn
                return
            }
            proceed(with: try await client.loadProfile())
        } catch let error as APIError where error.kind == .unauthorized {
            phase = .signIn
        } catch {
            if !appOutdated { phase = .offline }
        }
    }

    func signIn(username: String, password: String) async throws {
        guard let client else { return }
        switch try await client.signIn(username: username, password: password) {
        case .secondFactor: phase = .secondFactor
        case .signedIn: try await loadProfileAfterSignIn()
        }
    }

    func confirmSecondFactor(code: String, isBackupCode: Bool) async throws {
        guard let client else { return }
        try await client.confirmSecondFactor(code: code, isBackupCode: isBackupCode)
        try await loadProfileAfterSignIn()
    }

    /// Back to sign-in when the intermediate second-factor step is no longer valid.
    func restartSignIn() async {
        await client?.clearCookies()
        phase = .signIn
    }

    func passwordChanged(current: String, new: String) async throws {
        guard let client else { return }
        try await client.changePassword(current: current, new: new)
        try await loadProfileAfterSignIn()
    }

    func privacyAcknowledged() async throws {
        guard let client else { return }
        try await client.acknowledgePrivacy()
        try await loadProfileAfterSignIn()
    }

    func signOut(everywhere: Bool = false) async {
        await client?.signOut(everywhere: everywhere)
        for task in onSignOut { await task() }
        phase = .signIn
    }

    private func loadProfileAfterSignIn() async throws {
        guard let client else { return }
        proceed(with: try await client.loadProfile())
    }

    private func sessionDidEnd() {
        phase = .signIn
        Task { for task in onSignOut { await task() } }
    }

    private func proceed(with profile: Profile) {
        phase = Self.phase(for: profile)
    }

    /// Order as the backend defines it: password change first, then privacy, then the app.
    nonisolated static func phase(for profile: Profile) -> Phase {
        if profile.mustChangePassword { return .changePassword(profile) }
        if profile.privacyReadAt == nil { return .privacy(profile) }
        return .ready(profile)
    }
}

/// Forwards events of the client as soon as the `AppState` is ready.
private nonisolated final class EventRelay: @unchecked Sendable {
    // shortcut: unguarded access, target is set only once right after init; guard it if there are more writers.
    var target: (@Sendable (APIEvent) -> Void)?
    func report(_ event: APIEvent) { target?(event) }
}
