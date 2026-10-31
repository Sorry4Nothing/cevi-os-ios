import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    @Environment(\.colorSchemeContrast) private var contrast

    private var bubbleShape: UnevenRoundedRectangle {
        // The corner towards the sender stays small, like a speech bubble tail.
        UnevenRoundedRectangle(
            topLeadingRadius: Radius.lg,
            bottomLeadingRadius: message.isOwn ? Radius.lg : Spacing.s2,
            bottomTrailingRadius: message.isOwn ? Spacing.s2 : Radius.lg,
            topTrailingRadius: Radius.lg,
            style: .continuous
        )
    }

    private var senderLabel: String {
        let name = message.author.ceviName ?? message.author.name
        return message.author.isUnitLeader ? String(localized: "\(name) · SL") : name
    }

    private var senderAccessibility: String {
        message.author.displayName + (message.author.isUnitLeader ? String(localized: " (Stufenleitung)") : "")
    }

    var body: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: Spacing.s1) {
            // Own messages sit on the right and are read as "Du", so the difference does not rely on color.
            if !message.isOwn {
                Text(senderLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ceviAccent)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.isOwn ? Color.ceviOnSecondary : Color.ceviOnSurface)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
                .background(message.isOwn ? Color.ceviSecondary : Color.ceviSurfaceContainerLow, in: bubbleShape)
                .overlay {
                    if !message.isOwn { bubbleShape.strokeBorder(contrast == .increased ? Color.ceviOutline : Color.ceviOutlineVariant, lineWidth: Size.border) }
                }
            if let program = message.program {
                Label(program.title, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            Text(message.isOwn ? "\(ChatDate.time(message.createdAt)) · Gesendet" : "\(ChatDate.time(message.createdAt))")
                .font(.caption)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
        .padding(message.isOwn ? .leading : .trailing, Spacing.s8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [message.isOwn ? String(localized: "Du") : senderAccessibility, message.text]
        if let program = message.program { parts.append(program.title) }
        parts.append(ChatDate.time(message.createdAt))
        if message.isOwn { parts.append(String(localized: "Gesendet")) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Nachrichten") {
    let leader = ChatAuthor(id: UUID(), name: "Sarah Muster", ceviName: "Sarah", imageURL: nil, isUnitLeader: true)
    let me = ChatAuthor(id: UUID(), name: "Robin Lehmann", ceviName: nil, imageURL: nil, isUnitLeader: false)
    ScrollView {
        VStack(spacing: Spacing.s3) {
            MessageRow(message: ChatMessage(id: UUID(), text: "Hoi zäme, Noah kommt am Samstag etwas später, etwa 14:30.",
                                            createdAt: .now, author: me, program: nil, isOwn: true))
            MessageRow(message: ChatMessage(id: UUID(), text: "Kein Problem, wir sind bis 15:00 beim Gemeindehaus.",
                                            createdAt: .now, author: leader, program: nil, isOwn: false))
        }
        .padding(Spacing.s4)
    }
    .ceviScreenBackground()
}
