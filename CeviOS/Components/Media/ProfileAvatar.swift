import SwiftUI

/// Round profile image or initials. Decorative: the name next to it carries the information.
struct ProfileAvatar: View {
    @Environment(AppState.self) private var state
    let path: String?
    let initials: String
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.headline)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Color.ceviOnPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ceviPrimary)
            }
        }
        .frame(width: Size.avatar, height: Size.avatar)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path else { image = nil; return }
        image = await ProfileImageCache.shared.image(path: path, client: state.client)
    }
}
