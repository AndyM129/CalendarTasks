import EventKit
import Foundation

/// 重复设置草稿，与 EKRecurrenceRule 互转。只覆盖系统日历常用的几种：
/// 预设（每天/每周/每两周/每月/每年）与自定义（每 N 天/周/月/年，按周时可选星期几），外加结束条件
struct RepeatDraft: Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case none, daily, weekly, biweekly, monthly, yearly, custom
        var id: Self { self }
        var title: String {
            switch self {
            case .none: "永不"
            case .daily: "每天"
            case .weekly: "每周"
            case .biweekly: "每两周"
            case .monthly: "每月"
            case .yearly: "每年"
            case .custom: "自定义…"
            }
        }
    }

    enum Unit: Int, CaseIterable, Identifiable {
        case day, week, month, year
        var id: Self { self }
        var title: String { ["天", "周", "月", "年"][rawValue] }
        var frequency: EKRecurrenceFrequency { [.daily, .weekly, .monthly, .yearly][rawValue] }
        init(_ frequency: EKRecurrenceFrequency) {
            switch frequency {
            case .daily: self = .day
            case .weekly: self = .week
            case .monthly: self = .month
            default: self = .year
            }
        }
    }

    enum End: Equatable {
        case never, onDate(Date), afterCount(Int)
    }

    var enabled = false
    var unit = Unit.week
    var interval = 1
    /// 按周重复时选中的星期，1 = 周日 … 7 = 周六；为空表示跟随开始日期
    var weekdays: Set<Int> = []
    var end = End.never
    /// 原规则含本编辑器表达不了的细节（如每月第几个星期几）时为 true，提示用户改动会覆盖
    var hasUnsupportedDetails = false
    /// 用户选了「自定义…」：即使当前设置恰好等于某个预设，也保持自定义编辑区展开
    var isCustom = false

    init() {}

    init(rule: EKRecurrenceRule?) {
        guard let rule else { return }
        enabled = true
        unit = Unit(rule.frequency)
        interval = max(rule.interval, 1)
        weekdays = Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
        if let endDate = rule.recurrenceEnd?.endDate {
            end = .onDate(endDate)
        } else if let count = rule.recurrenceEnd?.occurrenceCount, count > 0 {
            end = .afterCount(count)
        }
        hasUnsupportedDetails = rule.daysOfTheMonth != nil || rule.monthsOfTheYear != nil
            || rule.setPositions != nil || rule.weeksOfTheYear != nil || rule.daysOfTheYear != nil
            || (rule.daysOfTheWeek ?? []).contains { $0.weekNumber != 0 }
    }

    func preset(start: Date) -> Preset {
        guard enabled else { return .none }
        let plainWeek = weekdays.isEmpty || weekdays == [Calendar.current.component(.weekday, from: start)]
        if hasUnsupportedDetails || isCustom { return .custom }
        switch (unit, interval) {
        case (.day, 1): return .daily
        case (.week, 1) where plainWeek: return .weekly
        case (.week, 2) where plainWeek: return .biweekly
        case (.month, 1): return .monthly
        case (.year, 1): return .yearly
        default: return .custom
        }
    }

    mutating func apply(_ preset: Preset, start: Date) {
        let keepEnd = end
        switch preset {
        case .none: self = RepeatDraft()
        case .daily: self = RepeatDraft(enabled: true, unit: .day)
        case .weekly: self = RepeatDraft(enabled: true, unit: .week)
        case .biweekly: self = RepeatDraft(enabled: true, unit: .week, interval: 2)
        case .monthly: self = RepeatDraft(enabled: true, unit: .month)
        case .yearly: self = RepeatDraft(enabled: true, unit: .year)
        case .custom:
            enabled = true
            isCustom = true
            if unit == .week && weekdays.isEmpty {
                weekdays = [Calendar.current.component(.weekday, from: start)]
            }
        }
        if preset != .none { end = keepEnd }
    }

    private init(enabled: Bool, unit: Unit, interval: Int = 1) {
        self.enabled = enabled
        self.unit = unit
        self.interval = interval
    }

    func makeRule() -> EKRecurrenceRule? {
        guard enabled else { return nil }
        let days = unit == .week && !weekdays.isEmpty
            ? weekdays.sorted().compactMap { EKWeekday(rawValue: $0).map(EKRecurrenceDayOfWeek.init) }
            : nil
        let recurrenceEnd: EKRecurrenceEnd? = switch end {
        case .never: nil
        case .onDate(let date): EKRecurrenceEnd(end: date)
        case .afterCount(let count): EKRecurrenceEnd(occurrenceCount: max(count, 1))
        }
        return EKRecurrenceRule(recurrenceWith: unit.frequency, interval: interval, daysOfTheWeek: days,
                                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                daysOfTheYear: nil, setPositions: nil, end: recurrenceEnd)
    }

    /// 摘要，如「每 2 周的周一、周三，共 10 次」
    func summary(start: Date) -> String {
        let preset = preset(start: start)
        var text = preset == .custom ? customSummary : preset.title
        switch end {
        case .never: break
        case .onDate(let date): text += "，至 " + date.formatted(date: .abbreviated, time: .omitted)
        case .afterCount(let count): text += "，共 \(count) 次"
        }
        return text
    }

    private var customSummary: String {
        var text = interval == 1 ? "每\(unit.title)" : "每 \(interval) \(unit.title)"
        if unit == .week, !weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            text += "的" + weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: "、")
        }
        return hasUnsupportedDetails ? text + "（含更多规则）" : text
    }
}
