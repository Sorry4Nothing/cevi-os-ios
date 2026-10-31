import Foundation

/// Error shape of the server: `{ "code": …, "message": … }`.
nonisolated struct ErrorBody: Decodable, Equatable, Sendable {
    let code: String
    let message: String
}

/// Error of the API client, mapped from status code and error body.
nonisolated struct APIError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case invalidInput // 400
        case unauthorized // 401
        case forbidden // 403
        case notFound // 404
        case conflict // 409
        case payloadTooLarge // 413
        case unsupportedMediaType // 415
        case appOutdated // 426
        case rateLimited // 429
        case server // 5xx and everything else
        case network // no response
    }

    let kind: Kind
    let status: Int?
    /// Code of the server, e.g. `NICHT_ANGEMELDET`. `nil` without a readable error body.
    let code: String?
    /// Text of the server. For better-auth codes (English) not meant for display.
    let message: String?

    static func from(status: Int, data: Data) -> APIError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let kind: Kind = switch status {
        case 400: .invalidInput
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 409: .conflict
        case 413: .payloadTooLarge
        case 415: .unsupportedMediaType
        case 426: .appOutdated
        case 429: .rateLimited
        default: .server
        }
        return APIError(kind: kind, status: status, code: body?.code, message: body?.message)
    }

    static let network = APIError(kind: .network, status: nil, code: nil, message: nil)

    /// Text for display. For 429 always «Bitte kurz warten.», otherwise the server's text if present.
    var displayText: String {
        switch kind {
        case .rateLimited:
            String(localized: "Bitte kurz warten.")
        case .network:
            String(localized: "Keine Verbindung zum Server. Bitte später nochmals versuchen.")
        case .appOutdated:
            String(localized: "Bitte die App aktualisieren.")
        default:
            message ?? String(localized: "Etwas ist schiefgegangen. Bitte später nochmals versuchen.")
        }
    }
}
