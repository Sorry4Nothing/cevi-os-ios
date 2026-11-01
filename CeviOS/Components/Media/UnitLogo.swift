import SwiftUI

/// Logo of a unit without background or frame; the Cevi logo while loading or without own logo. Decorative: the unit
/// name next to it carries the information.
struct UnitLogo: View {
    @Environment(AppState.self) private var state
    let unitId: UUID?
    var size: CGFloat = Size.avatar
    @State private var image: CGImage?

    private var path: String? { unitId.flatMap { state.logoPath(unitId: $0) } }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Image(decorative: "CeviLogo").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task { await state.loadUnitsIfNeeded() }
        .task(id: path) {
            guard let path else { image = nil; return }
            image = await ProfileImageCache.shared.image(path: path, client: state.client)
        }
    }
}
