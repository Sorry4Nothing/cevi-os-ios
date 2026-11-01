import SwiftUI

/// Root of the app. If the app is outdated, the notice blocks everything else. Otherwise the screen follows the phase of the `AppState`.
struct RootView: View {
    @Environment(\.appConfiguration) private var configuration
    @Environment(AppState.self) private var state
    @Environment(AppLock.self) private var lock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if state.appOutdated {
                AppOutdatedView(appStoreURL: configuration.appStoreURL)
            } else {
                content
                    .task { await state.start() }
            }
        }
        .tint(.ceviAccent)
        // Soft cross-fade between start, sign-in and the app. Not with "Reduce Motion".
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.phase)
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
            protected(profile)
        }
    }

    @ViewBuilder
    private func protected(_ profile: Profile) -> some View {
        if !lock.isRequired(for: profile) || !lock.isLocked {
            MainView(profile: profile)
        } else if AppLock.deviceCodeSet {
            LockView()
        } else if profile.isLeader {
            DeviceCodeMissingView()
        } else {
            // Without a device code there is nothing to lock for parents.
            MainView(profile: profile)
        }
    }
}
