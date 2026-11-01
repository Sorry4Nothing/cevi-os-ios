import Foundation

/// The only image addresses the app loads: profile images and unit logos on its own server, optionally with `?v=`.
/// Anything else (other hosts, paths, traversal, extra query) is refused, so the session cookie never goes elsewhere.
nonisolated enum ImagePath {
    static let maxBytes = 512 * 1024

    static func isValid(_ path: String) -> Bool {
        path.wholeMatch(of: /\/api\/v1\/(?:personen\/[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\/bild|stufen\/[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\/logo)(?:\?v=[0-9a-fA-F]+)?/) != nil
    }
}
