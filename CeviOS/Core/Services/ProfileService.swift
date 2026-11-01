import Foundation
import ImageIO
import UniformTypeIdentifiers

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
/// Uses ImageIO and CoreGraphics only.
nonisolated enum ProfileImage {
    static let maxSide = 1024
    static let maxBytes = 5 * 1024 * 1024

    /// Decodes image data (JPEG, PNG, HEIC, WebP …) applying the EXIF orientation.
    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide, // bounds the decoded size of server images
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Center square, scaled down to `maxSide`, as JPEG below `maxBytes`. `nil` if the data is no image.
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), 16_000),
        ]
        guard let full = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(full.width, full.height)
        let crop = CGRect(x: (full.width - side) / 2, y: (full.height - side) / 2, width: side, height: side)
        guard var square = full.cropping(to: crop) else { return nil }
        if side > maxSide, let scaled = scaled(square, to: maxSide) { square = scaled }
        for quality in stride(from: 0.85, through: 0.25, by: -0.15) {
            if let jpeg = encodeJPEG(square, quality: quality), jpeg.count < maxBytes { return jpeg }
        }
        return nil
    }

    private static func scaled(_ image: CGImage, to side: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
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
