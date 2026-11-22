import Foundation

/// A JSON value of an operation payload or of a row in a conflict answer. The payload fields belong to the modules
/// (`typ` names them); the app does not know them here, so it carries them as they are.
nonisolated enum CampJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([CampJSON])
    case object([String: CampJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([CampJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: CampJSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var intValue: Int? { if case .int(let value) = self { value } else { nil } }
}

/// One change collected offline. `clientOpId` is created once and kept on every retry: the server stores a `ok` for 30 days
/// and answers a repeat with the same result without writing again.
nonisolated struct CampOperation: Codable, Equatable, Identifiable, Sendable {
    let clientOpId: UUID
    /// Name of the operation, 1 to 64 characters, for example `aufgabe.aendern`.
    let type: String
    let payload: [String: CampJSON]

    var id: UUID { clientOpId }

    init(clientOpId: UUID = UUID(), type: String, payload: [String: CampJSON]) {
        self.clientOpId = clientOpId
        self.type = type
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey { case clientOpId, type = "typ", payload = "nutzlast" }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientOpId = try container.decode(UUID.self, forKey: .clientOpId)
        type = try container.decode(String.self, forKey: .type)
        payload = try container.decode([String: CampJSON].self, forKey: .payload)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientOpId.uuidString.lowercased(), forKey: .clientOpId)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
    }
}

/// Body of `POST …/aenderungen`: 1 to 100 operations, at most 256 KB.
nonisolated struct CampOperationBatch: Encodable, Sendable {
    static let maxOperations = 100

    let operations: [CampOperation]

    enum CodingKeys: String, CodingKey { case operations = "operationen" }
}

nonisolated enum CampOperationStatus: String, Decodable, Sendable {
    case ok
    case conflict = "konflikt"
    case rejected = "abgelehnt"
}

/// Result of one operation. The server answers in the order of the request; match by `clientOpId` all the same.
nonisolated struct CampOperationResult: Decodable, Equatable, Sendable {
    let clientOpId: UUID
    let status: CampOperationStatus
    /// Only on `ok`: IDs and versions of the written rows, no contents.
    let result: [String: CampJSON]?
    /// Only on `konflikt` (`VERSION_KONFLIKT`) and `abgelehnt` (see `CampRules.rejectionCodes`).
    let code: String?
    let message: String?
    /// Only on `konflikt`: the row as it stands now, in the view of the role.
    let current: [String: CampJSON]?
    /// Only on `konflikt`: the fields of the operation that differ now.
    let differing: [String]?

    enum CodingKeys: String, CodingKey {
        case clientOpId, status, result = "ergebnis", code, message, current = "aktuell", differing = "abweichend"
    }
}

nonisolated struct CampOperationResponse: Decodable, Equatable, Sendable {
    let results: [CampOperationResult]

    enum CodingKeys: String, CodingKey { case results = "ergebnisse" }
}

/// What the person chose in front of a conflict ("Meine übernehmen", "Aktuelle behalten", "Zusammenführen").
nonisolated enum CampConflictChoice: Equatable, Sendable {
    case keepMine
    case keepCurrent
    /// The person edited the fields by hand: the new payload.
    case merge([String: CampJSON])
}

nonisolated extension CampOperation {
    /// The follow-up of a conflict: the same change with a new `clientOpId` and the current `version` of the row. `nil` for
    /// `keepCurrent` (nothing to send) and when `current` carries no integer `version`.
    /// Assumption: the payload field is called `version`, like in the PATCH bodies of the modules; the description of
    /// `…/aenderungen` does not list the payload fields.
    func resolved(_ choice: CampConflictChoice, current: [String: CampJSON]?) -> CampOperation? {
        guard let version = current?["version"]?.intValue else { return nil }
        var next: [String: CampJSON]
        switch choice {
        case .keepCurrent: return nil
        case .keepMine: next = payload
        case .merge(let merged): next = merged
        }
        next["version"] = .int(version)
        return CampOperation(type: type, payload: next)
    }
}

// MARK: Event stream

/// A message of the event stream, as the format `text/event-stream` carries it.
nonisolated struct CampServerEvent: Equatable, Sendable {
    let id: Int?
    /// `message` if the message had no `event` field.
    let name: String
    let data: String
}

/// Parser of `text/event-stream`: fields `id`, `event`, `data` (several `data` lines are joined with a line feed), comment
/// lines (`:`) are ignored, an empty line ends a message. Lines end with LF, CR LF or CR. Feed bytes in any chunking.
nonisolated struct CampEventParser: Sendable {
    private var line: [UInt8] = []
    private var lastWasCR = false
    private var lastId: Int?
    private var name = ""
    private var data: [String] = []

    init() {}

    mutating func consume(_ bytes: some Sequence<UInt8>) -> [CampServerEvent] {
        var events: [CampServerEvent] = []
        for byte in bytes {
            if byte == 0x0A, lastWasCR { lastWasCR = false; continue }
            lastWasCR = byte == 0x0D
            if byte == 0x0A || byte == 0x0D {
                if let event = finishLine() { events.append(event) }
            } else {
                line.append(byte)
            }
        }
        return events
    }

    private mutating func finishLine() -> CampServerEvent? {
        defer { line = [] }
        let text = String(decoding: line, as: UTF8.self)
        if text.isEmpty {
            defer { name = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return CampServerEvent(id: lastId, name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        if text.hasPrefix(":") { return nil }
        let field: Substring, value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            let rest = text[text.index(after: colon)...]
            value = rest.hasPrefix(" ") ? rest.dropFirst() : rest
        } else {
            (field, value) = (text[...], "")
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        case "id": if !value.contains("\0") { lastId = Int(value) }
        default: break // `retry` and unknown fields
        }
        return nil
    }
}

/// What the stream tells: that there is news, never what. The content comes from the change feed
/// (`campChanges(campId:since:)`), where the row filter of the role applies.
nonisolated enum CampLiveEvent: Equatable, Sendable {
    /// First message: the stand of the camp.
    case ready(upTo: Int)
    /// News up to `upTo` in these object types.
    case changed(upTo: Int, objectTypes: [String])
    /// The sequence number of the app lies in the future (camp restored): load anew.
    case reload(upTo: Int)
    /// The server ends the connection (`neu-verbinden`): connect again with the last `upTo`.
    case end
    /// A message the app does not know; ignore it.
    case unknown(String)

    /// `upTo` of the message, to send as `Last-Event-ID` on reconnect.
    var upTo: Int? {
        switch self {
        case .ready(let value), .reload(let value): value
        case .changed(let value, _): value
        case .end, .unknown: nil
        }
    }

    private struct Payload: Decodable {
        let bis: Int?
        let objekttypen: [String]?
    }

    /// `nil` if the data of a known message is not JSON of the expected shape.
    init?(_ event: CampServerEvent) {
        let payload = try? JSONDecoder().decode(Payload.self, from: Data(event.data.utf8))
        switch event.name {
        case "bereit": guard let up = payload?.bis else { return nil }; self = .ready(upTo: up)
        case "aenderung": guard let up = payload?.bis else { return nil }; self = .changed(upTo: up, objectTypes: payload?.objekttypen ?? [])
        case "neu-laden": guard let up = payload?.bis else { return nil }; self = .reload(upTo: up)
        case "ende": self = .end
        default: self = .unknown(event.name)
        }
    }
}
