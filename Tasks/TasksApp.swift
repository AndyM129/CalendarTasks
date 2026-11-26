import SwiftUI

@main
struct TasksApp: App {
    @State private var store = CalendarStore()

    init() {
        // 尽早开始监控崩溃与卡顿
        CrashRecorder.install()
        #if DEBUG
        DebugBench.runIfRequested()
        // 验证用：启动参数 -debugCrash YES，3 秒后故意崩溃，下次启动看 CrashRecorder 是否记下
        if UserDefaults.standard.bool(forKey: "debugCrash") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { fatalError("debugCrash") }
        }
        // 验证用：启动参数 -debugHang <秒>，3 秒后让主线程卡住这么久，下次启动看卡顿是否记下
        let hang = UserDefaults.standard.double(forKey: "debugHang")
        if hang > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Thread.sleep(forTimeInterval: hang) }
        }
        // 验证用：启动参数 -debugFeedback YES，3 秒后打开问题反馈邮件（只打开写信窗口，不会发出）
        if UserDefaults.standard.bool(forKey: "debugFeedback") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Feedback.compose() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 280, minHeight: 320)
                // 记下之前的崩溃报告，已记过的跳过
                .task { CrashRecorder.collect(toasts: store.toasts) }
                #if DEBUG
                .modifier(DebugOpenSettings())
                #endif
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
    /// 设置里「动画时长」的存储键与默认值
    static let durationKey = "animationDuration"
    static let defaultDuration = 0.3

    /// 全局统一的界面过渡：无回弹的平滑弹簧（与 iOS 导航 push 同类的曲线），时长可在设置里调
    static var ui: Animation {
        let stored = UserDefaults.standard.double(forKey: durationKey)
        return .smooth(duration: stored > 0 ? stored : defaultDuration)
    }
}
