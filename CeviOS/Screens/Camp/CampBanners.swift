import SwiftUI

/// U8: the camp is completed or archived; everything can be read, nothing can be changed.
struct CampClosedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Label("Lager abgeschlossen", systemImage: "lock.fill").font(.headline)
            Text("Du kannst alles ansehen, aber nichts mehr ändern.").font(.subheadline)
        }
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .combine)
    }
}

/// Texts of the queue banner (U6).
nonisolated enum CampQueueText {
    static func title(waiting: Int, offline: Bool) -> String {
        let changes = waiting == 1 ? String(localized: "1 Änderung wartet.") : String(localized: "\(waiting) Änderungen warten.")
        return offline ? String(localized: "Ohne Netz. ") + changes : changes
    }
}

/// U6: changes wait in the queue. A live region: VoiceOver announces the count when it changes.
struct CampQueueBanner: View {
    let waiting: Int
    let offline: Bool
    let send: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Label(CampQueueText.title(waiting: waiting, offline: offline), systemImage: offline ? "wifi.slash" : "clock")
                .font(.headline)
            Text("Sie werden gesendet, sobald du wieder Netz hast. Du kannst weiterarbeiten.").font(.subheadline)
            Button("Jetzt senden", action: send).buttonStyle(.ceviText)
        }
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .onChange(of: waiting) {
            AccessibilityNotification.Announcement(CampQueueText.title(waiting: waiting, offline: offline)).post()
        }
    }
}

#Preview("U6 Banner") { CampQueueBanner(waiting: 3, offline: true) {}.padding() }
#Preview("U8 Banner Nacht") { CampClosedBanner().padding().preferredColorScheme(.dark) }
