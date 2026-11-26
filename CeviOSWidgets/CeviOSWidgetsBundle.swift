import SwiftUI
import WidgetKit

@main
struct CeviOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextProgramWidget()
        CalendarWidget()
        CampTodayWidget()
        TasksWidget()
        EmergencyWidget()
        ChatWidget()
    }
}
