import SwiftUI

/// Main navigation of the signed-in person. Chat and profile tabs follow with their issues.
struct MainView: View {
    @Environment(AppState.self) private var state
    let profile: Profile

    private var attendanceUnits: [UnitSummary] {
        LeadershipPermissions(profile: profile).attendanceUnits(from: profile.units)
    }

    var body: some View {
        TabView {
            Tab("Programme", systemImage: "calendar") {
                ProgramListView()
            }
            if !attendanceUnits.isEmpty {
                Tab("Anwesenheit", systemImage: "checklist") {
                    AttendanceListView(units: attendanceUnits)
                }
            }
            Tab("Profil", systemImage: "person.crop.circle") {
                VStack(spacing: 16) {
                    Text("Hallo \(profile.ceviName ?? profile.name)")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Button("Abmelden", role: .destructive) {
                        Task { await state.signOut() }
                    }
                    .frame(minHeight: 44)
                }
                .padding()
            }
        }
    }
}
