import AppKit
import KSCrashRecording
import ToastKit

/// 崩溃与卡顿记录，未发送的放在 ~/.config/CalendarTasks/crashes/，「问题反馈」时打包随邮件发给作者：
/// - 系统崩溃报告：启动时把系统为本 App 生成的 ~/Library/Logs/DiagnosticReports/<进程名>-*.ips（带符号）复制过来，复制过的记在 recorded.txt，不再重复复制。
/// - KSCrash 报告：主线程卡顿（Watchdog，卡住 250ms 起记录）与崩溃，启动时从 KSCrash 的报告库导出为 JSON，导出后从库里删掉。
/// 用户确认邮件已发出后，附带的记录移到 crashes/sent/<日期>/，30 天后删除。
/// 有新的崩溃或卡死后退出就提示。没用 MetricKit：实测故意崩溃后重启，诊断没有送到（2026-11-26），系统崩溃报告则每次都有
@MainActor
enum CrashRecorder {
    static var directory: URL {
        ConfigFile.url.deletingLastPathComponent().appending(path: "crashes", directoryHint: .isDirectory)
    }

    /// 已发送的记录，按发送日期分子目录
    static var sentDirectory: URL { directory.appending(path: "sent", directoryHint: .isDirectory) }

    /// 已复制过的系统崩溃报告文件名，一行一个；移走或删除后也不会再从系统目录复制回来
    private static var recordedListURL: URL { directory.appending(path: "recorded-\(processName).txt") }

    /// 开发版进程名是 CalendarTasks-Dev，文件都以「进程名-」开头，正式版和开发版的记录互不混入
    static var processName: String { ProcessInfo.processInfo.processName }

    /// 卡顿短于这个时长不记，免得记录太多
    private static let minimumHang: TimeInterval = 1
    /// 恢复了的卡顿最多保留的份数，超出删最旧的
    private static let maximumHangFiles = 50
    /// 已发送的记录保留天数
    static let sentRetentionDays = 30

    private static var reportsDirectory: URL {
        ConfigFile.realHome.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// 未发送的记录（.ips 与 .json），新的在前
    static var files: [URL] { records(in: directory) }

    /// 已发送的记录，新的在前
    static var sentFiles: [URL] {
        let days = (try? FileManager.default.contentsOfDirectory(at: sentDirectory, includingPropertiesForKeys: nil)) ?? []
        return days.flatMap { records(in: $0) }.sorted { modificationDate($0) > modificationDate($1) }
    }

    private static func records(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(processName + "-") && ["ips", "json"].contains($0.pathExtension) }
            .sorted { modificationDate($0) > modificationDate($1) }
    }

    static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// 邮件发出后调用：把这次附带的记录移到 sent/<今天>/
    static func markSent(_ urls: [URL]) throws {
        let day = sentDirectory.appending(path: Date.now.formatted(.iso8601.year().month().day()), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.moveItem(at: url, to: day.appending(path: url.lastPathComponent))
        }
    }

