import SwiftUI

/// Dimmed layer with a spinner over the whole app while a user action takes longer than 250 ms. Swallows all touches.
struct BusyOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .tint(Color.ceviOnSurface)
                .padding(Spacing.s6)
                .background(Color.ceviSurface, in: Radius.shape(Radius.lg))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Einen Moment …"))
        .accessibilityAddTraits(.isModal)
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Einen Moment …")).post() }
    }
}

#Preview("Einen Moment") {
    Text("Inhalt").overlay { BusyOverlay() }
}
