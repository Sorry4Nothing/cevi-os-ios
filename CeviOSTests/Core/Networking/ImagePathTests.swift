import Testing
@testable import CeviOS

struct ImagePathTests {
    private let uuid = "0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b"

    @Test func acceptsProfileImagesAndLogos() {
        #expect(ImagePath.isValid("/api/v1/personen/\(uuid)/bild"))
        #expect(ImagePath.isValid("/api/v1/personen/\(uuid)/bild?v=1730000000"))
        #expect(ImagePath.isValid("/api/v1/stufen/\(uuid)/logo"))
        #expect(ImagePath.isValid("/api/v1/stufen/\(uuid)/logo?v=a1b2c3"))
    }

    @Test(arguments: [
        "https://evil.example/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild",
        "//evil.example/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild",
        "/api/v1/ich",
        "/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/logo",
        "/api/v1/stufen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild",
        "/api/v1/personen/../ich/bild",
        "/api/v1/stufen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/logo/../../x",
        "/api/v1/personen/%2e%2e/bild",
        "/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild?v=1&x=2",
        "/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild?v=",
        "/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild?x=1",
        "/api/v1/personen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/bild#x",
        "api/v1/stufen/0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b/logo",
        "",
    ])
    func rejectsEverythingElse(_ path: String) {
        #expect(!ImagePath.isValid(path))
    }
}
