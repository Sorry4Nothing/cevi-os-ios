import SwiftUI

/// Locked: unlock with Face ID or Touch ID, or end the session and sign in with the password.
struct LockView: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppState.self) private var state

    var body: some View {
        StateView(
            symbol: lock.failed ? "lock.trianglebadge.exclamationmark" : "lock.fill",
            title: "Cevi OS ist gesperrt",
            message: lock.failed ? "Das Entsperren hat nicht geklappt." : nil,
            tone: lock.failed ? .error : .neutral,
            primary: StateView.Action(title: "Entsperren", symbol: lock.symbol) { Task { await lock.unlock() } },
            secondary: StateView.Action(title: "Mit Passwort anmelden") { Task { await state.busy.track { await state.signOut() } } }
        )
        .task { await lock.unlock() }
    }
}

#Preview("Gesperrt") {
    LockView().environment(AppLock()).environment(AppState())
}
