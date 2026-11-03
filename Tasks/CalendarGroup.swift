import SwiftUI

/// 日历组合：把任意多个日历保存为一组，选中即勾选这些日历
struct CalendarGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var tint: Tint
    var calendarIDs: Set<String>

    enum Tint: String, Codable, CaseIterable, Identifiable {
        case red, orange, yellow, green, mint, blue, indigo, purple, pink, gray

        var id: Self { self }

        var color: Color {
            switch self {
            case .red: .red
            case .orange: .orange
            case .yellow: .yellow
            case .green: .green
            case .mint: .mint
            case .blue: .blue
            case .indigo: .indigo
            case .purple: .purple
            case .pink: .pink
            case .gray: .gray
            }
        }
    }
}
