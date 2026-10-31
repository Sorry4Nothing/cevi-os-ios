import SwiftUI

@MainActor @Observable
final class ParticipationOverviewModel {
    private(set) var overview: ParticipationOverview?
    private(set) var error: String?

    func load(programId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            overview = try await client.participationOverview(programId: programId)
            error = nil
        } catch is CancellationError {
        } catch let apiError as APIError {
            error = LeadershipMessages.message(for: apiError).text
        } catch {
            self.error = APIError.network.displayText
        }
    }
}

/// Who said yes, no or nothing yet. The server computes the numbers.
struct ParticipationOverviewView: View {
    @Environment(AppState.self) private var appState
    let programId: UUID
    @State private var model = ParticipationOverviewModel()

    var body: some View {
        Group {
            if let overview = model.overview {
                ParticipationContent(overview: overview)
                    .refreshable { await model.load(programId: programId, client: appState.client) }
            } else if let error = model.error {
                ErrorRow(text: error).padding()
            } else {
                LoadingView(label: "Lädt")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ceviScreenBackground()
        .navigationTitle("Anmeldungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(programId: programId, client: appState.client) }
    }
}

/// The loaded overview: bar with the numbers, group switch, sorted list.
private struct ParticipationContent: View {
    enum Group: Hashable { case children, leaders }

    let overview: ParticipationOverview
    @State private var group: Group = .children

    private struct Row: Identifiable {
        let id: UUID
        let name: String
        let answer: OverviewAnswer
    }

    var body: some View {
        // With only one group there is nothing to switch.
        let showsPicker = !overview.children.isEmpty && !overview.leaders.isEmpty
        let shown: Group = showsPicker ? group : (overview.children.isEmpty && !overview.leaders.isEmpty ? .leaders : .children)
        let counts = shown == .children ? overview.totals.children : overview.totals.leaders
        let rows = rows(for: shown)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                CountsBar(counts: counts)
                if showsPicker {
                    Picker("Gruppe", selection: $group) {
                        Text("Kinder · \(overview.children.count)").tag(Group.children)
                        Text("Leitende · \(overview.leaders.count)").tag(Group.leaders)
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: Size.touchTarget)
                }
                if rows.isEmpty {
                    Text("Noch niemand eingeteilt.")
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            AnswerRow(name: row.name, answer: row.answer)
                            if row.id != rows.last?.id { Divider() }
                        }
                    }
                    .ceviCard(padding: 0)
                }
                Text("Sortiert: offen zuerst, dann Ja, dann Nein.")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                    .padding(.horizontal, Spacing.s1)
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
    }

    private func rows(for group: Group) -> [Row] {
        let rows = switch group {
        case .children: overview.children.map { Row(id: $0.id, name: "\($0.firstName) \($0.lastName)", answer: $0.answer) }
        case .leaders: overview.leaders.map { leader in
            Row(id: leader.id, name: leader.ceviName.map { "\(leader.name) (\($0))" } ?? leader.name, answer: leader.answer)
        }
        }
        return ParticipationOrder.sorted(rows, answer: \.answer, name: \.name)
    }
}

/// Proportional bar (yes, no, open) with the numbers as text below.
private struct CountsBar: View {
    let counts: ParticipationCounts

    var body: some View {
        let total = counts.yes + counts.no + counts.open
        let summary = String(localized: "\(counts.yes) Ja, \(counts.no) Nein, \(counts.open) offen von \(total)")
        VStack(alignment: .leading, spacing: Spacing.s2) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    segment(counts.yes, of: total, width: proxy.size.width, color: .ceviOnSuccessContainer)
                    segment(counts.no, of: total, width: proxy.size.width, color: .ceviOnErrorContainer)
                    segment(counts.open, of: total, width: proxy.size.width, color: .ceviOutlineVariant)
                }
                .background(Color.ceviOutlineVariant)
                .clipShape(Capsule())
            }
            .frame(height: Spacing.s3)
            Text(summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private func segment(_ value: Int, of total: Int, width: CGFloat, color: Color) -> some View {
        color.frame(width: total > 0 ? width * CGFloat(value) / CGFloat(total) : 0)
    }
}

/// Name with the answer as chip; stacks at accessibility sizes.
private struct AnswerRow: View {
    let name: String
    let answer: OverviewAnswer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s2))
            : AnyLayout(HStackLayout(spacing: Spacing.s3))
        layout {
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
            AnswerChip(answer: answer)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .frame(minHeight: Size.touchTarget)
        .accessibilityElement(children: .combine)
    }
}

/// Answer as chip: symbol and word, never color alone.
struct AnswerChip: View {
    let answer: OverviewAnswer

    var body: some View {
        let (title, symbol, foreground, background): (LocalizedStringKey, String, Color, Color) = switch answer {
        case .yes: ("Ja", "checkmark", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .no: ("Nein", "xmark", .ceviOnErrorContainer, .ceviErrorContainer)
        case .open: ("Offen", "circle.dashed", .ceviOnSurfaceVariant, .clear)
        }
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
            .overlay {
                if answer == .open { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) }
            }
    }
}

#Preview {
    let json = """
    {"zahlen":{"kinder":{"ja":2,"nein":1,"offen":2},"leitende":{"ja":1,"nein":0,"offen":0}},
     "kinder":[
      {"id":"00000000-0000-0000-0000-000000000001","vorname":"Jonas","nachname":"Schmid","stufeId":"00000000-0000-0000-0000-0000000000aa","status":"nein"},
      {"id":"00000000-0000-0000-0000-000000000002","vorname":"Lena","nachname":"Meier","stufeId":"00000000-0000-0000-0000-0000000000aa","status":"ja"},
      {"id":"00000000-0000-0000-0000-000000000003","vorname":"Elin","nachname":"Frei","stufeId":"00000000-0000-0000-0000-0000000000aa","status":"offen"},
      {"id":"00000000-0000-0000-0000-000000000004","vorname":"Noah","nachname":"Keller","stufeId":"00000000-0000-0000-0000-0000000000aa","status":"ja"},
      {"id":"00000000-0000-0000-0000-000000000005","vorname":"Tim","nachname":"Baumann","stufeId":"00000000-0000-0000-0000-0000000000aa","status":"offen"}],
     "leitende":[{"id":"00000000-0000-0000-0000-000000000006","name":"Robin Muster","ceviName":"Fuchs","stufeId":"00000000-0000-0000-0000-0000000000aa","rolle":"leitung","status":"ja"}]}
    """
    // swiftlint:disable:next force_try
    let overview = try! JSONDecoder.api.decode(ParticipationOverview.self, from: Data(json.utf8))
    NavigationStack { ParticipationContent(overview: overview).ceviScreenBackground() }
}
