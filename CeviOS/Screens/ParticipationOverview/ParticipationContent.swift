import SwiftUI

/// The loaded overview: bar with the numbers, group switch, sorted list.
struct ParticipationContent: View {
    enum Group: Hashable { case children, leaders }

    let overview: ParticipationOverview
    @State private var group: Group = .children

    private struct Row: Identifiable {
        let id: UUID
        let name: String
        var subtitle: String?
        var imagePath: String?
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
                            AnswerRow(name: row.name, subtitle: row.subtitle, imagePath: row.imagePath, answer: row.answer)
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
            let names = PersonName.titled(name: leader.name, ceviName: leader.ceviName)
            return Row(id: leader.id, name: names.title, subtitle: names.subtitle, imagePath: leader.imageURL, answer: leader.answer)
        }
        }
        return ParticipationOrder.sorted(rows, answer: \.answer, name: \.name)
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
     "leitende":[{"id":"00000000-0000-0000-0000-000000000006","name":"Jan Muster","ceviName":"Fuchs","stufeId":"00000000-0000-0000-0000-0000000000aa","rolle":"leitung","status":"ja"}]}
    """
    // swiftlint:disable:next force_try
    let overview = try! JSONDecoder.api.decode(ParticipationOverview.self, from: Data(json.utf8))
    NavigationStack { ParticipationContent(overview: overview).ceviScreenBackground() }.environment(AppState())
}
