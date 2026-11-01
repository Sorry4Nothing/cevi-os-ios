import SwiftUI

@main
struct CeviOSApp: App {
    @State private var state: AppState
    @State private var lock: AppLock
    @State private var push = PushManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if UITestLaunch.isActive {
            _state = State(initialValue: UITestLaunch.appState())
            _lock = State(initialValue: AppLock(uiTestLocked: UITestLaunch.startsLocked))
            return
        }
        #endif
        _state = State(initialValue: AppState())
        _lock = State(initialValue: AppLock())
        // Starts Firebase (only with GoogleService-Info.plist).
        PushManager.shared.configure()
    }

    private var root: some View {
        #if DEBUG
        RootView().preferredColorScheme(UITestLaunch.colorScheme)
        #else
        RootView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(state)
                .environment(lock)
                .environment(push)
                .task {
                    push.attach(state)
                    lock.biometryChanged = { [state] in await state.signOutAfterBiometryChange() }
                }
                .onChange(of: scenePhase) { _, new in
                    if lock.scenePhase(new, hasSession: state.hasSession) { state.lock() }
                }
                .onChange(of: state.phase, initial: true) { _, new in
                    // The password unlocks. `.ready` is only reached unlocked; there a lost key is created anew.
                    switch new {
                    case .signIn, .ready: lock.signedInWithPassword()
                    default: break
                    }
                }
        }
    }
}
