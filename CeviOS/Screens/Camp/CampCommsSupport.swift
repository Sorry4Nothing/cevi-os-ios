import SwiftUI

/// What the role may do in meetings, protocols, notice board and inbox. The defaults of the rights matrix (`docs/lager.md`):
/// the app shows only these actions, the server decides again. A missing action is a missing button.
nonisolated struct CampCommsRights: Equatable, Sendable {
    let role: CampRole?
    /// The camp is completed or archived.
    let readOnly: Bool

    private var isLead: Bool { role == .campLeader }
    private var edits: Bool { role == .campLeader || role == .leader }

    /// The team sees the team meetings in the short form only.
    var seesAllMeetings: Bool { role == .campLeader || role == .leader || role == .readOnly }
    var editsMeetings: Bool { !readOnly && edits }
    var readsProtocols: Bool { seesAllMeetings }
    var editsProtocols: Bool { !readOnly && edits }
    var editsNotices: Bool { !readOnly && edits }
    /// Votes and reactions.
    var interacts: Bool { !readOnly && (edits || role == .team) }
    var readsInbox: Bool { isLead }
    var answersInbox: Bool { !readOnly && isLead }
}

/// The answer of a write with a row version: written, someone else changed the row (`conflict` holds the row as it stands), or failed.
nonisolated enum CampWriteOutcome<Value: Sendable, Row: Sendable>: Sendable {
    case done(Value)
    case conflict(Row)
    /// 400: the text names the field.
    case invalid(String)
    case failed(String)
}

@MainActor
enum CampCommsWrite {
    /// Runs one write. `as` is the row type of a 409 `VERSION_KONFLIKT`.
    static func run<Value: Sendable, Row: Decodable & Sendable>(as row: Row.Type, _ perform: () async throws -> Value) async -> CampWriteOutcome<Value, Row> {
        do {
            return .done(try await BusyState.shared.track(perform))
        } catch let error as APIError {
            if let conflict = CampRules.versionConflict(error, as: Row.self)?.current { return .conflict(conflict) }
            return error.kind == .invalidInput ? .invalid(error.displayText) : .failed(CampRules.writeError(error))
        } catch {
            return .failed(APIError.network.displayText)
        }
    }

    /// For writes without a version (no conflict possible).
    static func run<Value: Sendable>(_ perform: () async throws -> Value) async -> CampWriteOutcome<Value, Never> {
        await run(as: Never.self, perform)
    }
}

nonisolated enum CampCommsText {
    private static func style() -> Date.FormatStyle { Date.FormatStyle(locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone) }

    /// «Mittwoch, 26. Mai» and with a time «Mittwoch, 26. Mai, 19:30».
    static func meetingDate(_ date: Date, time: String?) -> String {
        let day = date.formatted(style().weekday(.wide).day().month(.wide))
        return time.map { "\(day), \($0)" } ?? day
    }

    static func day(_ date: Date) -> String { date.formatted(style().day().month(.wide)) }

    /// «heute 08:12» and «gestern», older days with the date.
    static func relativeDay(_ date: Date, now: Date) -> String {
        let days = CampTaskText.days(from: date, to: now)
        switch days {
        case 0: return String(localized: "heute")
        case 1: return String(localized: "gestern")
        default: return day(date)
        }
    }

    static func agendaCount(_ n: Int) -> String { n == 1 ? String(localized: "1 Traktandum") : String(localized: "\(n) Traktanden") }
    static func votes(_ n: Int) -> String { n == 1 ? String(localized: "1 Stimme") : String(localized: "\(n) Stimmen") }

    static func initials(_ name: String?) -> String { String((name ?? "?").prefix(1)).uppercased() }
}

/// The states every list screen of this slice shares: loading, failure, content.
struct CampPhaseView<Content: View>: View {
    let phase: CampPhase
    let loading: LocalizedStringKey
    var notFound: LocalizedStringKey = "Das gibt es nicht mehr. Vielleicht wurde es gelöscht."
    var back: StateView.Action?
    let retry: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        switch phase {
        case .loading: LoadingView(label: loading)
        case .failed(let state, _):
            if let state, state.isFullScreen, state != .offline {
                CampStateView(state: state, notFoundMessage: notFound, back: back, retry: retry)
            } else {
                StateView.failure(retry: retry, back: back)
            }
        case .loaded: content
        }
    }
}

/// A screen body: scrolling column with the shared banners, a message line and the content.
struct CampScroll<Content: View>: View {
    var staleSince: Date?
    var error: String?
    var notice: CampNoticeData?
    var refresh: () async -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                CampBannerStack(staleSince: staleSince)
                if let notice { CampNoticeBar(title: notice.title, message: notice.message, undo: notice.undo, dismiss: notice.dismiss) }
                if let error { ErrorRow(text: error) }
                content
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .ceviScreenBackground()
    }
}

/// «Als Traktandum übernommen.» with the optional «Rückgängig».
struct CampNoticeData {
    let title: String
    var message: String?
    var undo: (() -> Void)?
    let dismiss: () -> Void
}

/// The one main action at the bottom right (the other buttons of a screen are quiet).
struct CampMainAction: View {
    let title: LocalizedStringKey
    var symbol = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(CeviPrimaryButtonStyle(expands: false))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, Spacing.s4)
    }
}
