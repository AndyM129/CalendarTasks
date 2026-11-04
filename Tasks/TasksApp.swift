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
        .commands {
            // 工具栏不放新增按钮；「文件 › 新增日程 ⌘N」代替默认的新建窗口
            CommandGroup(replacing: .newItem) {
                Button("新增日程") {
                    store.searchText = ""
                    withAnimation(.ui) { store.isAddingEvent = true }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!store.hasAccess || store.calendarForNewEvents == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Animation {
    /// 全局统一的界面过渡：0.3 秒缓入缓出曲线
    static let ui = Animation.easeInOut(duration: 0.3)
}
