import Foundation
import Testing
@testable import CeviOS

private nonisolated let reqId = "0190a000-0000-7000-8000-0000000a0001"
private nonisolated let reqId2 = "0190a000-0000-7000-8000-0000000a0002"

private nonisolated func requestJSON(_ id: String, room: String = "Pfadiheim") -> String {
    """
    {"id":"\(id)","raumId":"0190a000-0000-7000-8000-0000000b0001","raumName":"\(room)","beginn":"2027-03-06T13:00:00Z","ende":"2027-03-06T16:00:00Z",
     "zweck":"Sitzung","status":"angefragt","begruendung":null,"entschiedenAm":null,"erstelltAm":"2027-03-01T08:00:00Z","vonName":"Lea Beispiel"}
    """
}
private nonisolated func page(_ ids: String...) -> String { #"{"anfragen":[\#(ids.map { requestJSON($0) }.joined(separator: ","))],"weitere":false,"naechste":null}"# }
private nonisolated func newHost() -> String { "r\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }
private nonisolated func client(_ host: String) -> APIClient {
    APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
              session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
}
/// Lists the given requests and answers every decision with `(status, body)`.
private nonisolated func serve(_ host: String, ids: [String] = [reqId, reqId2], decision: @escaping @Sendable () -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        if request.httpMethod == "GET" { return (200, [:], Data(page(ids.first ?? reqId, ids.last ?? reqId2).utf8)) }
        let (status, body) = decision()
        return (status, [:], Data(body.utf8))
    }
}
private nonisolated func error(_ status: Int, _ code: String? = nil) -> APIError {
    APIError.from(status: status, data: Data((code.map { #"{"code":"\#($0)","message":"Servertext"}"# } ?? "{}").utf8))
}

@MainActor
struct RoomDecisionsTests {
    private func loaded(_ host: String) async -> (RoomDecisionsModel, APIClient, RoomRequest, RoomRequest) {
        let api = client(host)
        let model = RoomDecisionsModel()
        await model.load(client: api)
        return (model, api, model.requests[0], model.requests[1])
    }

    @Test func loadsTheOpenRequestsAndTheProfileRowFollowsThem() async {
        let host = newHost()
        serve(host) { (200, "{}") }
        let (model, _, first, _) = await loaded(host)
        #expect(model.phase == .loaded && model.requests.count == 2 && model.hasOpen && first.requesterName == "Lea Beispiel")
        let get = StubProtocol.requests(host: host).first
        #expect(get?.url?.path == "/api/v1/raeume/anfragen/offen")
        StubProtocol.register(host: host) { _ in (200, [:], Data(#"{"anfragen":[],"weitere":false,"naechste":null}"#.utf8)) }
        await model.load(client: client(host))
        #expect(!model.hasOpen && model.phase == .loaded)
        let offline = RoomDecisionsModel()
        await offline.load(client: client(newHost()))
        #expect(offline.phase == .failed(text: APIError.network.displayText, isOffline: true) && !offline.hasOpen)
    }

    @Test func acceptingSendsTheDecisionAndRemovesTheRequest() async throws {
        let host = newHost()
        serve(host) { (200, #"{"id":"\#(reqId)","status":"bestaetigt"}"#) }
        let (model, api, first, _) = await loaded(host)
        await model.accept(first, client: api)
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(post.url?.path == "/api/v1/raeume/anfragen/\(reqId)/entscheid")
        #expect(String(decoding: StubProtocol.body(of: post) ?? Data(), as: UTF8.self) == #"{"entscheid":"annehmen"}"#)
        #expect(model.requests.map { $0.id.uuidString.lowercased() } == [reqId2] && model.notice == "Pfadiheim bestätigt.")
    }

    @Test func decliningNeedsAReasonAndSendsIt() async throws {
        let host = newHost()
        serve(host) { (200, #"{"id":"\#(reqId)","status":"abgelehnt"}"#) }
        let (model, api, first, _) = await loaded(host)
        #expect(await model.decline(first, reason: "  ", client: api) == false && model.rowErrors[first.id] != nil)
        #expect(await model.decline(first, reason: String(repeating: "a", count: 501), client: api) == false)
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
        #expect(await model.decline(first, reason: " Raum besetzt ", client: api) == true)
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        let body = String(decoding: StubProtocol.body(of: post) ?? Data(), as: UTF8.self)
        #expect(body.contains(#""entscheid":"ablehnen""#) && body.contains(#""begruendung":"Raum besetzt""#) && model.notice == "Pfadiheim abgelehnt.")
    }

    @Test func aTakenRoomLeavesOnlyDeclining() async {
        let host = newHost()
        serve(host) { (409, #"{"code":"RAUM_BELEGT","message":"x"}"#) }
        let (model, api, first, _) = await loaded(host)
        await model.accept(first, client: api)
        #expect(model.bookedIds == [first.id] && model.rowErrors[first.id]?.contains("nur ablehnen") == true && model.retryable.isEmpty && model.requests.count == 2)
        await model.accept(first, client: api)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }.count == 1)
    }

    @Test func aDecidedRequestLeavesTheList() async {
        let host = newHost()
        serve(host) { (409, #"{"code":"STATUS_UNGUELTIG","message":"x"}"#) }
        let (model, api, first, _) = await loaded(host)
        #expect(await model.decline(first, reason: "Grund", client: api) == true)
        #expect(model.requests.count == 1 && model.notice?.contains("schon entschieden") == true)
    }

    @Test func failuresGetTheirOwnTexts() {
        #expect(RoomDecisionsModel.failure(for: error(404)) == .removed("Diese Anfrage gibt es nicht mehr."))
        #expect(RoomDecisionsModel.failure(for: error(403)) == .removed("Du darfst über diese Anfrage nicht entscheiden."))
        #expect(RoomDecisionsModel.failure(for: error(403, "EIGENE_ANFRAGE")) == .kept("Über deine eigene Anfrage entscheidest du nicht.", bookedOnly: false, retry: false))
        #expect(RoomDecisionsModel.failure(for: .network) == .kept(APIError.network.displayText, bookedOnly: false, retry: true))
        #expect(RoomDecisionsModel.failure(for: error(400, "UNGUELTIGE_EINGABE")) == .kept("Servertext", bookedOnly: false, retry: false))
    }

    @Test func aFailedDecisionIsNotRepeatedUntilThePersonTaps() async {
        let host = newHost()
        serve(host) { (500, #"{"code":"FEHLER","message":"Fehler"}"#) }
        let (model, api, first, _) = await loaded(host)
        await model.accept(first, client: api)
        #expect(model.rowErrors[first.id] == "Fehler" && model.retryable[first.id] == .accept && model.requests.count == 2)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }.count == 1)
        serve(host) { (200, #"{"id":"\#(reqId)","status":"bestaetigt"}"#) }
        await model.retry(first, client: api)
        #expect(model.requests.count == 1 && model.retryable.isEmpty && StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }.count == 2)
    }
}
