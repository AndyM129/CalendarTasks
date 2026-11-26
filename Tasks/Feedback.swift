import AppKit
import ToastKit

/// App 与本机信息，「关于」页与反馈邮件共用
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// 系统名称，如 macOS Tahoe；不认识的版本只写 macOS
    static var macOSName: String {
        let names = [26: "Tahoe"]
        guard let name = names[ProcessInfo.processInfo.operatingSystemVersion.majorVersion] else { return "macOS" }
        return "macOS " + name
    }

    static var memory: String {
        "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB"
    }

    /// 机型标识，如 Mac16,7
    static var model: String { sysctlString("hw.model") }

    static var chip: String { sysctlString("machdep.cpu.brand_string") }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname(name, &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// 问题反馈：用默认邮件 App 写一封给作者的邮件，带上模板和崩溃 / 卡顿记录的压缩包
@MainActor
enum Feedback {
    static let recipient = "andym129_hello@163.com"

    static func compose(toasts: ToastCenter? = nil) {
        let subject = "\(AppInfo.name) 问题反馈（v\(AppInfo.version)）"
        var items: [Any] = [body()]
        let archive: URL?
        do {
            archive = try makeArchive()
        } catch {
            archive = nil
            toasts?.show("打包崩溃记录失败：" + error.localizedDescription, kind: .error)
        }
        if let archive { items.append(archive) }

        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) {
            service.recipients = [recipient]
            service.subject = subject
            service.perform(withItems: items)
            return
        }
        // 没有可用的邮件 App：用 mailto 打开（不能带附件），并在访达里选中压缩包，方便手动拖进邮件
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body())]
        if let url = components.url { NSWorkspace.shared.open(url) }
        if let archive { NSWorkspace.shared.activateFileViewerSelecting([archive]) }
    }

    private static func body() -> String {
        let records = CrashRecorder.files.count
        return """
        你好，我在使用 \(AppInfo.name) 时遇到了问题：

        【问题描述】


        【复现步骤】
        1.
        2.

        【期望结果】


        ——
        App：\(AppInfo.name) v\(AppInfo.version)（\(AppInfo.build)）
        系统：macOS \(AppInfo.macOSVersion)
        机型：\(AppInfo.model)，\(AppInfo.chip)
        崩溃与卡顿记录：\(records == 0 ? "无" : "\(records) 份，见附件")
        """
    }

    /// 把本进程的记录打成 zip，放在 ~/.config/CalendarTasks/feedback/；没有记录时返回 nil
    private static func makeArchive() throws -> URL? {
        let files = CrashRecorder.files
        guard !files.isEmpty else { return nil }
        let fileManager = FileManager.default
        let feedbackDirectory = ConfigFile.url.deletingLastPathComponent()
            .appending(path: "feedback", directoryHint: .isDirectory)
        let name = "\(CrashRecorder.processName)-reports-\(CrashRecorder.fileDateFormatter.string(from: .now))"
        let staging = feedbackDirectory.appending(path: name, directoryHint: .isDirectory)
        let archive = feedbackDirectory.appending(path: name + ".zip")
        // 之前打的包已经发出或作废，只留这一次的
        if let old = try? fileManager.contentsOfDirectory(at: feedbackDirectory, includingPropertiesForKeys: nil) {
            old.forEach { try? fileManager.removeItem(at: $0) }
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        for file in files {
            try fileManager.copyItem(at: file, to: staging.appending(path: file.lastPathComponent))
        }

        // 读目录时带 forUploading，系统给出该目录的 zip（只在回调内有效，复制出来）
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinationError) { zip in
            do { try fileManager.copyItem(at: zip, to: archive) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return archive
    }
}
