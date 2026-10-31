import SwiftUI

/// Small uppercase line above a display title. Only on Login, Willkommen and Start.
struct Eyebrow: View {
    let text: String

    init(_ text: String.LocalizationValue) { self.text = String(localized: text) }

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ceviAccent)
            // VoiceOver (and UI tests) get the normal spelling, not single capitals.
            .accessibilityLabel(text)
    }
}
