import SwiftUI
import WidgetKit

extension WidgetSize {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .systemLarge, .systemExtraLarge, .systemExtraLargePortrait: self = .large
        case .accessoryCircular: self = .circular
        case .accessoryRectangular: self = .rectangular
        case .accessoryInline: self = .inline
        @unknown default: self = .small
        }
    }

    var isSystem: Bool { self == .small || self == .medium || self == .large }
}

/// Fixed texts of one widget for the states without content.
struct WidgetSpec {
    let title: String
    let symbol: String
    let emptyText: String
    let emptySymbol: String
}

/// Texts and symbols of the states I, U, F, R, E (design boards W1 to W6).
struct WidgetStateBody: View {
    let phase: WidgetPhase
    let spec: WidgetSpec
    let size: WidgetSize

    private var long: (symbol: String, text: String) {
        switch phase {
        case .neverOpened: ("clock", String(localized: "Wird geladen, sobald die App geöffnet wird"))
        case .signedOut: ("person.crop.circle", String(localized: "Zum Anzeigen in der App anmelden"))
        case .failed: ("exclamationmark.triangle", String(localized: "Etwas ist schiefgelaufen. Tippe, um die App zu öffnen."))
        case .noCamp: ("tent", String(localized: "Kein Lager. Sobald dich die Lagerleitung hinzufügt, erscheint es hier."))
        default: (spec.emptySymbol, spec.emptyText)
        }
    }

    private var short: String {
        switch phase {
        case .neverOpened: String(localized: "Wird geladen …")
        case .signedOut: String(localized: "In der App anmelden")
        case .failed: String(localized: "Fehler. App öffnen")
        case .noCamp: String(localized: "Kein Lager")
        default: spec.emptyText
        }
    }

    private var circular: String {
        switch phase {
        case .neverOpened: String(localized: "Laden")
        case .signedOut: String(localized: "Anmelden")
        case .failed: String(localized: "Fehler")
        case .noCamp: String(localized: "Kein Lager")
        default: "0"
        }
    }

    var body: some View {
        Group {
            switch size {
            case .inline:
                Text(short)
            case .circular:
                ZStack {
                    AccessoryWidgetBackground()
                    Text(circular).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                }
            case .rectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title).font(.headline).widgetAccentable()
                    Text(long.text).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .small, .medium, .large:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: spec.title, symbol: spec.symbol)
                    WidgetNote(symbol: long.symbol, text: long.text)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(size == .inline || size == .circular ? short : "\(spec.title). \(long.text)")
    }
}

/// Common wrapper: one tap target for the whole widget, accessory widgets get the system background.
struct WidgetRoot<Content: View>: View {
    let size: WidgetSize
    let link: URL
    @ViewBuilder let content: Content

    var body: some View {
        content
            .widgetURL(link)
            .ceviWidgetBackground()
    }
}
