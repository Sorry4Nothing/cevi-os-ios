import SwiftUI

/// Name with the answer as chip; stacks at accessibility sizes.
struct AnswerRow: View {
    let name: String
    let answer: OverviewAnswer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s2))
            : AnyLayout(HStackLayout(spacing: Spacing.s3))
        layout {
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
            AnswerChip(answer: answer)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .frame(minHeight: Size.touchTarget)
        .accessibilityElement(children: .combine)
    }
}
