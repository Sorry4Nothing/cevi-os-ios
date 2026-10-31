import SwiftUI

/// Entry for the attendance tab: the units the person leads (all units for admins).
struct AttendanceListView: View {
    let units: [UnitSummary]

    var body: some View {
        NavigationStack {
            List(units) { unit in
                NavigationLink(unit.name) { AttendanceView(unit: unit) }.frame(minHeight: Size.touchTarget)
            }
            .navigationTitle("Anwesenheit")
        }
    }
}
