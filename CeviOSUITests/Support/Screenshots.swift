import XCTest

extension Screen {
    /// Saves the screen as PNG for the comparison with the design boards (`/tmp/camp-shots`). The folder exists only on the
    /// development Mac; where it cannot be written the call does nothing.
    func snap(_ id: String) {
        let variant = AccessibilityAudit.variant(of: app).rawValue
        let directory = URL(fileURLWithPath: "/tmp/camp-shots")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: directory.appending(path: "\(variant)-\(id).png"))
    }
}
