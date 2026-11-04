import EventKit
import Foundation

/// 提醒选项：相对日程开始的偏移（秒）。全天日程的偏移相对当天 0 点，所以「当天 9:00」是 +9 小时
struct AlarmChoice: Hashable, Identifiable {
    let title: String
    /// nil 表示「无」
    let offset: TimeInterval?
    var id: String { title }

    static let none = AlarmChoice(title: "无", offset: nil)

    static let timed: [AlarmChoice] = [
        .none,
        AlarmChoice(title: "日程发生时", offset: 0),
        AlarmChoice(title: "5 分钟前", offset: -5 * 60),
        AlarmChoice(title: "10 分钟前", offset: -10 * 60),
        AlarmChoice(title: "15 分钟前", offset: -15 * 60),
        AlarmChoice(title: "30 分钟前", offset: -30 * 60),
        AlarmChoice(title: "1 小时前", offset: -3600),
        AlarmChoice(title: "2 小时前", offset: -2 * 3600),
        AlarmChoice(title: "1 天前", offset: -86400),
        AlarmChoice(title: "2 天前", offset: -2 * 86400),
        AlarmChoice(title: "1 周前", offset: -7 * 86400),
    ]

    static let allDay: [AlarmChoice] = [
        .none,
        AlarmChoice(title: "日程当天（9:00）", offset: 9 * 3600),
        AlarmChoice(title: "1 天前（9:00）", offset: -15 * 3600),
        AlarmChoice(title: "2 天前（9:00）", offset: -39 * 3600),
        AlarmChoice(title: "1 周前（9:00）", offset: -159 * 3600),
    ]

    static func choices(allDay: Bool) -> [AlarmChoice] { allDay ? Self.allDay : timed }

    /// 现有提醒对应的选项；不在列表里的（如绝对时间、其他偏移）单独列为「其他」，保持原样不改
    static func current(of event: EKEvent) -> AlarmChoice {
        guard let alarm = event.alarms?.first else { return .none }
        if alarm.absoluteDate == nil,
           let match = choices(allDay: event.isAllDay).first(where: { $0.offset == alarm.relativeOffset }) {
            return match
        }
        return AlarmChoice(title: "其他（保持不变）", offset: alarm.absoluteDate == nil ? alarm.relativeOffset : nil)
    }

    var isKeepExisting: Bool { title == "其他（保持不变）" }
}
