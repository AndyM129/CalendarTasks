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
    /// 日程数据版本，每次重新加载递增
    private(set) var revision = 0
    /// 列表末尾是否显示新增输入行
    var isAddingEvent = false
    /// 日期选择浮层是否打开（点大标题或 ⌘J）
    var isPickingDate = false
    var searchText = ""

    var day: Date = Calendar.current.startOfDay(for: .now) {
        didSet { reloadEvents() }
    }

    var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: Self.selectedIDsKey)
            saveConfig()
            reloadEvents()
        }
    }

    var groups: [CalendarGroup] = [] {
        didSet { saveConfig() }
    }

    /// 旧版本存在 UserDefaults 里的组合，首次生成配置文件时迁移
    private static func loadLegacyGroups() -> [CalendarGroup] {
        guard let data = UserDefaults.standard.data(forKey: groupsKey) else { return [] }
        return (try? JSONDecoder().decode([CalendarGroup].self, from: data)) ?? []
    }

    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// 配置文件里记下的日历引用（按 ID），本机找不到该日历时用它按名字重新匹配、写回时原样保留
    @ObservationIgnored private var knownCalendarRefs: [String: ConfigFile.CalendarRef] = [:]
    /// 最近一次读到或写入的配置，内容没变就不写文件
    @ObservationIgnored private var savedConfig: ConfigFile.Content?
    /// 配置文件格式有误时不写，免得覆盖用户手改的内容
    @ObservationIgnored private var configWritable = true

    init() {
        loadConfig()
        #if DEBUG
        // 验证用：启动参数 -debugShowHidden YES 启动时就显示已隐藏的日程
        showHiddenEvents = UserDefaults.standard.bool(forKey: "debugShowHidden")
        #endif
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadAll() }
        }
        // 设置窗口改 emoji、动画时长等写的是 UserDefaults，有改动就同步到配置文件
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveConfig() }
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
        events.filter { $0.isAllDay && isVisible($0) }.sorted(by: listOrder)
    }

    var timedEvents: [EKEvent] {
        events.filter { !$0.isAllDay && isVisible($0) }.sorted(by: listOrder)
    }

    /// 列表里「显示 / 隐藏已结束日程」的开关，不持久化，每次启动默认隐藏
    var showHiddenEvents = false
    /// 刚改成隐藏状态、还在 3 秒宽限期内的日程（calendarItemIdentifier）
    var pendingHideIDs: Set<String> = []

    func count(for calendar: EKCalendar) -> Int {
        dayEventsAllCalendars.count { $0.calendar.calendarIdentifier == calendar.calendarIdentifier }
    }

    // MARK: - 写回

    /// 最近一次写入失败的说明，界面弹窗展示后清空
    var lastError: String?

    /// 改标题（状态 / 优先级 emoji）。completesAllDay 为 true 时，全天日程同时改为非全天、起止都设为当前分钟。
    /// 改成「隐藏的状态」时先留在列表里 3 秒，再带过渡隐藏
    func updateTitle(of event: EKEvent, to title: String, span: EKSpan, completesAllDay: Bool = false) {
        event.title = title
        if completesAllDay, event.isAllDay {
            let now = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
            event.isAllDay = false
            // 全天日程的 timeZone 为 nil（浮动时间），不补上的话起止会按 UTC 解读，与本机时间差一个时区
            event.timeZone = .current
            event.startDate = now
            event.endDate = now
        }
        let id = event.calendarItemIdentifier
        let willHide = isHiddenStatus(of: event)
        if willHide { pendingHideIDs.insert(id) }
        guard save(event, span: span), willHide else {
            pendingHideIDs.remove(id)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.ui) { _ = pendingHideIDs.remove(id) }
        }
    }

    /// 保存改动；失败时撤回未保存的修改并记录原因
    @discardableResult
    func save(_ event: EKEvent, span: EKSpan) -> Bool {
        defer { reloadEvents() }
        do {
            try eventStore.save(event, span: span, commit: true)
            return true
        } catch {
            event.rollback()
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - 新增

    /// 新日程所在日历：系统默认日历在勾选中时用它，否则用勾选里第一个可编辑的日历
    var calendarForNewEvents: EKCalendar? {
        let editable = calendars.filter { isSelected($0) && $0.allowsContentModifications }
        if let fallback = eventStore.defaultCalendarForNewEvents,
           editable.contains(where: { $0.calendarIdentifier == fallback.calendarIdentifier }) {
            return fallback
        }
        return editable.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.first
    }

    /// 只给标题时默认为当日全天日程
    func createEvent(title: String) {
        guard let calendar = calendarForNewEvents else {
            lastError = "所选日历都不可编辑，请先勾选一个可编辑的日历。"
            return
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = day
        event.endDate = day
        save(event, span: .thisEvent)
    }

    // MARK: - 删除与撤销

    /// 删除日程，可用 ⌘Z 撤销：按删除前快照重建。
    /// 重复日程「仅此次」恢复为独立的单次日程；「将来所有」从这次开始按原规则重建系列
    func delete(_ event: EKEvent, span: EKSpan, undoManager: UndoManager?) {
        let keepsRecurrence = event.hasRecurrenceRules && span == .futureEvents
        let snapshot = EventSnapshot(event, keepsRecurrence: keepsRecurrence)
        do {
            try eventStore.remove(event, span: span, commit: true)
        } catch {
            lastError = error.localizedDescription
            reloadEvents()
            return
        }
        reloadEvents()
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            store.restore(snapshot, undoManager: undoManager)
        }
        undoManager.setActionName("删除日程")
    }

    private func restore(_ snapshot: EventSnapshot, undoManager: UndoManager) {
        let event = snapshot.makeEvent(in: eventStore)
        let span: EKSpan = event.hasRecurrenceRules ? .futureEvents : .thisEvent
        guard save(event, span: span) else { return }
        undoManager.registerUndo(withTarget: self) { store in
            store.delete(event, span: span, undoManager: undoManager)
        }
        undoManager.setActionName("删除日程")
    }

    // MARK: - 搜索

    /// 在勾选日历中搜索当日前后各一年的标题 / 地点 / 备注
    func search(_ query: String) -> [EKEvent] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = calendars.filter(isSelected)
        guard !keyword.isEmpty, !selected.isEmpty,
              let start = Calendar.current.date(byAdding: .year, value: -1, to: day),
              let end = Calendar.current.date(byAdding: .year, value: 1, to: day) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        return eventStore.events(matching: predicate)
            .filter { event in
                [event.title, event.location, event.notes].contains { $0?.localizedStandardContains(keyword) == true }
            }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - 配置文件

    private func loadConfig() {
        switch ConfigFile.read() {
        case .loaded(let content):
            ConfigFile.applyPreferences(of: content)
            for ref in content.calendarGroups.flatMap(\.calendars) + (content.selectedCalendars ?? []) {
                knownCalendarRefs[ref.id] = ref
            }
            if let selected = content.selectedCalendars {
                UserDefaults.standard.set(selected.map(\.id), forKey: Self.selectedIDsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedIDsKey)
            }
            savedConfig = content
            groups = content.calendarGroups.map {
                CalendarGroup(id: $0.id, name: $0.name, tint: $0.tint, calendarIDs: Set($0.calendars.map(\.id)))
            }
        case .missing:
            // 首次启动或旧版本升级：用 UserDefaults 里已有的设置生成配置文件
            groups = Self.loadLegacyGroups()
        case .invalid(let message):
            configWritable = false
            lastError = message
            groups = Self.loadLegacyGroups()
        }
    }

    private func saveConfig() {
        guard configWritable else { return }
        let prefs = ConfigFile.currentPreferences()
        let selected = UserDefaults.standard.array(forKey: Self.selectedIDsKey) as? [String]
        let content = ConfigFile.Content(
            statusEmojis: prefs.status,
            priorityEmojis: prefs.priority,
            hiddenStatuses: prefs.hidden,
            animationDuration: prefs.duration,
            selectedCalendars: selected.map { refs(for: Set($0)) },
            calendarGroups: groups.map {
                ConfigFile.Group(id: $0.id, name: $0.name, tint: $0.tint, calendars: refs(for: $0.calendarIDs))
            }
        )
        guard content != savedConfig else { return }
        do {
            try ConfigFile.write(content)
            savedConfig = content
        } catch {
            // 只提示一次，之后不再尝试写
            configWritable = false
            lastError = "无法写入配置文件 \(ConfigFile.url.path)：\(error.localizedDescription)"
        }
    }

    /// 本机找得到的日历取最新的账户名与日历名；找不到的保留配置文件里的原样
    private func refs(for ids: Set<String>) -> [ConfigFile.CalendarRef] {
        ids.map { id in
            if let calendar = calendars.first(where: { $0.calendarIdentifier == id }) {
                return ConfigFile.CalendarRef(id: id, account: calendar.source?.title ?? "", title: calendar.title)
            }
            return knownCalendarRefs[id] ?? ConfigFile.CalendarRef(id: id, account: "", title: "")
        }
        .sorted { ($0.account, $0.title, $0.id) < ($1.account, $1.title, $1.id) }
    }

    /// 本机没有这个 ID 的日历时，按配置里记的账户 + 日历名找本机的同名日历
    private func resolvedID(_ id: String) -> String {
        guard !calendars.contains(where: { $0.calendarIdentifier == id }),
              let ref = knownCalendarRefs[id],
              let match = calendars.first(where: { $0.title == ref.title && ($0.source?.title ?? "") == ref.account })
        else { return id }
        return match.calendarIdentifier
    }

    // MARK: - 加载

    private func reloadAll() {
        calendars = eventStore.calendars(for: .event)
        let validIDs = Set(calendars.map(\.calendarIdentifier))
        // 配置来自别的机器时，日历 ID 对不上，按账户 + 日历名换成本机的 ID
        let resolvedGroups = groups.map { group in
            var group = group
            group.calendarIDs = Set(group.calendarIDs.map(resolvedID))
            return group
        }
        if resolvedGroups != groups { groups = resolvedGroups }
        saveConfig()
        if let saved = UserDefaults.standard.array(forKey: Self.selectedIDsKey) as? [String] {
            let kept = Set(saved.map(resolvedID)).intersection(validIDs)
            if kept != selectedCalendarIDs { selectedCalendarIDs = kept; return }
        } else {
            selectedCalendarIDs = validIDs
            return
        }
        reloadEvents()
    }

    private func reloadEvents() {
        defer { revision &+= 1 }
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
