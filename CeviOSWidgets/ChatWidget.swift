import SwiftUI
import WidgetKit

/// W6 «Chat»: only the numbers, never contents or names.
struct ChatView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redaction

    private let spec = WidgetSpec(title: String(localized: "Chat"), symbol: "bubble.left.and.bubble.right", emptyText: String(localized: "Alles gelesen"), emptySymbol: "checkmark.circle")
    private var size: WidgetSize { WidgetSize(family) }
    private var model: WidgetModel { entry.model(.chat, privacy: redaction.contains(.privacy)) }

    var body: some View {
        WidgetRoot(size: size, link: WidgetLink.url(typ: "chats")) {
            if let chat = model.snapshot?.chat, model.phase == .content || model.phase == .redacted {
                filled(chat, redacted: model.phase == .redacted)
            } else {
                WidgetStateBody(phase: model.phase, spec: spec, size: size)
            }
        }
    }

    @ViewBuilder
    private func filled(_ chat: WidgetChat, redacted: Bool) -> some View {
        let label = String(localized: "\(chat.unread) ungelesen")
        switch size {
        case .inline:
            Text(label)
        case .circular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(chat.unread)").font(.headline)
                    Text("ungelesen").font(.system(size: 8))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: spec.title, symbol: spec.symbol)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(chat.unread)").font(.largeTitle.bold()).foregroundStyle(Color.ceviPrimary)
                    Text("ungelesen").font(.headline).foregroundStyle(Color.ceviOnSurface)
                }
                if redacted {
                    if size == .medium { Text("Zum Anzeigen die App öffnen").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant) }
                } else if size == .small {
                    Text("in \(chat.chats) Chats").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                } else {
                    Text("in \(chat.chats) Chats. Tippe, um den Chat zu öffnen.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                Spacer(minLength: 0)
                if let stand = model.stand, size != .small || stand.isStale || stand.isOffline { StandLine(stand: stand) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct ChatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Chat", provider: PlainProvider()) { entry in
            ChatView(entry: entry)
        }
        .configurationDisplayName("Chat")
        .description("Zeigt, wie viele Nachrichten ungelesen sind. Nie den Inhalt.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}
