import Foundation

/// How a person is named. Chats use the Cevi name, lists with room show both. Children have no Cevi name.
nonisolated enum PersonName {
    /// Cevi name, or the full name without one.
    static func short(name: String, ceviName: String?) -> String {
        Self.ceviName(ceviName) ?? name
    }

    /// Cevi name as title with the full name below; without a Cevi name only the full name.
    static func titled(name: String, ceviName: String?) -> (title: String, subtitle: String?) {
        Self.ceviName(ceviName).map { ($0, name) } ?? (name, nil)
    }

    /// The Cevi name if there is a non-empty one.
    static func ceviName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
