import SwiftUI

/// Dimmed layer with a spinner over the whole app while a user action takes longer than 250 ms. Swallows all touches.
struct BusyOverlay: View {
    var slow = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: Spacing.s3) {
                ProgressView().controlSize(.large).tint(Color.ceviOnSurface)
                if slow {
                    // U5: after a few seconds the overlay says it takes longer.
                    Text("Das dauert länger als sonst …").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Spacing.s6)
            .background(Color.ceviSurface, in: Radius.shape(Radius.lg))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(slow ? "Einen Moment … Das dauert länger als sonst …" : "Einen Moment …"))
        .accessibilityAddTraits(.isModal)
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Einen Moment …")).post() }
    }
}

#Preview("Einen Moment") {
    Text("Inhalt").overlay { BusyOverlay() }
}
#Preview("U5 Lädt länger") {
    Text("Inhalt").overlay { BusyOverlay(slow: true) }
}
