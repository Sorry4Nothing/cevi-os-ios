import Foundation

/// Public pages of the server (no sign-in needed).
nonisolated enum ServerPage: String {
    case privacy = "/datenschutz"
    case support = "/support"
    case deleteAccount = "/konto-loeschen"

    func url(base: URL?) -> URL? {
        base.flatMap { URL(string: $0.absoluteString + rawValue) }
    }
}
