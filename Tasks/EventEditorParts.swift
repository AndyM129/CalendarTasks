import AppKit
import EventKit
import SwiftUI

/// 编辑面板里的圆角卡片，样式参照系统日历的日程简介面板
struct EditorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 标题右侧的日历选择：显示当前日历的颜色圆点，点开列出可编辑的日历
struct CalendarColorMenu: View {
    @Environment(CalendarStore.self) private var store
    @Binding var calendarID: String

    var body: some View {
        Menu {
            ForEach(store.calendarGroups, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) { calendar in
                        Button {
                            calendarID = calendar.calendarIdentifier
                        } label: {
                            Label { Text(calendar.title) } icon: { Image(nsImage: Self.dot(calendar.color)) }
                        }
                    }
                }
            }
        } label: {
            Image(nsImage: Self.dot(currentColor))
        }
        .menuStyle(.button)
        .fixedSize()
        .help(store.calendars.first { $0.calendarIdentifier == calendarID }?.title ?? "日历")
    }

    private var currentColor: NSColor {
        store.calendars.first { $0.calendarIdentifier == calendarID }?.color ?? .gray
    }

    /// 菜单项里只能稳定显示图片，用实心圆图片表示日历颜色
    static func dot(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// 自定义重复：每 N 天/周/月/年，按周时选星期几
struct CustomRepeatEditor: View {
    @Binding var draft: RepeatDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("每")
                TextField("", value: $draft.interval, format: .number)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                Stepper("", value: $draft.interval, in: 1...99)
                    .labelsHidden()
                Picker("", selection: $draft.unit) {
                    ForEach(RepeatDraft.Unit.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if draft.unit == .week {
                HStack(spacing: 4) {
                    ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                        let selected = draft.weekdays.contains(weekday)
                        Button {
                            if selected, draft.weekdays.count > 1 {
                                draft.weekdays.remove(weekday)
                            } else {
                                draft.weekdays.insert(weekday)
                            }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                .frame(width: 26, height: 26)
                                .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if draft.hasUnsupportedDetails {
                Text("原规则包含这里无法显示的细节，修改后会被覆盖。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 按系统的一周首日排列（1 = 周日 … 7 = 周六）
    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

/// 结束重复：永不 / 于某日期 / 重复 N 次
struct RepeatEndEditor: View {
    @Binding var end: RepeatDraft.End
    let start: Date

    private enum Kind: Hashable { case never, date, count }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: kind) {
                Text("永不").tag(Kind.never)
                Text("于日期").tag(Kind.date)
                Text("重复次数").tag(Kind.count)
            }
            .labelsHidden()
            .fixedSize()
            switch end {
            case .never:
                EmptyView()
            case .onDate(let date):
                DatePicker("", selection: Binding(get: { date }, set: { end = .onDate($0) }),
                           in: start..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            case .afterCount(let count):
                Stepper("\(count) 次", value: Binding(get: { count }, set: { end = .afterCount($0) }), in: 1...999)
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch end {
                case .never: .never
                case .onDate: .date
                case .afterCount: .count
                }
            },
            set: { kind in
                switch kind {
                case .never: end = .never
                case .date: end = .onDate(Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start)
                case .count: end = .afterCount(10)
                }
            }
        )
    }
}
