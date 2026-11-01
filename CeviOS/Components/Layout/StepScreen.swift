import SwiftUI

/// Layout of the sign-in steps after the password (T02): title, content, main action at the bottom.
/// At accessibility text sizes the actions scroll with the content so they never cover it.
struct StepScreen<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title)
                        .font(.title(.title1))
                        .foregroundStyle(Color.ceviOnSurface)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                }
                content
                if typeSize.isAccessibilitySize { actionStack }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s8)
            .padding(.bottom, Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize {
                actionStack
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s3)
                    .frame(maxWidth: Size.contentMax)
                    .frame(maxWidth: .infinity)
                    .background(Color.ceviSurface)
            }
        }
        .ceviScreenBackground()
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.s1) { actions }
    }
}
