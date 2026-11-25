import EventKit

/// 删除或修改前保存的日程内容，用于撤销时重建或改回
struct EventSnapshot {
    let title: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZone: TimeZone?
    let calendarID: String
    let location: String?
    let notes: String?
    let url: URL?
    let alarms: [EKAlarm]
    /// 只在删除「将来所有」或修改时保留，撤销删除时从这次开始重建系列
    let recurrenceRules: [EKRecurrenceRule]

    init(_ event: EKEvent, keepsRecurrence: Bool) {
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        timeZone = event.timeZone
        calendarID = event.calendar.calendarIdentifier
        location = event.location
        notes = event.notes
        url = event.url
        alarms = (event.alarms ?? []).compactMap { $0.copy() as? EKAlarm }
        recurrenceRules = keepsRecurrence
            ? (event.recurrenceRules ?? []).compactMap { $0.copy() as? EKRecurrenceRule }
            : []
    }

    func makeEvent(in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = startDate
        event.endDate = endDate
        event.timeZone = timeZone
        event.calendar = store.calendar(withIdentifier: calendarID) ?? store.defaultCalendarForNewEvents
        event.location = location
        event.notes = notes
        event.url = url
        event.alarms = alarms.compactMap { $0.copy() as? EKAlarm }
        if !recurrenceRules.isEmpty {
            event.recurrenceRules = recurrenceRules.compactMap { $0.copy() as? EKRecurrenceRule }
        }
        return event
    }

    /// 把已有日程改回快照里的内容（撤销修改用）。restoresRecurrence 为 false（「仅此次」的改动）时不碰重复规则：
    /// 这一次已从系列里拆出来，再写规则 EventKit 会报「无法更改重复字段」；为 true 时也只在与快照不同时才写
    func apply(to event: EKEvent, in store: EKEventStore, restoresRecurrence: Bool) {
        event.title = title
        event.isAllDay = isAllDay
        event.timeZone = timeZone
        event.startDate = startDate
        event.endDate = endDate
        // 日历和提醒只在变了时才写：拆出来的那一次哪怕写回同一个日历，EventKit 也会报「无法更改重复字段」
        if event.calendar.calendarIdentifier != calendarID, let calendar = store.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        }
        event.location = location
        event.notes = notes
        event.url = url
        if (event.alarms ?? []).map(\.description) != alarms.map(\.description) {
            event.alarms = alarms.compactMap { $0.copy() as? EKAlarm }
        }
        guard restoresRecurrence else { return }
        let current = (event.recurrenceRules ?? []).map(\.description)
        if current != recurrenceRules.map(\.description) {
            event.recurrenceRules = recurrenceRules.isEmpty ? nil : recurrenceRules.compactMap { $0.copy() as? EKRecurrenceRule }
        }
    }
}
