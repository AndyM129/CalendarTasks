import SwiftUI

@main
struct TasksApp: App {
    @State private var store = CalendarStore()

    init() {
        #if DEBUG
        DebugBench.runIfRequested()
        #endif
    }

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

extension Animation {
    /// 全局统一的界面过渡：0.3 秒缓入缓出曲线
    static let ui = Animation.easeInOut(duration: 0.3)
}
