import Foundation

/// 标题开头的状态 / 优先级 emoji 配置，序列存 UserDefaults
enum EmojiMarkers {
    static let statusKey = "statusEmojis"
    static let priorityKey = "priorityEmojis"
    static let defaultStatuses = "⬜️✅❎"
    static let defaultPriorities = "❗️‼️"
    /// 标题开头没有状态 emoji 时显示的占位
    static let placeholder = "ℹ️"

    /// 把设置里的文本拆成 emoji 序列：每个字符一项，忽略空白与逗号，去重；为空时用默认值
    static func items(_ text: String, fallback: String) -> [String] {
        let parsed = parse(text)
        return parsed.isEmpty ? parse(fallback) : parsed
    }

    private static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .filter { !$0.isWhitespace && $0 != "," && $0 != "，" }
            .map(String.init)
            .filter { seen.insert(normalized($0)).inserted }
    }

    /// 比较时忽略变体选择符 U+FE0F，「⬜」与「⬜️」视为同一个
    static func normalized(_ emoji: String) -> String {
        emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
    }
}

/// 拆分后的日程标题：状态 + 优先级 + 正文
struct MarkedTitle: Equatable {
    var status: String?
    var priority: String?
    var text: String

    init(_ title: String, statuses: [String], priorities: [String]) {
        var rest = Substring(title)
        // 开头最多各识别一个状态、一个优先级，顺序不限
        for _ in 0..<2 {
            guard let first = rest.first.map(String.init) else { break }
            if status == nil, let match = Self.match(first, in: statuses) {
                status = match
            } else if priority == nil, let match = Self.match(first, in: priorities) {
                priority = match
            } else {
                break
            }
            rest = rest.dropFirst()
        }
        text = String(rest)
    }

    /// 写回日历的标题，统一为「状态 + 优先级 + 正文」
    var title: String { (status ?? "") + (priority ?? "") + text }

    /// 返回配置里的写法，写回时统一 emoji 形式
    private static func match(_ character: String, in items: [String]) -> String? {
        let key = EmojiMarkers.normalized(character)
        return items.first { EmojiMarkers.normalized($0) == key }
    }
}
