import EventKit
import SwiftUI

struct SidebarView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        List {
            Section {
                SummaryCards()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.bottom, 8)
            }
            ForEach(store.calendarGroups, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        CalendarRow(calendar: calendar)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// 顶部彩色卡片：今天 / 全部日历
private struct SummaryCards: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                SummaryCard(title: "今天", systemImage: "calendar", tint: .blue,
                            count: store.todayCountSelected, isActive: store.isToday) {
                    store.goToday()
                }
                SummaryCard(title: "全部日历", systemImage: "tray.full.fill", tint: .gray,
                            count: store.dayEventsAllCalendars.count, isActive: store.allSelected) {
                    store.selectAll()
                }
            }
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title2)
                    Spacer()
                    Text(count, format: .number)
                        .font(.title.bold())
                        .contentTransition(.numericText())
                }
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.gradient.opacity(isActive ? 1 : 0.75),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 日历行：彩色圆点表示勾选状态，点击切换
private struct CalendarRow: View {
    @Environment(CalendarStore.self) private var store
    let calendar: EKCalendar

    var body: some View {
        let selected = store.isSelected(calendar)
        let color = Color(cgColor: calendar.cgColor)
        Button {
            store.toggle(calendar)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? color : .clear)
                    Circle()
                        .strokeBorder(color, lineWidth: 2)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                Text(calendar.title)
                    .lineLimit(1)
                Spacer()
                Text(store.count(for: calendar), format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
