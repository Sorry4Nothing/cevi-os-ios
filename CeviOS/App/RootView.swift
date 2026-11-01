import SwiftUI

/// Root of the app. If the app is outdated, the notice blocks everything else. Otherwise the screen follows the phase of the `AppState`.
struct RootView: View {
    @Environment(\.appConfiguration) private var configuration
    @Environment(AppState.self) private var state
    @Environment(AppLock.self) private var lock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if state.appOutdated {
                AppOutdatedView(appStoreURL: configuration.appStoreURL)
            } else if state.hasSession, lock.requiresUnlock {
                // Cold start and after 30 s in the background: nothing loads before the unlock.
                LockView()
            } else {
                content
                    .task { await state.start() }
            }
        }
        // Disabling resigns the focused text field; the overlay swallows touches. Never over the start screen.
        .disabled(showsBusyOverlay)
        .overlay {
            if showsBusyOverlay { BusyOverlay() }
        }
        // With the lock on, the app switcher shows only a cover.
        .overlay {
            if lock.isEnabled, scenePhase != .active {
                ZStack {
                    Color.ceviSurface.ignoresSafeArea()
                    Text("Cevi OS").font(.title(.display)).foregroundStyle(Color.ceviOnSurface)
                }
                .accessibilityHidden(true)
            }
        }
        .tint(.ceviAccent)
        // Soft cross-fade between start, sign-in steps and the app. Not with "Reduce Motion" and not on sign-out.
        .animation(reduceMotion || state.phase == .signIn ? nil : .easeInOut(duration: 0.26), value: state.phase)
    }

    private var showsBusyOverlay: Bool {
        state.busy.isOverlayVisible && state.phase != .loading
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .loading:
            StartView()
        case .configurationMissing:
            StateView(symbol: "gearshape", title: "Die Verbindung zum Server ist nicht eingerichtet.", tone: .error)
        case .offline:
            OfflineView()
        case .signIn:
            SignInView()
        case .changePassword:
            ChangePasswordView()
        case .privacy(let profile):
            PrivacyView(name: profile.ceviName ?? profile.name, childNames: profile.children.map(\.firstName))
        case .ready(let profile):
            MainView(profile: profile)
        }
    }
}
