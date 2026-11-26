import SwiftUI
import WidgetKit

/// W5 «Notfall»: no data of its own, a tap opens the emergency page of the camp (it works without network).
struct EmergencyView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redaction

    private let spec = WidgetSpec(title: String(localized: "Notfall"), symbol: "cross", emptyText: "", emptySymbol: "cross")
    private var size: WidgetSize { WidgetSize(family) }
    private var model: WidgetModel { entry.model(.emergency, privacy: redaction.contains(.privacy)) }

    var body: some View {
        WidgetRoot(size: size, link: WidgetLink.url(typ: model.camp == nil ? nil : "lager_notfall", id: model.camp?.id)) {
            if model.phase == .content || model.phase == .redacted {
                filled
            } else {
                WidgetStateBody(phase: model.phase, spec: spec, size: size)
            }
        }
    }

    @ViewBuilder
    private var filled: some View {
        if size == .circular {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "cross.fill").widgetAccentable()
                    Text("Notfall").font(.system(size: 9, weight: .semibold))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notfall. Öffnet die Notfall-Seite mit allen Nummern.")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                Text("Notfall").font(.title2.bold()).foregroundStyle(Color.ceviOnSurface)
                if size == .medium, !typeSize.isAccessibilitySize {
                    Text("Öffnet die Notfall-Seite mit allen Nummern.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                Spacer(minLength: 0)
                Label("Funktioniert auch ohne Netz", systemImage: "wifi.slash").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notfall. Öffnet die Notfall-Seite mit allen Nummern. Funktioniert auch ohne Netz.")
        }
    }
}

struct EmergencyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Emergency", provider: PlainProvider()) { entry in
            EmergencyView(entry: entry)
        }
        .configurationDisplayName("Notfall")
        .description("Öffnet mit einem Tipp die Notfall-Seite des Lagers.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
