import SwiftUI

/// L14 for one meeting; creates its model.
struct CampMeetingModeView: View {
    @State private var model: CampMeetingModeModel

    init(active: ActiveCamp, meetingId: UUID) { _model = State(initialValue: CampMeetingModeModel(active: active, meetingId: meetingId)) }
    init(model: CampMeetingModeModel) { _model = State(initialValue: model) }

    var body: some View { CampMeetingModeScreen(model: model).task { await model.load() } }
}

/// L14: «Hoeck läuft». Attendees to tick off, the agenda, the round of portfolios.
struct CampMeetingModeScreen: View {
    @Bindable var model: CampMeetingModeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Hoeck wird geladen", notFound: "Diesen Hoeck gibt es nicht mehr.",
                      back: .init(title: "Zu den Hoecks") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, refresh: { await model.load() }) { content }
        }
        .navigationTitle("Hoeck läuft")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder private var content: some View {
        if let meeting = model.mode?.meeting {
            Text(meeting.time.map { "\(meeting.title), \(String(localized: "seit")) \($0)" } ?? meeting.title)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        heading(String(localized: "Anwesende, \(model.presentCount) von \(model.members.count)"))
        FlowLayout(spacing: Spacing.s2) { ForEach(model.members) { chip($0) } }
        if !model.agenda.isEmpty {
            heading(String(localized: "Traktanden"))
            VStack(spacing: 0) {
                ForEach(model.agenda) { item in
                    agendaRow(item)
                    if item.id != model.agenda.last?.id { Divider() }
                }
            }
            .ceviCard(padding: Spacing.s2)
        }
        if !model.round.isEmpty {
            heading(String(localized: "Ressort-Runde"))
            ForEach(Array(model.round.enumerated()), id: \.element.id) { index, portfolio in roundCard(portfolio, first: index == 0) }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader).padding(.top, Spacing.s2)
    }

    /// A tick with name, initials and a check mark (not color alone).
    private func chip(_ member: CampMeetingMember) -> some View {
        let name = CampMeetingModeModel.name(member)
        return Button { Task { await model.togglePresent(member) } } label: {
            HStack(spacing: Spacing.s2) {
                Text(CampCommsText.initials(name)).font(.caption2.bold()).foregroundStyle(Color.ceviOnPrimary)
                    .frame(width: 28, height: 28).background(Color.ceviAccent, in: Circle()).accessibilityHidden(true)
                Text(name).foregroundStyle(Color.ceviOnSurface)
                Image(systemName: member.present ? "checkmark" : "circle").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
            .background(member.present ? Color.ceviSecondaryContainer : Color.ceviSurfaceContainerLow, in: .capsule)
            .overlay(Capsule().stroke(Color.ceviOutlineVariant, lineWidth: member.present ? 0 : Size.border))
        }
        .buttonStyle(.plain)
        .disabled(!model.rights.editsMeetings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(member.present ? "anwesend" : "nicht angekreuzt")"))
        .accessibilityAddTraits(model.rights.editsMeetings ? .isButton : [])
    }

    private func agendaRow(_ item: CampAgendaItem) -> some View {
        Button { Task { await model.toggleDiscussed(item) } } label: {
            HStack(spacing: Spacing.s3) {
                Image(systemName: item.status == .discussed ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
                Text(item.title).foregroundStyle(Color.ceviOnSurface).multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.s2)
                if item.status == .discussed { Text("Besprochen").font(.caption.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
            }
            .padding(.horizontal, Spacing.s2).frame(minHeight: Size.touchTarget).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.rights.editsMeetings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(item.title), \(item.status == .discussed ? "besprochen" : "offen")"))
        .accessibilityAddTraits(model.rights.editsMeetings ? .isButton : [])
    }

    private func roundCard(_ portfolio: CampPortfolioRound, first: Bool) -> some View {
        let overdue = portfolio.tasks?.overdue
        let line = overdue.map { $0 == 1 ? String(localized: "1 überfällig") : String(localized: "\($0) überfällig") }
        let open = portfolio.tasks.map { String(localized: "\($0.open) offen") }
        let leader = CampTaskText.personName(name: portfolio.leader?.name, ceviName: portfolio.leader?.ceviName)
        return VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(portfolio.name).font(.headline).foregroundStyle(Color.ceviOnSurface)
            if let leader { Text(leader).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            HStack(spacing: Spacing.s2) {
                if let line { CampStatusChip(text: line, symbol: (overdue ?? 0) > 0 ? "exclamationmark.triangle" : "checkmark", isWarning: (overdue ?? 0) > 0) }
                if let open { Text(open).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).ceviCard()
        .accessibilityElement(children: .combine)
    }
}

/// Wraps its children to the next line (chips of names).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in arrange(bounds.width, subviews).frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .init(frame.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.init(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), frames)
    }
}

#if DEBUG
#Preview("L14 Normal") { CampCommsPreview.meetingMode() }
#Preview("L14 Nacht") { CampCommsPreview.meetingMode().preferredColorScheme(.dark) }
#Preview("L14 Laden") { CampCommsPreview.meetingMode(phase: .loading) }
#Preview("L14 Fehler") { CampCommsPreview.meetingMode(phase: .failed(state: nil, text: "x")) }
#Preview("L14 Ohne Netz") { CampCommsPreview.meetingMode(offline: true) }
#Preview("L14 Fehler beim Speichern") { CampCommsPreview.meetingMode(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L14 Textgrösse AX3") { CampCommsPreview.meetingMode().dynamicTypeSize(.accessibility3) }
#endif
