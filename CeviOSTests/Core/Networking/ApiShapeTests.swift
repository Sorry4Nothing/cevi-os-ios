import Foundation
import Testing
@testable import CeviOS

/// The simulated server of the UI tests must answer in the shape of the API description: every `required` field of the
/// response schema is present, and no field the description does not know. Together with the decoding tests this ties the
/// models to the description without a YAML parser: the `required` lists are read from `openapi.yaml` line by line
/// (block style, as the backend writes it), the answers come from the same simulated server the UI tests use.
struct ApiShapeTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Schema name to its direct `required` list and property names (only the lines at schema level, not nested ones).
    static func schemas() throws -> [String: (required: [String], properties: [String])] {
        let text = try String(contentsOf: root.appending(path: "api-vertrag/openapi.yaml"), encoding: .utf8)
        var result: [String: (required: [String], properties: [String])] = [:]
        var inSchemas = false
        var name: String?
        var section = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "  schemas:" { inSchemas = true; continue }
            guard inSchemas else { continue }
            if !line.isEmpty, !line.hasPrefix("  ") { break }
            if line.hasPrefix("    "), !line.hasPrefix("     "), line.hasSuffix(":") {
                name = String(line.dropFirst(4).dropLast())
                result[name!] = ([], [])
                section = ""
            } else if line.hasPrefix("      "), !line.hasPrefix("       "), line.hasSuffix(":") {
                section = line.trimmingCharacters(in: .whitespaces)
            } else if let name, section == "required:", line.hasPrefix("        - ") {
                result[name]?.required.append(String(line.dropFirst(10)))
            } else if let name, section == "properties:", line.hasPrefix("        "), !line.hasPrefix("         "), line.hasSuffix(":") {
                result[name]?.properties.append(String(line.dropFirst(8).dropLast()))
            }
        }
        return result
    }

    private nonisolated indirect enum Raw: Decodable, Sendable {
        case object([String: Raw]), array([Raw]), other

        init(from decoder: any Decoder) throws {
            if let object = try? decoder.container(keyedBy: AnyKey.self) {
                self = .object(try Dictionary(uniqueKeysWithValues: object.allKeys.map { ($0.stringValue, try object.decode(Raw.self, forKey: $0)) }))
            } else if var list = try? decoder.unkeyedContainer() {
                var items: [Raw] = []
                while !list.isAtEnd { items.append(try list.decode(Raw.self)) }
                self = .array(items)
            } else {
                self = .other
            }
        }

        struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
    }

    private func client(_ username: String) async throws -> APIClient {
        let client = APIClient(
            baseURL: URL(string: "https://ui-test.example.org")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [UITestBackend.self])
        )
        struct Credentials: Encodable { let username: String; let password: String }
        try await client.send("POST", "/api/auth/sign-in/username", body: Credentials(username: username, password: "geheim-geheim"))
        return client
    }

    /// One answer: path, schemas whose `required` list the object must fill, and the list key whose items follow `itemSchemas`.
    private struct Case {
        let path: String
        let schemas: [String]
        var listKey: String?
        var itemSchemas: [String] = []
    }

    private func check(_ cases: [Case], as username: String) async throws -> [String] {
        let known = try Self.schemas()
        let client = try await client(username)
        var failures: [String] = []
        func compare(_ object: [String: Raw], _ names: [String], _ label: String) {
            let required = Set(names.flatMap { known[$0]?.required ?? [] })
            let allowed = required.union(names.flatMap { known[$0]?.properties ?? [] })
            if names.contains(where: { known[$0] == nil }) { failures.append("\(label): unknown schema") }
            for key in required.subtracting(object.keys) { failures.append("\(label): missing required «\(key)»") }
            // With `allOf` (several names) the extra keys come from the inline part, which this reader does not see.
            for key in Set(object.keys).subtracting(allowed) where names.count == 1 { failures.append("\(label): «\(key)» is not in the description") }
        }
        for item in cases {
            do {
                guard case .object(let object) = try await client.load("GET", item.path) as Raw else { failures.append("\(item.path): not an object"); continue }
                compare(object, item.schemas, item.path)
                if let key = item.listKey, case .array(let rows)? = object[key] {
                    if rows.isEmpty { failures.append("\(item.path): «\(key)» is empty, the shape is not checked") }
                    for case .object(let row) in rows where !item.itemSchemas.isEmpty { compare(row, item.itemSchemas, item.path + " " + key) }
                }
            } catch {
                failures.append("\(item.path): \(error)")
            }
        }
        return failures
    }

    @Test func descriptionHoldsTheSchemasTheTestsNeed() throws {
        let known = try Self.schemas()
        #expect(known["IchProfil"]?.required.contains("abteilungsleitung") == true)
        #expect(known["IchProfil"]?.required.contains("admin") == false)
        #expect(known["ProgrammListeneintrag"]?.properties.contains("sichtbarkeit") == false)
        #expect(known["Lager"]?.required.contains("wetterOrt") == true)
    }

    @Test func leadAnswersMatchTheDescription() async throws {
        let camp = World.activeCamp
        let failures = try await check([
            Case(path: "/api/v1/ich", schemas: ["IchProfil"]),
            Case(path: "/api/v1/stufen", schemas: ["StufenAntwort"], listKey: "stufen", itemSchemas: ["StufenAntwortEintrag"]),
            Case(path: "/api/v1/chats", schemas: ["ChatListe"], listKey: "chats", itemSchemas: ["ChatListeneintrag"]),
            Case(path: "/api/v1/termine/mein", schemas: ["TerminMeinListe"], listKey: "termine", itemSchemas: ["TerminMeinEintrag"]),
            Case(path: "/api/v1/programme", schemas: ["ProgrammListe"], listKey: "programme", itemSchemas: ["ProgrammListeneintrag"]),
            Case(path: "/api/v1/programme/00000000-0000-0000-0000-0000000000a1", schemas: ["ProgrammListeneintrag", "ProgrammDetail"]),
            Case(path: "/api/v1/lager", schemas: ["LagerListe"], listKey: "lager", itemSchemas: ["Lager", "LagerListeneintrag"]),
            Case(path: "/api/v1/lager/\(camp)", schemas: ["Lager", "LagerDetail"]),
            Case(path: "/api/v1/lager/\(camp)/wetter", schemas: ["LagerWetter"]),
            Case(path: "/api/v1/lager/\(camp)/mitglieder", schemas: ["LagerMitgliederListe"], listKey: "mitglieder"),
            Case(path: "/api/v1/lager/\(camp)/vorlagen", schemas: ["LagerVorlagenListe"], listKey: "vorlagen"),
        ], as: "leitung.test")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }
}
