import Foundation
import CoreGraphics

/// In-memory cache of server images (profile images and unit logos) by path. Cleared on sign-out and lock; never
/// written to disk.
@MainActor
final class ProfileImageCache {
    static let shared = ProfileImageCache()
    private var images: [String: CGImage] = [:]

    subscript(path: String) -> CGImage? {
        get { images[path] }
        set { images[path] = newValue }
    }

    func removeAll() { images.removeAll() }

    /// Cached image or a fresh download. `nil` on any error (404, invalid path, too large, no image).
    func image(path: String, client: APIClient?) async -> CGImage? {
        if let cached = images[path] { return cached }
        guard let data = try? await client?.image(path: path), let loaded = ProfileImage.cgImage(from: data) else { return nil }
        images[path] = loaded
        return loaded
    }
}
