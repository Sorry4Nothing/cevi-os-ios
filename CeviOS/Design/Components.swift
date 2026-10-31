import SwiftUI

/// The one main action of a screen: Cevi-Rot capsule, at least `Size.button` high.
struct CeviPrimaryButtonStyle: ButtonStyle {
    /// Full width (forms) or as wide as the label (state screens).
    var expands = true
    @Environment(\.isEnabled) private var isEnabled

    private static let pressedOpacity = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            // Disabled: muted surface instead of a faded red, so the text keeps its contrast.
            .foregroundStyle(isEnabled ? Color.ceviOnPrimary : Color.ceviOnSurfaceVariant)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: Size.button)
            .background(isEnabled ? Color.ceviPrimary : Color.ceviSurfaceContainerHigh, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == CeviPrimaryButtonStyle {
    static var ceviPrimary: CeviPrimaryButtonStyle { CeviPrimaryButtonStyle() }
}

/// Quiet text action in accent blue (e.g. «Abbrechen», «Zu den Programmen»).
struct CeviTextButtonStyle: ButtonStyle {
    var color: Color = .ceviAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.s3)
            .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == CeviTextButtonStyle {
    static var ceviText: CeviTextButtonStyle { CeviTextButtonStyle() }
}

/// Small uppercase line above a display title. Only on Login, Willkommen and Start.
struct Eyebrow: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.ceviAccent)
            // VoiceOver reads the normal spelling, not single capitals.
            .accessibilityLabel(Text(text))
    }
}

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

/// Password input with a button to show or hide the text.
struct PasswordField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var contentType: UITextContentType = .password
    var isFocused: FocusState<Bool>.Binding
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isRevealed {
                    TextField("", text: $text)
                } else {
                    SecureField("", text: $text)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused(isFocused)
            .frame(minHeight: Size.touchTarget)
            .accessibilityLabel(Text(label))
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.ceviOnSurfaceVariant)
            .accessibilityLabel(isRevealed ? Text("Passwort verbergen") : Text("Passwort anzeigen"))
        }
    }
}

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

/// Scroll view whose content fills at least the visible height, so short content can sit at the bottom or center
/// and long content (large text sizes) still scrolls.
struct FillingScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
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
