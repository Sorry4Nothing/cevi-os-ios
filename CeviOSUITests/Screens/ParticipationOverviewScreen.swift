import XCTest

/// Who said yes, no or nothing yet (leaders).
struct ParticipationOverviewScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Anmeldungen"] }

    /// The bar is backed by the numbers in words.
    func assertCounts(yes: Int, no: Int, open: Int) {
        assertShows("\(yes) Ja, \(no) Nein, \(open) offen von \(yes + no + open)")
    }

    /// A row reads «Name, Ja|Nein|Offen».
    func assertRow(_ name: String, answer: String) {
        let row = scrollUntilHittable(element(containing: name))
        wait(for: row, "label CONTAINS %@", answer)
    }

    func showLeaders() {
        // System segmented control: 32 pt high by design; Apple's audit accepts it, so no 44 pt check here.
        let segment = button(containing: "Leitende")
        segment.tap()
        assertSelected(segment)
    }
}
