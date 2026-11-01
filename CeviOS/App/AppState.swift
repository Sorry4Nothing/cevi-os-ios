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
        case changePassword(Profile)
        case privacy(Profile)
        case ready(Profile)
    }

    /// `nil` while the base URL of the environment is missing or invalid.
    let client: APIClient?
    /// User-triggered actions in flight; drives the app-wide busy overlay.
    let busy = BusyState.shared
    private(set) var phase: Phase = .loading
    /// The server demands a newer app version; everything else is blocked.
    var appOutdated = false
    /// Chat that is open right now. Pushes for it are not shown.
    var openChatId: UUID?
    /// Target of a tapped push; the main view opens it and clears it.
    var pendingTarget: PushTarget?
    /// Notice for the sign-in screen after the app signed the person out on its own (admins).
    var signInNotice: String?
    /// Push tokens and caches that must be dropped on sign-out hook in here.
    var onSignOut: [@MainActor () async -> Void] = []
    /// In-memory caches that must leave memory when the app lock engages (the session cookie stays).
    var onLock: [@MainActor () -> Void] = []
    /// `GET /stufen`, loaded once per session for the unit logos. Dropped on sign-out and lock.
    private(set) var units: [UnitInfo]?
    private var isLoadingUnits = false

    /// `session` is replaced only by the DEBUG UI-test backend (`UITestLaunch`).
    init(
        configuration: AppConfiguration = .current,
        cookieStore: some CookieStore = KeychainCookieStore(),
        session: URLSession = APIClient.makeSession()
    ) {
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
        client = APIClient(baseURL: baseURL, appVersion: version, cookieStore: cookieStore, session: session) { relay.report($0) }
        relay.target = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        phase = hasCookies ? .loading : .signIn
        onSignOut.append { [weak self] in
            ProfileImageCache.shared.removeAll()
            self?.units = nil
        }
        onLock.append { [weak self] in
            ProfileImageCache.shared.removeAll()
            self?.units = nil
        }
    }

    /// Logo path of a unit, `nil` without own logo or before the units are loaded.
    func logoPath(unitId: UUID) -> String? {
        units?.first { $0.id == unitId }?.logoURL
    }

    /// Loads the units once per session. A failure leaves them `nil`, so the next caller tries again.
    func loadUnitsIfNeeded() async {
        guard units == nil, !isLoadingUnits, let client else { return }
        isLoadingUnits = true
        defer { isLoadingUnits = false }
        units = try? await client.units()
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

    /// A session cookie is (presumably) there; only then the app lock asks for biometrics.
    var hasSession: Bool {
        switch phase {
        case .signIn, .configurationMissing: false
        default: true
        }
    }

    /// App lock engaged: drop the profile and caches, keep the cookie. After unlocking, `start()` reloads.
    func lock() {
        guard hasSession else { return }
        phase = .loading
        for task in onLock { task() }
    }

    /// The biometric set changed: end the session and tell why on the sign-in screen.
    func signOutAfterBiometryChange() async {
        await signOut()
        signInNotice = AuthMessages.biometryChanged
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
            await proceed(with: try await client.loadProfile())
        } catch let error as APIError where error.kind == .unauthorized {
            phase = .signIn
        } catch {
            if !appOutdated { phase = .offline }
        }
    }

    func signIn(username: String, password: String) async throws {
        guard let client else { return }
        signInNotice = nil
        switch try await client.signIn(username: username, password: password) {
        case .adminOnly:
            // Only the intermediate second-factor cookie exists; dropping it locally is the whole sign-out.
            await client.clearCookies()
            signInNotice = AuthMessages.adminOnly
            phase = .signIn
        case .signedIn: try await loadProfileAfterSignIn()
        }
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

    func signOut() async {
        await client?.signOut()
        for task in onSignOut { await task() }
        phase = .signIn
    }

    /// Loads the profile again after it changed (settings, phone, image). Errors keep the current state.
    func reloadProfile() async {
        guard let client, case .ready = phase, let profile = try? await client.loadProfile() else { return }
        await proceed(with: profile)
    }

    private func loadProfileAfterSignIn() async throws {
        guard let client else { return }
        await proceed(with: try await client.loadProfile())
    }

    private func sessionDidEnd() {
        phase = .signIn
        Task { for task in onSignOut { await task() } }
    }

    private func proceed(with profile: Profile) async {
        guard !profile.isAdminOnly else {
            // Admins without children or unit roles have nothing to do in the app.
            await signOut()
            signInNotice = AuthMessages.adminOnly
            return
        }
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
