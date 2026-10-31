import SwiftUI

@main
struct CeviOSApp: App {
    @State private var zustand = AppZustand()
    @State private var sperre = AppSperre()
    @Environment(\.scenePhase) private var szenenphase

    var body: some Scene {
        WindowGroup {
            WurzelAnsicht()
                .environment(zustand)
                .environment(sperre)
                .onChange(of: szenenphase) { _, neu in sperre.szenenphase(neu) }
                .onChange(of: zustand.phase) { _, neu in
                    if neu == .anmelden { sperre.zuruecksetzen() }
                }
        }
    }
}
