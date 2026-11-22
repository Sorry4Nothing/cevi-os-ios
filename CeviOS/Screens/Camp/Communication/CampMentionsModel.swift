import SwiftUI

/// L15: the places where the person is mentioned, with «Als Aufgabe» and «Erledigt».
@MainActor @Observable
final class CampMentionsModel {
    struct Notice: Equatable { let title: String; let message: String? }

    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var mentions: [CampMention] = []
    private(set) var staleSince: Date?
    private(set) var error: String?
    private(set) var notice: Notice?

    init(active: ActiveCamp) { self.active = active }

    /// Every member reads and marks the own mentions; a closed camp takes no change.
    var canWrite: Bool { !active.isReadOnly }
    var open: [CampMention] { mentions.filter { !$0.done } }
    var done: [CampMention] { mentions.filter(\.done) }

    func setPreview(phase: CampPhase, mentions: [CampMention], notice: Notice? = nil, offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.mentions = mentions
        self.notice = notice
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampMention] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campMentions(campId: campId, after: cursor, limit: 100)
                all += page.mentions
                cursor = page.next
            } while cursor != nil && all.count < 1000
            mentions = all
            phase = .loaded
            staleSince = nil
            error = nil
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if mentions.isEmpty { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    static func place(_ kind: CampMentionSourceKind) -> String {
        switch kind {
        case .task: String(localized: "in einer Aufgabe")
        case .agendaItem: String(localized: "in einem Traktandum")
        case .notice: String(localized: "auf der Pinnwand")
        case .resolution: String(localized: "in einem Beschluss")
        }
    }

    /// «Erwähnt auf der Pinnwand, gestern».
    func caption(_ mention: CampMention) -> String {
        String(localized: "Erwähnt \(Self.place(mention.sourceKind)), \(CampCommsText.relativeDay(mention.createdAt, now: now()))")
    }

    func setDone(_ mention: CampMention, _ done: Bool) async {
        guard canWrite, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run({ try await client.setCampMentionDone(campId: campId, mentionId: mention.id, done: done) }) {
        case .done(let changed):
            replace(changed)
            error = nil
        case .invalid(let text), .failed(let text): error = text
        }
    }

    func makeTask(_ mention: CampMention) async {
        guard canWrite, mention.taskId == nil, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run({ try await client.makeCampMentionTask(campId: campId, mentionId: mention.id) }) {
        case .done:
            error = nil
            show(Notice(title: String(localized: "Als Aufgabe angelegt."), message: String(localized: "«\(mention.title)» steht jetzt in deinen Aufgaben.")))
            await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    func dismissNotice() { notice = nil }

    private func replace(_ mention: CampMention) {
        if let index = mentions.firstIndex(where: { $0.id == mention.id }) { mentions[index] = mention }
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        AccessibilityNotification.Announcement([notice.title, notice.message].compactMap { $0 }.joined(separator: " ")).post()
    }
}
