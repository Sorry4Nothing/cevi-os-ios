import Testing
@testable import CeviOS

struct PersonNameTests {
    @Test func shortPrefersCeviName() {
        #expect(PersonName.short(name: "Lea Beispiel", ceviName: "Wolke") == "Wolke")
        #expect(PersonName.short(name: "Lea Beispiel", ceviName: nil) == "Lea Beispiel")
        #expect(PersonName.short(name: "Lea Beispiel", ceviName: "  ") == "Lea Beispiel")
    }

    @Test func titledShowsBoth() {
        let both = PersonName.titled(name: "Lea Beispiel", ceviName: "Wolke")
        #expect(both.title == "Wolke" && both.subtitle == "Lea Beispiel")
        let only = PersonName.titled(name: "Lea Beispiel", ceviName: nil)
        #expect(only.title == "Lea Beispiel" && only.subtitle == nil)
    }
}
