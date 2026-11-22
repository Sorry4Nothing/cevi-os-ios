import SwiftUI

/// The banners every camp screen shares: waiting changes (U6), closed camp (U8), and the stand when there is no network.
struct CampBannerStack: View {
    @Environment(ActiveCamp.self) private var active
    var staleSince: Date?

    var body: some View {
        if active.waitingCount > 0 {
            CampQueueBanner(waiting: active.waitingCount, offline: active.isOffline) { Task { await active.sendWaiting() } }
        }
        if active.isReadOnly { CampClosedBanner() }
        if let staleSince { CampOfflineNote(since: staleSince) }
    }
}

/// «Ohne Netz. Du siehst den Stand von heute 18:02.» A live region.
struct CampOfflineNote: View {
    let since: Date

    var body: some View {
        let time = since.formatted(Date.FormatStyle(locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone).hour().minute())
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Label("Ohne Netz", systemImage: "wifi.slash").font(.headline)
            Text("Du siehst den Stand von heute \(time). Änderungen warten, bis du wieder Netz hast.").font(.subheadline)
        }
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// «Aufgabe erledigt.» with «Rückgängig». A live region; the model also announces it.
struct CampNoticeBar: View {
    let title: String
    var message: String?
    var undo: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Label(title, systemImage: "checkmark.circle").font(.headline)
                if let message { Text(message).font(.subheadline) }
            }
            Spacer(minLength: Spacing.s2)
            if let undo { Button("Rückgängig", action: undo).buttonStyle(.ceviText) }
            Button("Schliessen", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).buttonStyle(.plain)
                .frame(width: Size.touchTarget, height: Size.touchTarget)
        }
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .padding(.leading, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// «Verschieben nach …» and «Status ändern»: the visible alternative to dragging.
struct CampStatusSheet: View {
    let title: String
    let subtitle: String
    let counts: [CampTaskStatus: Int]
    let current: CampTaskStatus?
    let apply: (CampTaskStatus) -> Void
    @State private var chosen: CampTaskStatus?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(subtitle).font(.body).foregroundStyle(Color.ceviOnSurfaceVariant)
                VStack(spacing: 0) {
                    ForEach(CampTaskText.boardStatuses, id: \.self) { status in
                        Button { chosen = status } label: {
                            HStack {
                                Image(systemName: (chosen ?? current) == status ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
                                Text(CampTaskText.statusName(status)).foregroundStyle(Color.ceviOnSurface)
                                Spacer(minLength: Spacing.s2)
                                if let count = counts[status] {
                                    Text(count == 0 ? String(localized: "keine") : count == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(count) Aufgaben"))
                                        .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                                }
                            }
                            .frame(minHeight: Size.touchTarget)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits((chosen ?? current) == status ? .isSelected : [])
                        if status != CampTaskText.boardStatuses.last { Divider() }
                    }
                }
                .ceviCard(padding: Spacing.s4)
                Spacer(minLength: 0)
                Button("Übernehmen") { if let chosen { apply(chosen) }; dismiss() }
                    .buttonStyle(.ceviPrimary).disabled(chosen == nil || chosen == current)
            }
            .padding(Spacing.s4)
            .ceviScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// The «Neue Aufgabe» button of the lists (the one main action).
struct CampNewTaskButton: View {
    var title: LocalizedStringKey = "Neue Aufgabe"
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: "plus") }
            .buttonStyle(CeviPrimaryButtonStyle(expands: false))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}
