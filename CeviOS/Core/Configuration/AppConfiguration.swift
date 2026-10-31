import Foundation
import SwiftUI

/// Configuration of the running environment. The values come from the build configuration (`Config/*.xcconfig`), never from code.
struct AppConfiguration: Equatable, Sendable {
    enum AppEnvironment: String, Sendable {
        case dev = "Dev"
        case int = "Int"
        case prod = "Prod"
    }

    /// Key in the Info.plist, filled from `API_BASE_URL` of the xcconfig.
    static let baseURLKey = "APIBaseURL"

    let environment: AppEnvironment
    /// Base URL of the API. `nil` if it is missing or invalid (only `https` is allowed).
    let apiBaseURL: URL?

    /// Link to the app in the App Store for the notice «Bitte die App aktualisieren». `nil` until it is entered.
    let appStoreURL: URL?

    init(environment: AppEnvironment, infoDictionary: [String: Any]) {
        self.environment = environment
        apiBaseURL = Self.validBaseURL(infoDictionary[Self.baseURLKey] as? String)
        appStoreURL = Self.validBaseURL(infoDictionary["AppStoreURL"] as? String)
    }

    var isComplete: Bool {
        apiBaseURL != nil
    }

    static func validBaseURL(_ text: String?) -> URL? {
        guard
            let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            let url = URL(string: text),
            url.scheme == "https",
            url.host() != nil
        else {
            return nil
        }
        return url
    }

    /// Configuration of the running app. The environment is determined by the compiler flag of the scheme (`DEV`, `INT`, otherwise `PROD`).
    static let current = AppConfiguration(
        environment: runningEnvironment,
        infoDictionary: Bundle.main.infoDictionary ?? [:]
    )

    private static var runningEnvironment: AppEnvironment {
        #if DEV
        return .dev
        #elseif INT
        return .int
        #else
        return .prod
        #endif
    }
}

extension EnvironmentValues {
    @Entry var appConfiguration = AppConfiguration.current
}
