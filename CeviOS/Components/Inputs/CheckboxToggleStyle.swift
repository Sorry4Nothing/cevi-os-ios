import SwiftUI

/// Round checkbox (consent). VoiceOver sees a regular toggle.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(configuration.isOn ? Color.ceviSecondary : Color.ceviOutline)
                configuration.label
                    .font(.body)
                    .foregroundStyle(Color.ceviOnSurface)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: Size.touchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
