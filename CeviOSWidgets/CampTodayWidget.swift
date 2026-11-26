import SwiftUI
import WidgetKit

/// W3 «Lager heute» with the choice of the camp (WC2).
struct CampTodayView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redaction

    private let spec = WidgetSpec(title: String(localized: "Lager heute"), symbol: "tent", emptyText: String(localized: "Heute nichts eingeteilt"), emptySymbol: "tent")
    private var size: WidgetSize { WidgetSize(family) }
    private var model: WidgetModel { entry.model(.campToday, privacy: redaction.contains(.privacy)) }

    var body: some View {
        WidgetRoot(size: size, link: WidgetLink.url(typ: model.camp == nil ? nil : "lager_heute", id: model.camp?.id)) {
            if let camp = model.camp, model.phase == .content || model.phase == .redacted {
                filled(camp, redacted: model.phase == .redacted)
            } else {
                WidgetStateBody(phase: model.phase, spec: spec, size: size)
            }
        }
    }

    private func dayText(_ camp: WidgetCamp) -> String? {
        WidgetFormat.campDay(entry.date, from: camp.from, to: camp.to).map { String(localized: "Tag \($0.day) von \($0.of)") }
    }

    @ViewBuilder
    private func filled(_ camp: WidgetCamp, redacted: Bool) -> some View {
        let plan = WidgetLayoutPlan.campToday(size, largeType: typeSize.isAccessibilitySize)
        let day = WidgetFormat.campDay(entry.date, from: camp.from, to: camp.to)
        switch size {
        case .inline:
            Text(dayText(camp) ?? spec.title)
        case .circular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(day.map { "\($0.day)/\($0.of)" } ?? "–").font(.headline)
                    Text("Tag").font(.caption2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayText(camp) ?? spec.title)
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(redacted ? "\(spec.title), \(dayText(camp) ?? "")" : (dayText(camp) ?? spec.title)).font(.headline).widgetAccentable()
                if redacted {
                    Text("Zum Anzeigen die App öffnen").font(.caption)
                } else if let duty = camp.duty {
                    Text("Dein Dienst: \(duty.name)").font(.caption)
                    if let time = duty.time { Text(time).font(.caption) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .small:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                HStack(alignment: .firstTextBaseline) {
                    Text(day.map { "\($0.day)/\($0.of)" } ?? "–").font(.title.bold()).foregroundStyle(Color.ceviPrimary)
                    Text(dayText(camp) ?? "").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                if redacted {
                    Text("Zum Anzeigen die App öffnen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                } else if let duty = camp.duty {
                    Text(typeSize.isAccessibilitySize ? "Dein Dienst" : "Dein Dienst").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
                    Text(duty.time.map { "\(duty.name), \(String($0.prefix(5)))" } ?? duty.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
                }
                Spacer(minLength: 0)
                if let stand = model.stand, stand.isStale || stand.isOffline { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .medium, .large:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                Text(dayText(camp) ?? "").font(.headline.bold()).foregroundStyle(Color.ceviOnSurface)
                Text(WidgetFormat.longDay(entry.date)).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                if redacted {
                    Text("Zum Anzeigen die App öffnen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                } else {
                    if let duty = camp.duty {
                        Label(duty.time.map { "Dein Dienst: \(duty.name), \($0)" } ?? "Dein Dienst: \(duty.name)", systemImage: "person.crop.circle.badge.clock")
                            .font(.footnote).foregroundStyle(Color.ceviOnSurface)
                    }
                    if plan.rows > 0, !camp.important.isEmpty {
                        Text("Wichtig heute").font(.caption.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
                        ForEach(camp.important.prefix(plan.rows), id: \.self) { Text("– \($0)").font(.footnote).foregroundStyle(Color.ceviOnSurface).lineLimit(2) }
                    }
                    if plan.showsLater, camp.todosTotal > 0 {
                        Text("Meine To-dos").font(.caption.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
                        Text("\(camp.todosOpen) von \(camp.todosTotal) offen").font(.footnote).foregroundStyle(Color.ceviOnSurface)
                    }
                }
                Spacer(minLength: 0)
                if let stand = model.stand { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct CampTodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CampToday", intent: SelectCampIntent.self, provider: SnapshotProvider(kind: .campToday)) { entry in
            CampTodayView(entry: entry)
        }
        .configurationDisplayName("Lager heute")
        .description("Zeigt den Lagertag, deinen Dienst und was heute wichtig ist.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
