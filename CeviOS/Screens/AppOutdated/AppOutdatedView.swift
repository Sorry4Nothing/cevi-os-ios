import SwiftUI

/// Full-screen notice for 426 `APP_VERALTET`.
struct AppOutdatedView: View {
    let appStoreURL: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        StateView(
            symbol: "arrow.down.app",
            title: "Bitte die App aktualisieren",
            message: "Diese Version von Cevi OS wird nicht mehr unterstützt.",
            primary: appStoreURL.map { url in StateView.Action(title: "Im App Store öffnen") { openURL(url) } }
        )
    }
}

#Preview("App veraltet") {
    AppOutdatedView(appStoreURL: URL(string: "https://apps.apple.com/app/example"))
}
