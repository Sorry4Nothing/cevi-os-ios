import SwiftUI

/// Round profile image or initials. Decorative: the name next to it carries the information.
struct ProfileAvatar: View {
    @Environment(AppState.self) private var state
    let path: String?
    let initials: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
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
        if let cached = ProfileImageCache.shared[path] { image = cached; return }
        guard let data = try? await state.client?.data(path: path), let loaded = UIImage(data: data) else { return }
        ProfileImageCache.shared[path] = loaded
        image = loaded
    }
}
