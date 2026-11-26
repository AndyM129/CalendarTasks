import AppKit
import ToastKit

/// 崩溃记录：启动时把系统为本 App 生成的崩溃报告（~/Library/Logs/DiagnosticReports/<进程名>-*.ips，带符号）
/// 复制到 ~/.config/CalendarTasks/crashes/，有新的就提示。之前复制过的按文件名跳过。
/// 没用 MetricKit：实测故意崩溃后重启，诊断没有送到（2026-11-26），系统崩溃报告则每次都有
@MainActor
enum CrashRecorder {
    static var directory: URL {
        ConfigFile.url.deletingLastPathComponent().appending(path: "crashes", directoryHint: .isDirectory)
    }

    private static var reportsDirectory: URL {
        ConfigFile.realHome.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// 返回这次新复制的崩溃报告数
    @discardableResult
    static func collect(toasts: ToastCenter) -> Int {
        let fileManager = FileManager.default
        // 开发版进程名是 CalendarTasks-Dev，按「进程名-年份」匹配，免得正式版把开发版的也收进来
        let prefix = ProcessInfo.processInfo.processName + "-20"
        guard let reports = try? fileManager.contentsOfDirectory(atPath: reportsDirectory.path) else { return 0 }
        let mine = reports.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".ips") }
        guard !mine.isEmpty else { return 0 }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var copied = 0
            for name in mine where !fileManager.fileExists(atPath: directory.appending(path: name).path) {
                try fileManager.copyItem(at: reportsDirectory.appending(path: name), to: directory.appending(path: name))
                copied += 1
            }
            if copied > 0 {
                toasts.show(Toast("发现 \(copied) 次异常退出，已记录崩溃报告", kind: .error, action: Toast.Action("打开") {
                    NSWorkspace.shared.open(directory)
                }, duration: .seconds(8)))
            }
            return copied
        } catch {
            toasts.show("崩溃报告记录失败：" + error.localizedDescription, kind: .error)
            return 0
        }
    }
}
