import SwiftUI

@main
struct CeviOSApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var state = AppState()
    @State private var lock = AppLock()
    @State private var push = PushManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
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
