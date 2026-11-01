import SwiftUI

/// Proportional bar (yes, no, open) with the numbers as text below.
struct CountsBar: View {
    let counts: ParticipationCounts

    var body: some View {
        let total = counts.yes + counts.no + counts.open
        let summary = String(localized: "\(counts.yes) Ja, \(counts.no) Nein, \(counts.open) offen von \(total)")
        VStack(alignment: .leading, spacing: Spacing.s2) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    segment(counts.yes, of: total, width: proxy.size.width, color: .ceviOnSuccessContainer)
                    segment(counts.no, of: total, width: proxy.size.width, color: .ceviOnErrorContainer)
                    segment(counts.open, of: total, width: proxy.size.width, color: .ceviOutlineVariant)
                }
                .background(Color.ceviOutlineVariant)
                .clipShape(Capsule())
            }
            .frame(height: Spacing.s3)
            Text(summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private func segment(_ value: Int, of total: Int, width: CGFloat, color: Color) -> some View {
        color.frame(width: total > 0 ? width * CGFloat(value) / CGFloat(total) : 0)
    }
}
