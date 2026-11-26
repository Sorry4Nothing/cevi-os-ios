import SwiftUI
import WidgetKit

/// Shared parts of all widgets: header, stand line, chips, notes. Colours are the app's `cevi-…` sets.
struct WidgetHeader: View {
    let title: String
    let symbol: String
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(mode == .fullColor ? Color.white : Color.primary)
                .frame(width: 16, height: 16)
                .background(mode == .fullColor ? Color.ceviPrimary : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .widgetAccentable()
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .lineLimit(2)
        }
        .accessibilityHidden(true)
    }
}

struct StandLine: View {
    let stand: WidgetStand

    var body: some View {
        if stand.isStale || stand.isOffline {
            Label(stand.text, systemImage: stand.isOffline ? "wifi.slash" : "clock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.ceviOnWarningContainer)
        } else {
            Text(stand.text).font(.caption2).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
    }
}

struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.ceviOnStufeContainer)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.ceviStufeContainer, in: Capsule())
            .lineLimit(1)
    }
}

/// A line with a symbol and a text, for the notes of the states.
struct WidgetNote: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(Color.ceviOnSurface)
    }
}

extension View {
    /// The widget background of the app (`cevi-surface-container-low`, tinted and clear modes by the system).
    func ceviWidgetBackground() -> some View {
        containerBackground(Color.ceviSurfaceContainerLow, for: .widget)
    }
}
