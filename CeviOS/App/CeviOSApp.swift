import SwiftUI

@main
struct CeviOSApp: App {
    @State private var state: AppState
    @State private var lock: AppLock
    @State private var push = PushManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if let scenario = UITestScenario.current {
            _state = State(initialValue: scenario.appState())
            _lock = State(initialValue: scenario.appLock())
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
        RootView().preferredColorScheme(UITestScenario.colorScheme)
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
                .task { push.attach(state) }
                .onChange(of: scenePhase) { _, new in lock.scenePhase(new) }
                .onChange(of: state.phase) { _, new in
                    if new == .signIn { lock.reset() }
                }
        }
    }
}
