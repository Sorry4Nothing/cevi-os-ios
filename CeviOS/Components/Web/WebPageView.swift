import SwiftUI
import WebKit

/// Shows a server page (privacy, support, delete account) in the app, with a "Fertig" button. SwiftUI and WebKit only.
struct WebPageView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}
