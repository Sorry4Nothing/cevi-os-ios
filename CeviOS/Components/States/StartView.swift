import SwiftUI

/// ZT1: launch while the session is checked.
struct StartView: View {
    var body: some View {
        FillingScrollView {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Spacer(minLength: 0)
                Eyebrow("Cevi Stäfa-Hombrechtikon")
                Text("Cevi OS")
                    .font(.title(.display))
                    .foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Spacing.s3) {
                    ProgressView()
                    Text("Wird geladen …")
                        .font(.subheadline)
                        .foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                .padding(.top, Spacing.s5)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s6)
            .padding(.bottom, Spacing.s8)
        }
        .ceviScreenBackground()
    }
}

#Preview("Start") { StartView() }
