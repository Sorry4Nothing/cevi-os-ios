import SwiftUI

/// Locked: unlock with Face ID, Touch ID or device code.
struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        StateView(
            symbol: lock.failed ? "lock.trianglebadge.exclamationmark" : "lock.fill",
            title: "Cevi OS ist gesperrt",
            message: lock.failed ? "Das Entsperren hat nicht geklappt." : nil,
            tone: lock.failed ? .error : .neutral,
            primary: StateView.Action(title: "Entsperren", symbol: "faceid") { Task { await lock.unlock() } }
        )
        .task { await lock.unlock() }
    }
}

#Preview("Gesperrt") {
    LockView().environment(AppLock())
}
