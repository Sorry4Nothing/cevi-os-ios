import Foundation

/// Sending offline changes and the event stream of a camp. Reading the feed: `campChanges` in `CampService`.
extension APIClient {
    /// Sends 1 to 100 operations, in order, each in its own transaction. 200 even if single operations are `abgelehnt` or
    /// `konflikt`. 409 `LAGER_GESCHLOSSEN` rejects the whole request; 413 above 256 KB; 5xx: send the same request again.
    func sendCampOperations(campId: UUID, _ operations: [CampOperation]) async throws -> CampOperationResponse {
        try await load("POST", campPath(campId) + "/aenderungen", body: CampOperationBatch(operations: operations))
    }

    /// The event stream of an open view, in the foreground only. Ends after `.end` or when the server closes the
    /// connection; the caller then connects again with `lastEventId` = the last `upTo` it saw and asks the feed from there.
    /// Throws an `APIError` (401, 404, 429 `ZU_VIELE_VERBINDUNGEN` with `retryAfter`) before the first message.
    /// Cancelling the consuming task closes the connection.
    nonisolated func campEvents(campId: UUID, lastEventId: Int? = nil) -> AsyncThrowingStream<CampLiveEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let headers = lastEventId.map { ["Last-Event-ID": String($0)] } ?? [:]
                    let bytes = try await openStream("/api/v1/lager/\(campId.uuidString.lowercased())/ereignisse", headers: headers)
                    var parser = CampEventParser()
                    var chunk: [UInt8] = []
                    for try await byte in bytes {
                        chunk.append(byte)
                        // Hand over at each line end, so a message is not held back by the next byte.
                        guard byte == 0x0A else { continue }
                        for raw in parser.consume(chunk) {
                            guard let event = CampLiveEvent(raw) else { continue }
                            continuation.yield(event)
                            if event == .end { continuation.finish(); return }
                        }
                        chunk.removeAll(keepingCapacity: true)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: APIError.network)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
