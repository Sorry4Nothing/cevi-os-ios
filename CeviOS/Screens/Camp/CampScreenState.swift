import SwiftUI

/// The cross-cutting states U1 to U8 of the camp module, and which error leads to which.
nonisolated enum CampScreenState: String, Equatable, Hashable, Identifiable, Sendable {
    /// U1: 401.
    case sessionEnded
    /// U2: 404.
    case notFound
    /// U3: 403.
    case noAccess
    /// U4: 503 or the code `WARTUNG`.
    case maintenance
    /// No answer at all (the banner U6 tells about waiting changes).
    case offline
    /// U7: 409 `VERSION_KONFLIKT`.
    case versionConflict
    /// U8: 409 `LAGER_GESCHLOSSEN`.
    case closed

    var id: String { rawValue }

    /// `nil` for errors without a state of their own (the screen then shows the general error).
    init?(error: APIError) {
        if error.status == 503 || error.code == CampRules.maintenanceCode {
            self = .maintenance
            return
        }
        switch error.kind {
        case .unauthorized: self = .sessionEnded
        case .notFound: self = .notFound
        case .forbidden: self = .noAccess
        case .network: self = .offline
        case .conflict:
            switch error.code {
            case CampRules.closedCode: self = .closed
            case CampRules.versionConflictCode: self = .versionConflict
            default: return nil
            }
        default: return nil
        }
    }

    /// Full-screen states; the closed camp is a banner and the conflict has its own screen (`CampConflictView`).
    var isFullScreen: Bool { self != .closed && self != .versionConflict }
}

/// Full-screen view of a `CampScreenState`. Texts are those of the design (U1 to U4); `notFoundMessage` names the object.
struct CampStateView: View {
    let state: CampScreenState
    var notFoundMessage: LocalizedStringKey = "Das gibt es nicht mehr. Vielleicht wurde es gelöscht."
    var back: StateView.Action?
    var signIn: () -> Void = {}
    var retry: () -> Void = {}

    var body: some View {
        switch state {
        case .sessionEnded:
            StateView.sessionEnded(signIn: signIn)
        case .notFound:
            StateView(symbol: "magnifyingglass", title: "Nicht gefunden", message: notFoundMessage, primary: back)
        case .noAccess:
            StateView(symbol: "lock", title: "Kein Zugriff", message: "Du bist in diesem Lager nicht dabei. Frag die Lagerleitung.", primary: back)
        case .maintenance:
            StateView(symbol: "wrench.and.screwdriver", title: "Wartung",
                      message: "Das Lager-Modul ist gerade nicht erreichbar. Deine Änderungen bleiben auf dem Gerät.",
                      primary: .init(title: "Nochmals versuchen", symbol: "arrow.clockwise", perform: retry), secondary: back)
        case .offline:
            StateView.offline(retry: retry)
        case .closed:
            CampClosedBanner().padding(Spacing.s4)
        case .versionConflict:
            // The conflict is shown by `CampConflictView`, which needs the two versions.
            EmptyView()
        }
    }
}

#Preview("U1 Sitzung abgelaufen") { CampStateView(state: .sessionEnded) }
#Preview("U2 Nicht gefunden") {
    CampStateView(state: .notFound, notFoundMessage: "Diese Aufgabe gibt es nicht mehr. Vielleicht wurde sie gelöscht.",
                  back: .init(title: "Zu den Aufgaben") {})
}
#Preview("U3 Kein Zugriff") { CampStateView(state: .noAccess, back: .init(title: "Zu deinen Lagern") {}) }
#Preview("U4 Wartung") { CampStateView(state: .maintenance) }
#Preview("U4 Wartung Nacht") { CampStateView(state: .maintenance).preferredColorScheme(.dark) }
