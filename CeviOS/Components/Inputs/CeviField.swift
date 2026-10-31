import SwiftUI

/// Label above a bordered text field. The field itself carries the accessibility label.
struct CeviField<Field: View>: View {
    let label: LocalizedStringKey
    var isFocused = false
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .accessibilityHidden(true)
            field
                .font(.body)
                .foregroundStyle(Color.ceviOnSurface)
                .padding(.leading, Spacing.s4)
                .padding(.trailing, Spacing.s1)
                .frame(maxWidth: .infinity, minHeight: Size.field, alignment: .leading)
                .background(Color.ceviSurface, in: Radius.shape(Radius.sm))
                .overlay {
                    Radius.shape(Radius.sm).strokeBorder(
                        isFocused ? Color.ceviFocus : Color.ceviOutline,
                        lineWidth: isFocused ? Size.focusBorder : Size.border
                    )
                }
        }
    }
}

#Preview("Bausteine") {
    @Previewable @State var text = "m.keller"
    @Previewable @State var password = "sternennacht"
    @Previewable @State var accepted = true
    @Previewable @FocusState var focused: Bool
    VStack(spacing: Spacing.s4) {
        Eyebrow("Cevi Stäfa-Hombrechtikon")
        CeviField(label: "Benutzername") { TextField("", text: $text) }
        CeviField(label: "Passwort", isFocused: true) {
            PasswordField(label: "Passwort", text: $password, isFocused: $focused)
        }
        Toggle("Ich habe die Datenschutzerklärung gelesen und bin einverstanden.", isOn: $accepted)
            .toggleStyle(CheckboxToggleStyle())
        Button("Anmelden") {}.buttonStyle(.ceviPrimary)
        Button("Anmelden") {}.buttonStyle(.ceviPrimary).disabled(true)
        Button("Abbrechen") {}.buttonStyle(.ceviText)
    }
    .padding(Spacing.s4)
    .ceviScreenBackground()
}