    /// 移到废纸篓（可从废纸篓恢复）
    static func trash(_ urls: [URL]) throws {
        for url in urls {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// 启动时尽早调用。报告库放在 ~/.config/CalendarTasks/kscrash-<进程名>/，沙箱内可写
    static func install() {
        let config = KSCrashConfiguration()
        config.installPath = ConfigFile.url.deletingLastPathComponent()
            .appending(path: "kscrash-" + processName, directoryHint: .isDirectory).path
        // 崩溃（Mach 异常、信号、C++ / ObjC 异常）与主线程卡顿。不开 termination：macOS 上强制退出、关机等也会被记成异常终止，干扰多
        config.monitors = [.machException, .signal, .cppException, .nsException, .watchdog]
        // 保留自己恢复了的卡顿（默认会删掉，只留卡死后被结束的）
        config.enableHangReporting = true
        // 每次启动都会导出清空，这里只防一次运行里卡顿太多时丢掉较早的
        config.reportStoreConfiguration.maxReportCount = maximumHangFiles
        do {
            try KSCrash.shared.install(with: config)
        } catch {
            NSLog("KSCrash 安装失败：\(error)")
        }
        // SwiftUI App 默认允许「突然终止」，退出时系统直接 SIGKILL，KSCrash 会把每次正常退出都当成被杀，
        // 并把启动时未收尾的卡顿记成「卡死后退出」。关掉后退出走 exit()，KSCrash 能记下正常退出
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("记录正常退出，供崩溃与卡顿监控区分异常退出")
    }

    /// 收集新的记录，返回这次新增的崩溃 / 卡死数（不含恢复了的卡顿）
    @discardableResult
    static func collect(toasts: ToastCenter) -> Int {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let count = try copySystemReports() + exportKSCrashReports()
            pruneHangFiles()
            pruneSentFiles()
            if count > 0 {
                toasts.show(Toast("发现 \(count) 次异常退出，已记录", kind: .error, action: Toast.Action("发给作者") {
                    Feedback.compose(toasts: toasts)
                }, duration: .seconds(8)))
            }
            return count
        } catch {
            toasts.show("崩溃报告记录失败：" + error.localizedDescription, kind: .error)
            return 0
        }
    }

    private static func copySystemReports() throws -> Int {
        let fileManager = FileManager.default
        let prefix = processName + "-20"
        guard let reports = try? fileManager.contentsOfDirectory(atPath: reportsDirectory.path) else { return 0 }
        // 已复制过的：列表里记着的，加上目录里已有的（列表是 v0.3.0 才加的，之前复制的只在目录里）
        let listed = (try? String(contentsOf: recordedListURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        var recorded = Set(listed).union((files + sentFiles).map(\.lastPathComponent))
        var copied = 0
        for name in reports.sorted() where name.hasPrefix(prefix) && name.hasSuffix(".ips") && !recorded.contains(name) {
            try fileManager.copyItem(at: reportsDirectory.appending(path: name), to: directory.appending(path: name))
            recorded.insert(name)
            copied += 1
        }
        let ips = recorded.filter { $0.hasSuffix(".ips") }.sorted()
        if ips != listed.sorted() {
            try ips.joined(separator: "\n").write(to: recordedListURL, atomically: true, encoding: .utf8)
        }
        return copied
    }

    /// 把 KSCrash 报告库里的报告写成 JSON。KSCrash 抓到的崩溃系统也会生成 .ips，只把「卡死后被结束」计入提示
    private static func exportKSCrashReports() throws -> Int {
        guard let store = KSCrash.shared.reportStore else { return 0 }
        var fatalHangs = 0
        for id in store.reportIDs.map(\.int64Value) {
            defer { store.deleteReport(with: id) }
            guard let report = store.report(for: id)?.value else { continue }
            let error = (report["crash"] as? [String: Any])?["error"] as? [String: Any]
            let kind: String
            // 卡顿中被结束时 type 是 mach 等终止类型，但同样带 hang 字段
            if let hang = error?["hang"] as? [String: Any] {
                // 短于 1 秒的不记。KSCrash 2.6.1 有个竞态：卡顿在写报告期间（约 0.5 秒）就结束时，报告不会被删也不会标为恢复，
                // 下次启动被当成「卡死后退出」（实测每次启动都有一份 0.5 秒左右的启动卡顿）。按时长过滤一并去掉这类误报
                let start = (hang["hang_start_nanos"] as? NSNumber)?.doubleValue ?? 0
                let end = (hang["hang_end_nanos"] as? NSNumber)?.doubleValue ?? 0
                if (end - start) / 1e9 < minimumHang { continue }
                if hang["hang_recovered"] as? Bool ?? false {
                    kind = "hang"
                } else {
                    kind = "fatal-hang"
                    fatalHangs += 1
                }
            } else {
                kind = "crash"
            }
            let date = reportDate(report) ?? .now
            let url = directory.appending(path: "\(processName)-\(kind)-\(fileDateFormatter.string(from: date))-\(id).json")
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return fatalHangs
    }

    /// 报告时间：原始报告里是微秒数，经 KSCrash 修整后是日期字符串
    private static func reportDate(_ report: [String: Any]) -> Date? {
        let value = (report["report"] as? [String: Any])?["timestamp"]
        if let micros = value as? NSNumber { return Date(timeIntervalSince1970: micros.doubleValue / 1e6) }
        if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        return nil
    }

    static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private static func pruneHangFiles() {
        let hangs = files.filter { $0.lastPathComponent.hasPrefix(processName + "-hang-") }
        for url in hangs.dropFirst(maximumHangFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 删掉发送超过 30 天的记录（只删本进程的，正式版与开发版共用 sent/），子目录空了一并删
    private static func pruneSentFiles() {
        let fileManager = FileManager.default
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -sentRetentionDays, to: .now),
              let days = try? fileManager.contentsOfDirectory(at: sentDirectory, includingPropertiesForKeys: nil) else { return }
        for day in days {
            guard let date = try? Date(day.lastPathComponent, strategy: .iso8601.year().month().day()), date < cutoff else { continue }
            records(in: day).forEach { try? fileManager.removeItem(at: $0) }
            if (try? fileManager.contentsOfDirectory(atPath: day.path))?.isEmpty == true {
                try? fileManager.removeItem(at: day)
            }
        }
    }
}
