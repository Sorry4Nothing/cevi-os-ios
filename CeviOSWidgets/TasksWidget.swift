import SwiftUI
import WidgetKit

/// W4 «Meine Aufgaben».
struct TasksView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redaction

    private let spec = WidgetSpec(title: String(localized: "Meine Aufgaben"), symbol: "checkmark.circle", emptyText: String(localized: "Keine offenen Aufgaben"), emptySymbol: "checkmark.circle")
    private var size: WidgetSize { WidgetSize(family) }
    private var model: WidgetModel { entry.model(.tasks, privacy: redaction.contains(.privacy)) }

    var body: some View {
        WidgetRoot(size: size, link: WidgetLink.url(typ: model.camp == nil ? nil : "lager_aufgaben", id: model.camp?.id)) {
            if let camp = model.camp, model.phase == .content || model.phase == .redacted {
                filled(camp, redacted: model.phase == .redacted)
            } else {
                WidgetStateBody(phase: model.phase, spec: spec, size: size)
            }
        }
    }

    private func overdueLabel(_ n: Int) -> String { String(localized: "\(n) überfällig") }

    @ViewBuilder
    private func filled(_ camp: WidgetCamp, redacted: Bool) -> some View {
        let plan = WidgetLayoutPlan.tasks(size, largeType: typeSize.isAccessibilitySize)
        switch size {
        case .circular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(camp.overdueCount)").font(.headline)
                    Text("überfällig").font(.system(size: 8))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(overdueLabel(camp.overdueCount))
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(overdueLabel(camp.overdueCount)).font(.headline).widgetAccentable()
                if redacted {
                    Text("Zum Anzeigen die App öffnen").font(.caption)
                } else if let task = camp.tasks.first {
                    Text(task.title).font(.caption).lineLimit(2)
                    if let due = task.due { Text("Frist \(WidgetFormat.dueDay(due))").font(.caption2) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(camp.overdueCount)").font(.title.bold()).foregroundStyle(Color.ceviPrimary)
                    Text("überfällig").font(.headline).foregroundStyle(Color.ceviOnSurface)
                }
                if redacted {
                    Text("Zum Anzeigen die App öffnen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                } else if size == .small {
                    if let task = camp.tasks.first {
                        Text("Nächste:").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
                        Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface).lineLimit(3)
                    }
                } else {
                    ForEach(Array(camp.tasks.prefix(plan.rows))) { task in
                        Link(destination: WidgetLink.url(typ: "lager_aufgabe", id: task.id)) { taskRow(task) }
                    }
                    if plan.showsLater {
                        Divider()
                        if let later = camp.laterCount { summary(String(localized: "Später fällig"), later) }
                        if let done = camp.doneThisWeek { summary(String(localized: "Diese Woche erledigt"), done) }
                    }
                }
                Spacer(minLength: 0)
                if let stand = model.stand, size != .small || stand.isStale || stand.isOffline { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func taskRow(_ task: WidgetTask) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface).lineLimit(2)
                if let due = task.due { Text("Frist \(WidgetFormat.dueDay(due))").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
            }
            Spacer(minLength: 4)
            if task.isOverdue {
                Label("Überfällig", systemImage: "exclamationmark.triangle").font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ceviOnErrorContainer).padding(.horizontal, 6).padding(.vertical, 2).background(Color.ceviErrorContainer, in: Capsule())
            } else {
                Label("Bald", systemImage: "clock").font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ceviOnWarningContainer).padding(.horizontal, 6).padding(.vertical, 2).background(Color.ceviWarningContainer, in: Capsule())
            }
        }
    }

    private func summary(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            Spacer()
            Text(count == 1 ? "1 Aufgabe" : "\(count) Aufgaben").font(.footnote.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
        }
    }
}

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Tasks", provider: PlainProvider()) { entry in
            TasksView(entry: entry)
        }
        .configurationDisplayName("Meine Aufgaben")
        .description("Zeigt, wie viele Aufgaben überfällig sind, und die nächsten Fristen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
