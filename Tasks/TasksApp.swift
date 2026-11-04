import SwiftUI

@main
struct TasksApp: App {
    @State private var store = CalendarStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 980, height: 720)

        Settings {
            SettingsView()
        }
    }
}
