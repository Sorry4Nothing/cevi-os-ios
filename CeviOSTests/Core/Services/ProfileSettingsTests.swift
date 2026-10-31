import Foundation
import Testing
import UIKit
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

    @MainActor @Test func imageIsCroppedScaledAndSmall() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let data = try #require(ProfileImage.jpeg(from: source))
        let result = try #require(UIImage(data: data))
        #expect(result.size == CGSize(width: 1024, height: 1024))
        #expect(data.count < ProfileImage.maxBytes)
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }
}
