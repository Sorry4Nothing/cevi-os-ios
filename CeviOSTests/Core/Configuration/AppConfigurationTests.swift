import Foundation
import Testing
@testable import CeviOS

struct AppConfigurationTests {
    @Test func acceptsValidHTTPSAddress() {
        let configuration = AppConfiguration(
            environment: .dev,
            infoDictionary: [AppConfiguration.baseURLKey: "https://api.example.org"]
        )
        #expect(configuration.apiBaseURL == URL(string: "https://api.example.org"))
        #expect(configuration.isComplete)
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(AppConfiguration.validBaseURL("  https://api.example.org \n") == URL(string: "https://api.example.org"))
    }

    @Test(arguments: [nil, "", "   ", "http://api.example.org", "api.example.org", "https://"] as [String?])
    func invalidAddressYieldsNoURL(text: String?) {
        #expect(AppConfiguration.validBaseURL(text) == nil)
    }

    @Test func missingKeyYieldsIncompleteConfiguration() {
        let configuration = AppConfiguration(environment: .prod, infoDictionary: [:])
        #expect(configuration.apiBaseURL == nil)
        #expect(!configuration.isComplete)
    }

    @Test func environmentMatchesScheme() {
        #if DEV
        #expect(AppConfiguration.current.environment == .dev)
        #elseif INT
        #expect(AppConfiguration.current.environment == .int)
        #else
        #expect(AppConfiguration.current.environment == .prod)
        #endif
    }
}
