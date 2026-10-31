import SwiftUI

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
