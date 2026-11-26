import AppIntents
import SwiftUI
import WidgetKit

/// One moment of a widget. The model is resolved in the view: the redaction reason (locked device) is only known there.
struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var unitId: UUID?
    var campId: UUID?

    func model(_ kind: WidgetKind, privacy: Bool) -> WidgetModel {
        WidgetModel.resolve(kind: kind, snapshot: snapshot, now: date, privacyRedacted: privacy, unitId: unitId, campId: campId)
    }
}

/// Reads the snapshot of the app group. No network, no session: the widget knows nothing but this file.
enum WidgetTimeline {
    static func make(now: Date, unitId: UUID?, campId: UUID?, snapshot: WidgetSnapshot? = WidgetStore.shared.read()) -> Timeline<WidgetEntry> {
        var entries = [WidgetEntry(date: now, snapshot: snapshot, unitId: unitId, campId: campId)]
        // The stand line turns stale after two hours, whether or not the app has refreshed by then.
        if let updated = snapshot?.updatedAt {
            let stale = updated.addingTimeInterval(WidgetStand.staleAfter)
            if stale > now { entries.append(WidgetEntry(date: stale, snapshot: snapshot, unitId: unitId, campId: campId)) }
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }
}

/// Provider with a configuration (W1: unit, W3: camp).
struct SnapshotProvider<Intent: WidgetConfigurationIntent & SelectionIntent>: AppIntentTimelineProvider {
    let kind: WidgetKind

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: WidgetSamples.snapshot(updatedAt: .now))
    }

    func snapshot(for configuration: Intent, in context: Context) async -> WidgetEntry {
        if context.isPreview { return WidgetEntry(date: .now, snapshot: WidgetSamples.snapshot(updatedAt: .now)) }
        return WidgetTimeline.make(now: .now, unitId: configuration.unitId, campId: configuration.campId).entries[0]
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<WidgetEntry> {
        WidgetTimeline.make(now: .now, unitId: configuration.unitId, campId: configuration.campId)
    }
}

/// Provider without a configuration (W2, W4, W5, W6).
struct PlainProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: WidgetSamples.snapshot(updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WidgetTimeline.make(now: .now, unitId: nil, campId: nil).entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        completion(WidgetTimeline.make(now: .now, unitId: nil, campId: nil))
    }
}
