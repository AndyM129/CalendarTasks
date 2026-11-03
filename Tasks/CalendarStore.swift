import EventKit
import Observation
import SwiftUI

/// 封装 EventKit：权限、日历列表、所选日历与当日日程。
@Observable
final class CalendarStore {
    private static let selectedIDsKey = "selectedCalendarIDs"
    private static let groupsKey = "calendarGroups"

    let eventStore = EKEventStore()

    private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [EKCalendar] = []
    /// 当日所有日历中的日程，用于计数
    private(set) var dayEventsAllCalendars: [EKEvent] = []
    private(set) var todayCountSelected = 0

    var day: Date = Calendar.current.startOfDay(for: .now) {
        didSet { reloadEvents() }
    }

    var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: Self.selectedIDsKey)
            reloadEvents()
        }
    }

    var groups: [CalendarGroup] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(groups) {
                UserDefaults.standard.set(data, forKey: Self.groupsKey)
            }
        }
    }

    private static func loadGroups() -> [CalendarGroup] {
        guard let data = UserDefaults.standard.data(forKey: groupsKey) else { return [] }
        return (try? JSONDecoder().decode([CalendarGroup].self, from: data)) ?? []
    }

    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    init() {
        groups = Self.loadGroups()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadAll() }
        }
        if authorization == .fullAccess { reloadAll() }
    }

    // MARK: - 权限

    var hasAccess: Bool { authorization == .fullAccess }

    func requestAccess() async {
        _ = try? await eventStore.requestFullAccessToEvents()
        authorization = EKEventStore.authorizationStatus(for: .event)
        if hasAccess { reloadAll() }
    }

    // MARK: - 日历

    /// 按账户（来源）分组的日历，组内按标题排序
    var calendarGroups: [(source: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars) { $0.source?.title ?? "其他" }
            .map { ($0.key, $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }

    func isSelected(_ calendar: EKCalendar) -> Bool {
        selectedCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func toggle(_ calendar: EKCalendar) {
        if isSelected(calendar) {
            selectedCalendarIDs.remove(calendar.calendarIdentifier)
        } else {
            selectedCalendarIDs.insert(calendar.calendarIdentifier)
        }
    }

    var allSelected: Bool {
        !calendars.isEmpty && calendars.allSatisfy(isSelected)
    }

    func selectAll() {
        selectedCalendarIDs = Set(calendars.map(\.calendarIdentifier))
    }

    // MARK: - 日历组合

    func saveGroup(_ group: CalendarGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
    }

    func deleteGroup(_ group: CalendarGroup) {
        groups.removeAll { $0.id == group.id }
    }

    /// 组合中仍存在的日历
    func validIDs(of group: CalendarGroup) -> Set<String> {
        group.calendarIDs.intersection(calendars.map(\.calendarIdentifier))
    }

    func apply(_ group: CalendarGroup) {
        selectedCalendarIDs = validIDs(of: group)
    }

    /// 勾选恰好等于该组合时视为选中
    func isActive(_ group: CalendarGroup) -> Bool {
        let ids = validIDs(of: group)
        return !ids.isEmpty && ids == selectedCalendarIDs
    }

    func count(for group: CalendarGroup) -> Int {
        let ids = validIDs(of: group)
        return dayEventsAllCalendars.count { ids.contains($0.calendar.calendarIdentifier) }
    }

    // MARK: - 日期

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func goToday() { day = Calendar.current.startOfDay(for: .now) }

    func shiftDay(by value: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: value, to: day) {
            day = next
        }
    }

    // MARK: - 日程

    /// 当日、所选日历中的日程
    var events: [EKEvent] {
        dayEventsAllCalendars.filter { selectedCalendarIDs.contains($0.calendar.calendarIdentifier) }
    }

    var allDayEvents: [EKEvent] {
        events.filter(\.isAllDay)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var timedEvents: [EKEvent] {
        events.filter { !$0.isAllDay }
            .sorted { ($0.startDate, $0.title) < ($1.startDate, $1.title) }
    }

    func count(for calendar: EKCalendar) -> Int {
        dayEventsAllCalendars.count { $0.calendar.calendarIdentifier == calendar.calendarIdentifier }
    }

    // MARK: - 加载

    private func reloadAll() {
        calendars = eventStore.calendars(for: .event)
        let validIDs = Set(calendars.map(\.calendarIdentifier))
        if let saved = UserDefaults.standard.array(forKey: Self.selectedIDsKey) as? [String] {
            let kept = Set(saved).intersection(validIDs)
            if kept != selectedCalendarIDs { selectedCalendarIDs = kept; return }
        } else {
            selectedCalendarIDs = validIDs
            return
        }
        reloadEvents()
    }

    private func reloadEvents() {
        guard hasAccess, !calendars.isEmpty else {
            dayEventsAllCalendars = []
            todayCountSelected = 0
            return
        }
        dayEventsAllCalendars = fetchEvents(on: day, in: calendars)
        let selected = calendars.filter(isSelected)
        todayCountSelected = selected.isEmpty ? 0 : fetchEvents(on: .now, in: selected).count
    }

    private func fetchEvents(on date: Date, in calendars: [EKCalendar]) -> [EKEvent] {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate)
    }
}
