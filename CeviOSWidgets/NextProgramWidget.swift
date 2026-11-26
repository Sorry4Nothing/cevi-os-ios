import SwiftUI
import WidgetKit

/// W1 «Nächstes Programm» with the choice of the unit (WC1).
struct NextProgramView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redaction

    private let spec = WidgetSpec(title: String(localized: "Nächstes Programm"), symbol: "calendar", emptyText: String(localized: "Keine Programme in Sicht"), emptySymbol: "calendar")
    private var size: WidgetSize { WidgetSize(family) }
    private var model: WidgetModel { entry.model(.nextProgram, privacy: redaction.contains(.privacy)) }

    var body: some View {
        WidgetRoot(size: size, link: link) {
            if let unit = model.unit, let next = unit.programs.first, model.phase == .content || model.phase == .redacted {
                if model.phase == .redacted { redacted(next) } else { content(unit, next) }
            } else {
                WidgetStateBody(phase: model.phase, spec: spec, size: size)
            }
        }
    }

    private var link: URL {
        if let id = model.unit?.programs.first?.id, model.phase == .content || model.phase == .redacted {
            return WidgetLink.url(typ: "programm", id: id)
        }
        return WidgetLink.url()
    }

    private var openText: String? {
        guard let open = model.unit?.openAnswers, open > 0 else { return nil }
        return open == 1 ? String(localized: "Zusage für 1 Kind offen") : String(localized: "Zusage für \(open) Kinder offen")
    }

    @ViewBuilder
    private func content(_ unit: WidgetUnit, _ next: WidgetProgram) -> some View {
        let plan = WidgetLayoutPlan.nextProgram(size, largeType: typeSize.isAccessibilitySize)
        switch size {
        case .inline:
            Text(WidgetFormat.shortDateTime(next.start, allDay: next.isAllDay))
                .accessibilityLabel("Nächstes Programm: \(next.title), \(WidgetFormat.shortDateTime(next.start, allDay: next.isAllDay))")
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.title).font(.caption).widgetAccentable()
                Text(next.title).font(.headline).lineLimit(2)
                Text(WidgetFormat.shortDateTime(next.start, allDay: next.isAllDay)).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nächstes Programm: \(next.title), \(WidgetFormat.longRange(start: next.start, end: next.end, allDay: next.isAllDay))")
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                Text(next.title).font(.headline.bold()).foregroundStyle(Color.ceviOnSurface).lineLimit(size == .small ? 2 : 3)
                Text(size == .small ? WidgetFormat.shortDateTime(next.start, allDay: next.isAllDay) : WidgetFormat.longRange(start: next.start, end: next.end, allDay: next.isAllDay))
                    .font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                if plan.showsPlace, let place = next.place {
                    Label(place, systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if plan.showsGroups { Chip(text: unit.name) }
                    if size != .small, let openText { Label(openText, systemImage: "questionmark.circle").font(.caption).foregroundStyle(Color.ceviOnSurface).lineLimit(2) }
                }
                if size == .small, let openText { Label(openText, systemImage: "questionmark.circle").font(.caption).foregroundStyle(Color.ceviOnSurface) }
                if plan.showsLater, unit.programs.count > 1 { later(Array(unit.programs.dropFirst().prefix(plan.rows))) }
                Spacer(minLength: 0)
                if let stand = model.stand, size != .small || stand.isStale || stand.isOffline { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func later(_ rows: [WidgetProgram]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Danach").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
            ForEach(rows) { row in
                Link(destination: WidgetLink.url(typ: "programm", id: row.id)) {
                    HStack {
                        Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(WidgetFormat.shortDateTime(row.start, allDay: row.isAllDay)).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                }
            }
        }
    }

    /// S: kind of the day and time only, never title or place.
    @ViewBuilder
    private func redacted(_ next: WidgetProgram) -> some View {
        switch size {
        case .inline:
            Text(WidgetFormat.shortDateTime(next.start, allDay: next.isAllDay))
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.title).font(.caption).widgetAccentable()
                Text("\(WidgetFormat.shortWeekday(next.start)) \(WidgetFormat.time(next.start))").font(.headline)
                Text("Zum Anzeigen die App öffnen").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                Text(WidgetFormat.redactedStart(next.start, allDay: next.isAllDay)).font(.headline.bold()).foregroundStyle(Color.ceviOnSurface)
                Text("Zum Anzeigen die App öffnen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                Spacer(minLength: 0)
                if let stand = model.stand, size != .small { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NextProgramWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextProgram", intent: SelectUnitIntent.self, provider: SnapshotProvider(kind: .nextProgram)) { entry in
            NextProgramView(entry: entry)
        }
        .configurationDisplayName("Nächstes Programm")
        .description("Zeigt das nächste Programm deiner Stufe mit Zeit und Treffpunkt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
