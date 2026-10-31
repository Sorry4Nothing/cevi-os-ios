import SwiftUI

/// Error row with symbol and text, not color alone.
struct ErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.ceviOnErrorContainer)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Fehler: \(text)"))
    }
}
