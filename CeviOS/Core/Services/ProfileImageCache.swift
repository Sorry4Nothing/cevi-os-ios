import Foundation
import UIKit

/// In-memory cache of profile images by `bildUrl`. Cleared on sign-out; never written to disk.
@MainActor
final class ProfileImageCache {
    static let shared = ProfileImageCache()
    private var images: [String: UIImage] = [:]

    subscript(path: String) -> UIImage? {
        get { images[path] }
        set { images[path] = newValue }
    }

    func removeAll() { images.removeAll() }
}
