#if DEBUG
import EventKit
import Foundation

/// 验证用的日程时间探针，结果写到容器临时目录的 bench.txt
extension CalendarStore {
    /// -debugBench recurringTimeChange：在「备忘录」日历建一个从明天起、每天重复 3 次的临时全天日程，
    /// 对明天那次按「仅此次」依次走界面同一套路径：留在当天 → 撤销 → 移到今天 → 改回全天，每步读回起止，最后删掉
    func debugProbeRecurringTimeChange() async {
        guard let calendar = calendars.first(where: { $0.title == "备忘录" }) ?? calendarForNewEvents else { return }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let title = "CalendarTasks 调试重复日程，可删除"
        var lines = ["calendar=\(calendar.title) tomorrow=\(describe(tomorrow)) undo=\(undoManager != nil)"]
        let series = EKEvent(eventStore: eventStore)
        series.title = title
        series.calendar = calendar
        series.isAllDay = true
        series.startDate = tomorrow
        series.endDate = tomorrow
        series.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))]
        do {
            try eventStore.save(series, span: .futureEvents, commit: true)
        } catch {
            write(["create failed: \(error)"])
            return
        }
        let predicate = eventStore.predicateForEvents(
            withStart: tomorrow, end: cal.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow, calendars: [calendar])
        guard let occurrence = eventStore.events(matching: predicate)
            .first(where: { $0.calendarItemIdentifier == series.calendarItemIdentifier }) else {
            write(lines + ["occurrence not found"])
            return
        }
        lines.append(describe("before", occurrence))
        updateTitle(of: occurrence, to: "✅" + title, span: .thisEvent, timeChange: .completeOn(tomorrow))
        lines.append(describe("completeOn", occurrence))
        // 等这一轮事件循环结束、撤销分组关闭后再撤销，和用户按 ⌘Z 时一致
        try? await Task.sleep(for: .seconds(1))
        lines.append("canUndo=\(undoManager?.canUndo ?? false) name=\(undoManager?.undoActionName ?? "") "
                     + "groupingLevel=\(undoManager?.groupingLevel ?? -1) toast=\(toasts.current?.message ?? "")")
        undoManager?.undo()
        lines.append("after undo toast=\(toasts.current?.message ?? "")")
        _ = occurrence.refresh()
        lines.append(describe("undo", occurrence))
        updateTitle(of: occurrence, to: "✅" + title, span: .thisEvent, timeChange: .completeNow)
        lines.append(describe("completeNow", occurrence))
        updateTitle(of: occurrence, to: "⬜️" + title, span: .thisEvent, timeChange: .revertToAllDay)
        lines.append(describe("revertToAllDay", occurrence))
        try? await Task.sleep(for: .seconds(8))
        _ = occurrence.refresh()
        lines.append(describe("after 8s", occurrence))
        // 拆出来的那次和系列都按标题删掉
        let wide = eventStore.predicateForEvents(
            withStart: cal.startOfDay(for: .now), end: cal.date(byAdding: .day, value: 5, to: tomorrow) ?? tomorrow,
            calendars: [calendar])
        for leftover in eventStore.events(matching: wide) where (leftover.title ?? "").hasSuffix(title) {
            try? eventStore.remove(leftover, span: .futureEvents, commit: true)
        }
        let remaining = eventStore.events(matching: wide).filter { ($0.title ?? "").hasSuffix(title) }.count
        write(lines + ["remaining=\(remaining)"])
    }

    /// -debugBench inspectTest：只读，列出近几天标题含「测试」的日程的日历、时区、起止与重复信息
    func debugInspectTestEvents() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: .now)) ?? .now
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? .now
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let lines = eventStore.events(matching: predicate)
            .filter { ($0.title ?? "").contains("测试") }
            .map { event in
                describe(event.title ?? "", event)
                    + " calendar=\(event.calendar.title) source=\(event.calendar.source?.title ?? "")"
                    + " recurring=\(event.hasRecurrenceRules) detached=\(event.isDetached)"
                    + " occurrence=\(describe(event.occurrenceDate))"
            }
        write(lines.isEmpty ? ["no events"] : lines)
    }

    private func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm xxx"
        return formatter.string(from: date)
    }

    private func describe(_ label: String, _ event: EKEvent) -> String {
        "\(label): allDay=\(event.isAllDay) tz=\(event.timeZone?.identifier ?? "nil") "
            + "start=\(describe(event.startDate)) end=\(describe(event.endDate))"
    }

    private func write(_ lines: [String]) {
        try? lines.joined(separator: "\n").write(
            to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
