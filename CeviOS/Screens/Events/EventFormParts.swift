import SwiftUI

/// Date, from and to of a form (K1, K2). Swiss time and German wording, whatever the device region is.
struct DateTimeFields: View {
    @Binding var date: Date
    @Binding var start: Date
    @Binding var end: Date
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s3))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Spacing.s3))
        layout {
            CeviField(label: "Datum") {
                DatePicker("Datum", selection: $date, displayedComponents: .date).labelsHidden()
            }
            CeviField(label: "von") {
                DatePicker("von", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
            }
            CeviField(label: "bis") {
                DatePicker("bis", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
            }
        }
        .environment(\.locale, Locale(identifier: "de_CH"))
        .environment(\.timeZone, DateFormats.timeZone)
        .environment(\.calendar, DateFormats.calendar)
    }
}

/// A group the person can pick or not: the check mark and the selected trait carry the state, not the color.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s1) {
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(title)
            }
            .font(isSelected ? .body.weight(.bold) : .body.weight(.medium))
            .foregroundStyle(isSelected ? Color.ceviOnPrimary : Color.ceviOnSurface)
            .padding(.horizontal, Spacing.s4)
            .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
            .background(isSelected ? Color.ceviSwitchOn : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(isSelected ? Color.ceviSwitchOn : Color.ceviOutline, lineWidth: Size.border) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Label above a group of controls (not a text field).
struct FieldLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Color.ceviOnSurfaceVariant)
    }
}

/// Full-screen state for a failed load: «Keine Verbindung» without a network, otherwise the general error.
struct LoadFailureView: View {
    let error: String?
    let isOffline: Bool
    let retry: () -> Void

    var body: some View {
        if isOffline { StateView.offline(retry: retry) } else { StateView.failure(retry: retry) }
    }
}

/// Day and time range for summaries: «Samstag, 6. März 2027, 19:30–21:00».
nonisolated enum EventFormat {
    static func range(start: Date, end: Date) -> String {
        let day = start.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone))
        return "\(day), \(ProgramFormat.clock(start))–\(ProgramFormat.clock(end))"
    }

    /// The date of `day` with the time of `time`, in Swiss time.
    static func combine(day: Date, time: Date) -> Date {
        let calendar = DateFormats.calendar
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }
}

/// Bordered text field whose whole box focuses it (the field carries the accessibility label).
struct EventTextField: View {
    let label: LocalizedStringKey
    let accessibility: String
    @Binding var text: String
    var multiline = false
    @FocusState private var isFocused: Bool

    var body: some View {
        CeviField(label: label, focus: $isFocused) {
            TextField("", text: $text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...8 : 1...1)
                .padding(.vertical, multiline ? Spacing.s3 : 0)
                .focused($isFocused)
                .accessibilityLabel(Text(accessibility))
        }
    }
}
