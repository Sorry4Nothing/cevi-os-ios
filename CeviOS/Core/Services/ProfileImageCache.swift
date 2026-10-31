import Foundation
import CoreGraphics

/// In-memory cache of profile images by `bildUrl`. Cleared on sign-out; never written to disk.
@MainActor
final class ProfileImageCache {
    static let shared = ProfileImageCache()
    private var images: [String: CGImage] = [:]

    subscript(path: String) -> CGImage? {
        get { images[path] }
        set { images[path] = newValue }
    }

    func removeAll() { images.removeAll() }
}
