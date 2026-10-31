import SwiftUI

struct SectionTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ceviOnSurfaceVariant)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}
