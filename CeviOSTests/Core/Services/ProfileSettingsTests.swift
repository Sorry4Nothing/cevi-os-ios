import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CeviOS

struct ProfileSettingsTests {
    @Test func phoneInputFollowsServerRule() {
        #expect(PhoneInput("  ") == .remove)
        #expect(PhoneInput(" +41 79 123 45 67 ") == .number("+41 79 123 45 67"))
        #expect(PhoneInput("044/123.45-67") == .number("044/123.45-67"))
        #expect(PhoneInput("(044) 123 45 67") == .invalid) // must start with a digit
        #expect(PhoneInput("12345") == .invalid)
        #expect(PhoneInput("123456") == .number("123456"))
        #expect(PhoneInput(String(repeating: "1", count: 30)) == .number(String(repeating: "1", count: 30)))
        #expect(PhoneInput(String(repeating: "1", count: 31)) == .invalid)
        #expect(PhoneInput("079 123 45 6x") == .invalid)
    }

    @Test func patchSendsOnlyChangedKeys() throws {
        let toggle = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfilePatch(pushPrograms: false)))
        #expect((toggle as? [String: Bool]) == ["pushProgramme": false])
        let remove = String(decoding: try JSONEncoder().encode(ProfilePatch(phone: .some(nil))), as: UTF8.self)
        #expect(remove == #"{"telefon":null}"#)
    }

    @Test func imageIsCroppedScaledAndSmall() throws {
        // A 3000 x 2000 red picture as PNG data, made with CoreGraphics only.
        let context = try #require(CGContext(
            data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let data = try #require(ProfileImage.jpeg(from: png as Data))
        let result = try #require(ProfileImage.cgImage(from: data))
        #expect(result.width == 1024 && result.height == 1024)
        #expect(data.count < ProfileImage.maxBytes)
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        #expect(ProfileImage.jpeg(from: Data("kein Bild".utf8)) == nil)
    }
}
