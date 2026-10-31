import Foundation
import UIKit

/// Body of `PATCH /api/v1/ich`: only the changed keys are sent. `phone == .some(nil)` sends `null` and removes the number.
nonisolated struct ProfilePatch: Encodable, Sendable {
    var pushChat: Bool?
    var pushPrograms: Bool?
    var pushRegistrations: Bool?
    var phone: String??

    enum CodingKeys: String, CodingKey {
        case pushChat
        case pushPrograms = "pushProgramme"
        case pushRegistrations = "pushAnmeldungen"
        case phone = "telefon"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(pushChat, forKey: .pushChat)
        try container.encodeIfPresent(pushPrograms, forKey: .pushPrograms)
        try container.encodeIfPresent(pushRegistrations, forKey: .pushRegistrations)
        if let phone { try container.encode(phone, forKey: .phone) }
    }
}

/// Phone number of a unit leader, checked like the server does (`^\+?\d[\d ()/.-]{4,28}\d$` after trim).
nonisolated enum PhoneInput: Equatable {
    /// Empty input: the number is removed.
    case remove
    case number(String)
    case invalid

    init(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            self = .remove
        } else if value.wholeMatch(of: /\+?\d[\d ()\/.\-]{4,28}\d/) != nil {
            self = .number(value)
        } else {
            self = .invalid
        }
    }
}

/// Prepares a picked photo for `PUT /api/v1/ich/bild`: center square, at most 1024 px, JPEG under 5 MiB.
nonisolated enum ProfileImage {
    static let maxSide: CGFloat = 1024
    static let maxBytes = 5 * 1024 * 1024

    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0 else { return nil }
        let target = min(side, maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let scale = target / side
        let square = renderer.image { _ in
            // Drawing centered and scaled crops the longer side evenly.
            image.draw(in: CGRect(
                x: (target - size.width * scale) / 2,
                y: (target - size.height * scale) / 2,
                width: size.width * scale,
                height: size.height * scale
            ))
        }
        for quality in stride(from: 0.85, through: 0.25, by: -0.15) {
            if let data = square.jpegData(compressionQuality: quality), data.count < maxBytes { return data }
        }
        return nil
    }
}

extension APIClient {
    func updateProfile(_ patch: ProfilePatch) async throws {
        try await send("PATCH", "/api/v1/ich", body: patch)
    }

    func uploadProfileImage(_ jpeg: Data) async throws {
        try await send("PUT", "/api/v1/ich/bild", rawBody: jpeg)
    }

    func deleteProfileImage() async throws {
        try await send("DELETE", "/api/v1/ich/bild")
    }
}
