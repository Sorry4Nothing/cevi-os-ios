import SwiftUI
import WidgetKit

/// W2 «Mein Kalender».
struct CalendarView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redaction

    private let spec = WidgetSpec(title: String(localized: "Mein Kalender"), symbol: "calendar", emptyText: String(localized: "Keine Termine für dich"), emptySymbol: "calendar")
    private var size: WidgetSize { WidgetSize(family) }
    private var model: WidgetModel { entry.model(.calendar, privacy: redaction.contains(.privacy)) }
    private var events: [WidgetEvent] { model.snapshot?.events ?? [] }
    private var header: String { String(localized: "Mein Kalender, \(events.count) Termine") }

    var body: some View {
        WidgetRoot(size: size, link: events.first.map { WidgetLink.url(typ: "programm", id: $0.id) } ?? WidgetLink.url()) {
            switch model.phase {
            case .content, .redacted: rows(redacted: model.phase == .redacted)
            default: WidgetStateBody(phase: model.phase, spec: spec, size: size)
            }
        }
    }

    @ViewBuilder
    private func rows(redacted: Bool) -> some View {
        let plan = WidgetLayoutPlan.calendar(size, largeType: typeSize.isAccessibilitySize)
        let shown = Array(events.prefix(plan.rows))
        if size == .rectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.title).font(.caption).widgetAccentable()
                if let first = shown.first {
                    Text(redacted ? "\(WidgetFormat.shortWeekday(first.start)) \(WidgetFormat.time(first.start))" : first.title).font(.headline).lineLimit(2)
                    Text(redacted ? String(localized: "Zum Anzeigen die App öffnen") : WidgetFormat.shortDateTime(first.start, allDay: first.isAllDay)).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: size == .small ? spec.title : header, symbol: spec.symbol)
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider() }
                    row(event, redacted: redacted)
                }
                if redacted { Text("Zum Anzeigen die App öffnen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant) }
                Spacer(minLength: 0)
                if let stand = model.stand, size != .small || stand.isStale || stand.isOffline { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(header)
        }
    }

    @ViewBuilder
    private func row(_ event: WidgetEvent, redacted: Bool) -> some View {
        if redacted {
            Text(WidgetFormat.shortDateTime(event.start, allDay: event.isAllDay)).font(.footnote).foregroundStyle(Color.ceviOnSurface)
        } else if size == .small {
            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetFormat.shortDateTime(event.start, allDay: event.isAllDay)).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                Text(event.title).font(.headline.bold()).foregroundStyle(Color.ceviOnSurface).lineLimit(2)
                HStack { ForEach(event.groups.prefix(2), id: \.self) { Chip(text: $0) } }
            }
        } else {
            Link(destination: WidgetLink.url(typ: "programm", id: event.id)) {
                HStack(spacing: 8) {
                    Text(WidgetFormat.shortDateTime(event.start, allDay: event.isAllDay))
                        .font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant).frame(width: 78, alignment: .leading)
                    Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface).lineLimit(2)
                    Spacer(minLength: 4)
                    if WidgetLayoutPlan.calendar(size, largeType: typeSize.isAccessibilitySize).showsGroups {
                        HStack(spacing: 4) { ForEach(event.groups.prefix(2), id: \.self) { Chip(text: $0) } }
                    }
                }
            }
        }
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Calendar", provider: PlainProvider()) { entry in
            CalendarView(entry: entry)
        }
        .configurationDisplayName("Mein Kalender")
        .description("Zeigt deine nächsten Termine aus allen deinen Gruppen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
