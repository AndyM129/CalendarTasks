import EventKit
import Foundation

/// 日程列表的排序与「隐藏已结束日程」
extension CalendarStore {
    /// 列表中 emoji 前缀的先后：越靠后显示越靠上（✅ 沉到底，其他 emoji 在最上）；无前缀按 ℹ️ 算
    static let emojiRankOrder = ["✅", "❎", "⬜️", "‼️", "❗️", "❕", "ℹ️"].map { EmojiMarkers.normalized($0) }

    /// 「隐藏的状态」设置
    static let hiddenStatusKey = "hiddenStatuses"
    static let defaultHiddenStatuses = "✅❎"

    var statusItems: [String] {
        EmojiMarkers.items(UserDefaults.standard.string(forKey: EmojiMarkers.statusKey) ?? "",
                           fallback: EmojiMarkers.defaultStatuses)
    }

    var priorityItems: [String] {
        EmojiMarkers.items(UserDefaults.standard.string(forKey: EmojiMarkers.priorityKey) ?? "",
                           fallback: EmojiMarkers.defaultPriorities)
    }

    var hiddenStatusItems: Set<String> {
        Set(EmojiMarkers.items(UserDefaults.standard.string(forKey: Self.hiddenStatusKey) ?? "",
                               fallback: Self.defaultHiddenStatuses).map { EmojiMarkers.normalized($0) })
    }

    func marked(_ event: EKEvent) -> MarkedTitle {
        MarkedTitle(event.title ?? "", statuses: statusItems, priorities: priorityItems)
    }

    func isHiddenStatus(of event: EKEvent) -> Bool {
        isHiddenStatus(marked(event).status)
    }

    /// 「隐藏的状态」也表示结果（如 ✅❎）：改成它时视为完成
    func isHiddenStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        return hiddenStatusItems.contains(EmojiMarkers.normalized(status))
    }

    /// 打开了「显示」、不是隐藏状态、或还在 3 秒宽限期内的日程才显示
    func isVisible(_ event: EKEvent) -> Bool {
        showHiddenEvents || !isHiddenStatus(of: event) || pendingHideIDs.contains(event.calendarItemIdentifier)
    }

    /// 当日、所选日历中处于隐藏状态的日程数（不论当前是否显示）
    var hiddenEventCount: Int {
        events.count { isHiddenStatus(of: $0) }
    }

    /// 分组内的顺序：emoji 前缀按 emojiRankOrder 倒序，相同再按开始、结束时间从早到晚，最后按标题
    func listOrder(_ a: EKEvent, _ b: EKEvent) -> Bool {
        let (rankA, rankB) = (emojiRank(a), emojiRank(b))
        if rankA != rankB { return rankA > rankB }
        if a.startDate != b.startDate { return a.startDate < b.startDate }
        if a.endDate != b.endDate { return a.endDate < b.endDate }
        return (a.title ?? "").localizedStandardCompare(b.title ?? "") == .orderedAscending
    }

    /// 取标题开头第一个 emoji（先状态、再优先级、再任意 emoji），不在列表里的「其他 emoji」排最大
    private func emojiRank(_ event: EKEvent) -> Int {
        let marked = marked(event)
        let leading = (event.title ?? "").first.flatMap { character -> String? in
            // 数字、# 等也带 isEmoji 属性，只认真正以图形显示的 emoji
            guard let scalar = character.unicodeScalars.first,
                  scalar.properties.isEmojiPresentation || character.unicodeScalars.count > 1 && scalar.properties.isEmoji
            else { return nil }
            return String(character)
        }
        let first = EmojiMarkers.normalized(marked.status ?? marked.priority ?? leading ?? EmojiMarkers.placeholder)
        return Self.emojiRankOrder.firstIndex(of: first) ?? Self.emojiRankOrder.count
    }
}
