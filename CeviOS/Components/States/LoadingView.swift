import SwiftUI

/// ZT2: list content is loading. Shows placeholder cards; VoiceOver hears one label.
struct LoadingView: View {
    let label: LocalizedStringKey

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.s2) {
                ForEach(0..<3, id: \.self) { _ in placeholderCard }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
        .skeletonPulse()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .ceviScreenBackground()
    }

    private var placeholderCard: some View {
        // Never visible as text: `redacted` turns it into bars of the right size for the current text size.
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(verbatim: "Samstag, 14.00")
            Text(verbatim: "Programm im Wald").font(.title(.cardTitle))
            Text(verbatim: "Treffpunkt")
        }
        .foregroundStyle(Color.ceviSurfaceContainerHigh)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }
}

#Preview("Laden") { LoadingView(label: "Programme werden geladen") }
