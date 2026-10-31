import SwiftUI

/// Root of the app. If the app is outdated, the notice blocks everything else. Otherwise the screen follows the phase of the `AppState`.
struct RootView: View {
    @Environment(\.appConfiguration) private var configuration
    @Environment(AppState.self) private var state
    @Environment(AppLock.self) private var lock

    var body: some View {
        if state.appOutdated {
            AppOutdatedView(appStoreURL: configuration.appStoreURL)
        } else {
            content
                .task { await state.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .loading:
            ProgressView().accessibilityLabel(Text("Lädt"))
        case .configurationMissing:
            Text("Die Verbindung zum Server ist nicht eingerichtet.")
                .multilineTextAlignment(.center)
                .padding()
        case .offline:
            OfflineView()
        case .signIn:
            SignInView()
        case .secondFactor:
            SecondFactorView()
        case .changePassword:
            ChangePasswordView()
        case .privacy:
            PrivacyView()
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

/// Full-screen notice for 426 `APP_VERALTET`.
struct AppOutdatedView: View {
    let appStoreURL: URL?

    var body: some View {
        VStack(spacing: 24) {
            Text("Bitte die App aktualisieren")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Diese Version von Cevi OS wird nicht mehr unterstützt.")
                .font(.body)
                .multilineTextAlignment(.center)
            if let appStoreURL {
                Link("Im App Store öffnen", destination: appStoreURL)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
        }
        .padding()
    }
}

#Preview("App veraltet") {
    AppOutdatedView(appStoreURL: URL(string: "https://apps.apple.com/app/example"))
}
