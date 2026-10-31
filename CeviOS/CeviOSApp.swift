import SwiftUI

@main
struct CeviOSApp: App {
    @State private var state = AppState()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(lock)
                .onChange(of: scenePhase) { _, new in lock.scenePhase(new) }
                .onChange(of: state.phase) { _, new in
                    if new == .signIn { lock.reset() }
                }
        }
    }
}
