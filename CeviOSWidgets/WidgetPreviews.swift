#if DEBUG
import SwiftUI
import WidgetKit

/// Entries for all states of the boards (N, E, I, U, F, V, O, R). Invented data only.
private enum PreviewEntries {
    static func entries(_ kind: WidgetKind) -> [WidgetEntry] {
        let now = WidgetSamples.now
        let normal = WidgetSamples.snapshot()
        var empty = normal
        empty.units = []
        empty.events = []
        empty.chat = WidgetChat(unread: 0, chats: 0)
        empty.camps = normal.camps.map { WidgetCamp(id: $0.id, title: $0.title, from: $0.from, to: $0.to, duty: nil, important: [], todosOpen: 0, todosTotal: 0, overdueCount: 0, tasks: [], laterCount: nil, doneThisWeek: nil) }
        var noCamp = normal
        noCamp.camps = []
        var offline = normal
        offline.status = .offline
        var failed = normal
        failed.status = .failed
        var locked = normal
        locked.hidesContent = true
        var list: [(WidgetSnapshot?, Date)] = [
            (normal, now), (nil, now), (.signedOut(), now), (failed, now), (empty, now),
            (normal, now.addingTimeInterval(2 * 3600)), (offline, now), (locked, now),
        ]
        if kind != .nextProgram, kind != .calendar, kind != .chat { list.append((noCamp, now)) }
        return list.map { WidgetEntry(date: $1, snapshot: $0, unitId: nil, campId: nil) }
    }
}

#Preview("W1 small", as: .systemSmall) { NextProgramWidget() } timeline: { for entry in PreviewEntries.entries(.nextProgram) { entry } }
#Preview("W1 medium", as: .systemMedium) { NextProgramWidget() } timeline: { for entry in PreviewEntries.entries(.nextProgram) { entry } }
#Preview("W1 large", as: .systemLarge) { NextProgramWidget() } timeline: { for entry in PreviewEntries.entries(.nextProgram) { entry } }
#Preview("W1 rectangular", as: .accessoryRectangular) { NextProgramWidget() } timeline: { for entry in PreviewEntries.entries(.nextProgram) { entry } }
#Preview("W1 inline", as: .accessoryInline) { NextProgramWidget() } timeline: { for entry in PreviewEntries.entries(.nextProgram) { entry } }
#Preview("W2 small", as: .systemSmall) { CalendarWidget() } timeline: { for entry in PreviewEntries.entries(.calendar) { entry } }
#Preview("W2 medium", as: .systemMedium) { CalendarWidget() } timeline: { for entry in PreviewEntries.entries(.calendar) { entry } }
#Preview("W2 large", as: .systemLarge) { CalendarWidget() } timeline: { for entry in PreviewEntries.entries(.calendar) { entry } }
#Preview("W2 rectangular", as: .accessoryRectangular) { CalendarWidget() } timeline: { for entry in PreviewEntries.entries(.calendar) { entry } }
#Preview("W3 small", as: .systemSmall) { CampTodayWidget() } timeline: { for entry in PreviewEntries.entries(.campToday) { entry } }
#Preview("W3 medium", as: .systemMedium) { CampTodayWidget() } timeline: { for entry in PreviewEntries.entries(.campToday) { entry } }
#Preview("W3 large", as: .systemLarge) { CampTodayWidget() } timeline: { for entry in PreviewEntries.entries(.campToday) { entry } }
#Preview("W3 circular", as: .accessoryCircular) { CampTodayWidget() } timeline: { for entry in PreviewEntries.entries(.campToday) { entry } }
#Preview("W3 rectangular", as: .accessoryRectangular) { CampTodayWidget() } timeline: { for entry in PreviewEntries.entries(.campToday) { entry } }
#Preview("W3 inline", as: .accessoryInline) { CampTodayWidget() } timeline: { for entry in PreviewEntries.entries(.campToday) { entry } }
#Preview("W4 small", as: .systemSmall) { TasksWidget() } timeline: { for entry in PreviewEntries.entries(.tasks) { entry } }
#Preview("W4 medium", as: .systemMedium) { TasksWidget() } timeline: { for entry in PreviewEntries.entries(.tasks) { entry } }
#Preview("W4 large", as: .systemLarge) { TasksWidget() } timeline: { for entry in PreviewEntries.entries(.tasks) { entry } }
#Preview("W4 circular", as: .accessoryCircular) { TasksWidget() } timeline: { for entry in PreviewEntries.entries(.tasks) { entry } }
#Preview("W4 rectangular", as: .accessoryRectangular) { TasksWidget() } timeline: { for entry in PreviewEntries.entries(.tasks) { entry } }
#Preview("W5 small", as: .systemSmall) { EmergencyWidget() } timeline: { for entry in PreviewEntries.entries(.emergency) { entry } }
#Preview("W5 medium", as: .systemMedium) { EmergencyWidget() } timeline: { for entry in PreviewEntries.entries(.emergency) { entry } }
#Preview("W5 circular", as: .accessoryCircular) { EmergencyWidget() } timeline: { for entry in PreviewEntries.entries(.emergency) { entry } }
#Preview("W6 small", as: .systemSmall) { ChatWidget() } timeline: { for entry in PreviewEntries.entries(.chat) { entry } }
#Preview("W6 medium", as: .systemMedium) { ChatWidget() } timeline: { for entry in PreviewEntries.entries(.chat) { entry } }
#Preview("W6 circular", as: .accessoryCircular) { ChatWidget() } timeline: { for entry in PreviewEntries.entries(.chat) { entry } }
#Preview("W6 inline", as: .accessoryInline) { ChatWidget() } timeline: { for entry in PreviewEntries.entries(.chat) { entry } }
#endif
