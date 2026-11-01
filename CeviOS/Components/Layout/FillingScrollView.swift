import SwiftUI

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
