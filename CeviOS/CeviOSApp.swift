import SwiftUI

@main
struct CeviOSApp: App {
    @State private var zustand = AppZustand()

    var body: some Scene {
        WindowGroup {
            WurzelAnsicht()
                .environment(zustand)
        }
    }
}
