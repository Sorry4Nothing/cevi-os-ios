import Foundation
import WidgetKit

/// Fetches the data for the widgets with the existing services and hands the redacted snapshot to the app group.
/// The widget itself never touches the network. Without an app group (free development team) nothing happens.
@MainActor
final class WidgetRefresher {
    private let store: WidgetStore
    private let reload: () -> Void
    private var isRefreshing = false

    init(store: WidgetStore = .shared, reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reload = reload
    }

    /// Sign-out and end of session: delete all data, leave the marker «signed out», redraw the widgets.
    func clear() {
        guard store.isAvailable else { return }
        store.clear()
        reload()
    }

    /// Like `clear()`, but only when the file does not already say so (every cold start without session).
    func markSignedOutIfNeeded() {
        guard store.isAvailable, store.read()?.session != .signedOut else { return }
        clear()
    }

    /// One refresh at a time; a call during a refresh is dropped (the next trigger catches up).
    func refresh(client: APIClient?, profile: Profile?, hidesContent: Bool, now: Date = .now) async {
        guard store.isAvailable, !isRefreshing, let client, let profile else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previous = store.read().flatMap { $0.session == .signedIn ? $0 : nil }
        var network = false
        var other = false
        var succeeded = false
        func attempt<T>(_ operation: () async throws -> T) async -> T? {
            do {
                let value = try await operation()
                succeeded = true
                return value
            } catch let error as APIError {
                if error.kind == .network { network = true } else { other = true }
            } catch {
                other = true
            }
            return nil
        }

        let window = DateFormats.calendar
        let from = window.startOfDay(for: now)
        let to = window.date(byAdding: .month, value: ProgramListModel.windowMonths, to: from) ?? from
        let programs = await attempt { try await ProgramListModel.allPrograms(client: client, from: from, to: to) }
        var places: [UUID: String] = [:]
        if let programs {
            // The meeting point is only in the detail; one call per unit for its next program.
            for unit in WidgetSnapshotBuilder.units(programs: programs, profile: profile, now: now) {
                guard let id = unit.programs.first?.id, let detail = try? await client.calendarEvent(id: id),
                      let point = Program(detail: detail).meetingPoint else { continue }
                places[id] = point
            }
        }
        let camps = await attempt { try await client.camps() }
        let chats: [ChatSummary]? = (!profile.children.isEmpty || profile.isUnitLeader) ? await attempt { try await client.chats() } : []

        var campData: [WidgetCamp]?
        if let camps {
            campData = []
            for entry in camps.filter({ $0.camp.status == .active }).prefix(3) {
                let id = entry.id
                let today = try? await client.campToday(campId: id)
                let week = try? await client.campMyWeek(campId: id)
                let sections = (try? await client.campSchedule(campId: id))?.sections ?? []
                let tasks = (try? await client.campTasks(campId: id, filter: CampTaskFilter(personId: profile.id)))?.tasks
                campData?.append(WidgetSnapshotBuilder.camp(entry.camp, today: today, week: week, sections: sections, tasks: tasks, personId: profile.id, now: now))
            }
        }

        guard succeeded else {
            // Nothing could be read: keep the last data and say so, or admit the error when there is none.
            var kept = previous ?? WidgetSnapshot(session: .signedIn, updatedAt: now, status: .failed)
            if previous != nil { kept.status = network || !other ? .offline : kept.status }
            kept.hidesContent = hidesContent
            write(kept)
            return
        }
        var snapshot = WidgetSnapshot(session: .signedIn, updatedAt: now)
        snapshot.hidesContent = hidesContent
        snapshot.units = programs.map { WidgetSnapshotBuilder.units(programs: $0, profile: profile, now: now, places: places) } ?? previous?.units ?? []
        snapshot.events = programs.map { WidgetSnapshotBuilder.events(programs: $0, now: now) } ?? previous?.events ?? []
        snapshot.camps = campData ?? previous?.camps ?? []
        snapshot.chat = chats.map(WidgetSnapshotBuilder.chat) ?? previous?.chat
        // A part that failed keeps its old data; the stand line then shows the age of the whole file honestly as «offline».
        if network, previous != nil { snapshot.status = .offline; snapshot.updatedAt = previous?.updatedAt ?? now }
        write(snapshot)
    }

    private func write(_ snapshot: WidgetSnapshot) {
        store.write(snapshot)
        reload()
    }
}
