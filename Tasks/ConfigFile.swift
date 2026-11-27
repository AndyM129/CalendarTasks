import SwiftUI

/// 用户设置的本地配置文件：~/.config/CalendarTasks/config.json（开发版为 config-dev.json）。
/// 卸载重装、换机后放回这个文件即可复用设置。手工改文件后重启 App 生效。
/// 运行时各设置仍读 UserDefaults：启动时用文件内容覆盖，之后有改动就写回文件
enum ConfigFile {
    struct Content: Codable, Equatable {
        var statusEmojis: String
        var priorityEmojis: String
        var hiddenStatuses: String
        var animationDuration: Double
        /// 勾选的日历；没有这一项时勾选全部
        var selectedCalendars: [CalendarRef]?
        var calendarGroups: [Group]
        /// 是否自动检查更新；缺省（旧配置文件没有这一项）视为开启
        var autoUpdate: Bool?
        /// 上次自动检查更新的时间
        var updateCheckAt: Date?
        /// 自动检查发现、还没装的版本号
        var pendingUpdateVersion: String?
    }

    /// 日历引用。日历 ID 由本机生成，换机后同一个日历的 ID 会变，ID 对不上时按「账户 + 日历名」重新匹配
    struct CalendarRef: Codable, Hashable {
        var id: String
        var account: String
        var title: String
    }

    struct Group: Codable, Equatable {
        var id: UUID
        var name: String
        var tint: CalendarGroup.Tint
        var calendars: [CalendarRef]
    }

    enum ReadResult {
        case missing
        case loaded(Content)
        case invalid(String)
    }

    static var url: URL {
        #if DEBUG
        let name = "config-dev.json"
        #else
        let name = "config.json"
        #endif
        return realHome.appending(path: ".config/CalendarTasks/\(name)")
    }

    /// 沙箱里 homeDirectoryForCurrentUser 指向容器目录，这里取用户真正的主目录
    static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func read() -> ReadResult {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(Content.self, from: data))
        } catch {
            return .invalid("配置文件 \(url.path) 格式有误，本次不读取也不覆盖它：\(error.localizedDescription)")
        }
    }

    static func write(_ content: Content) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(content)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - 与 UserDefaults 互转（日历相关的由 CalendarStore 处理）

    static func applyPreferences(of content: Content) {
        let defaults = UserDefaults.standard
        defaults.set(content.statusEmojis, forKey: EmojiMarkers.statusKey)
        defaults.set(content.priorityEmojis, forKey: EmojiMarkers.priorityKey)
        defaults.set(content.hiddenStatuses, forKey: CalendarStore.hiddenStatusKey)
        defaults.set(content.animationDuration, forKey: Animation.durationKey)
        defaults.set(content.autoUpdate ?? true, forKey: UpdateSettings.autoUpdateKey)
        defaults.set(content.updateCheckAt, forKey: UpdateSettings.checkAtKey)
        defaults.set(content.pendingUpdateVersion, forKey: UpdateSettings.pendingVersionKey)
    }

    /// 更新相关的当前设置，写回配置文件时用
    static func currentUpdateState() -> (autoUpdate: Bool, checkAt: Date?, pending: String?) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: UpdateSettings.autoUpdateKey) as? Bool ?? true,
            defaults.object(forKey: UpdateSettings.checkAtKey) as? Date,
            defaults.string(forKey: UpdateSettings.pendingVersionKey)
        )
    }

    static func currentPreferences() -> (status: String, priority: String, hidden: String, duration: Double) {
        let defaults = UserDefaults.standard
        let duration = defaults.double(forKey: Animation.durationKey)
        return (
            defaults.string(forKey: EmojiMarkers.statusKey) ?? EmojiMarkers.defaultStatuses,
            defaults.string(forKey: EmojiMarkers.priorityKey) ?? EmojiMarkers.defaultPriorities,
            defaults.string(forKey: CalendarStore.hiddenStatusKey) ?? CalendarStore.defaultHiddenStatuses,
            duration > 0 ? duration : Animation.defaultDuration
        )
    }
}
