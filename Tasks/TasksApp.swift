import SwiftUI

@main
struct TasksApp: App {
    @State private var store = CalendarStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 280, minHeight: 320)
        }
        .defaultSize(width: 980, height: 720)

        Settings {
            SettingsView()
        }
    }
}
