import SwiftUI

struct ChatRow: View {
    let chat: ChatSummary
    let profile: Profile

    private var title: String { ChatTitle.title(for: chat, profile: profile) }
    private var preview: String? {
        chat.lastMessage.map { "\($0.isOwn ? String(localized: "Du") : $0.author.displayName): \($0.text)" }
    }
    private var stamp: String? { chat.lastMessage.map { ChatDate.listStamp($0.createdAt) } }
    private var isUnread: Bool { chat.unread > 0 }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(.body.weight(isUnread ? .bold : .semibold))
                    .foregroundStyle(Color.ceviOnSurface)
                if let preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? Color.ceviOnSurface : Color.ceviOnSurfaceVariant)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Spacing.s2)
            VStack(alignment: .trailing, spacing: Spacing.s2) {
                if let stamp {
                    Text(stamp).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                if isUnread {
                    // Number plus bold title, so the unread state does not rely on color.
                    Text("\(chat.unread)")
                        .font(.caption.bold())
                        .foregroundStyle(Color.ceviOnPrimary)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, Spacing.s1)
                        .background(Color.ceviPrimary, in: .capsule)
                }
            }
        }
        // Design row height 72 pt, built from tokens (44 + 32 - 4) since Design.swift has no row token.
        .frame(minHeight: Size.touchTarget + Spacing.s8 - Spacing.s1, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [title]
        if isUnread { parts.append(String(localized: "\(chat.unread) ungelesen")) }
        if let preview { parts.append(preview) }
        if let stamp { parts.append(stamp) }
        return parts.joined(separator: ", ")
    }
}
