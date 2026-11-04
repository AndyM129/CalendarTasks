import EventKit
import SwiftUI

struct SidebarView: View {
    @Environment(CalendarStore.self) private var store
    /// 正在编辑的组合；新建时为空名的新组合
    @State private var editingGroup: CalendarGroup?
    @State private var deletingGroup: CalendarGroup?
    /// 已收起的账户，换行分隔存 UserDefaults
    @AppStorage("collapsedSources") private var collapsedSourcesText = ""
    /// 分区标题右侧图标与下方行内计数右对齐所需的内缩
    private static let headerTrailingInset: CGFloat = 10

    private var collapsedSources: Set<String> {
        Set(collapsedSourcesText.split(separator: "\n").map(String.init))
    }

    private func toggleSource(_ source: String) {
        var sources = collapsedSources
        if sources.remove(source) == nil { sources.insert(source) }
        collapsedSourcesText = sources.sorted().joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                SummaryCards()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.bottom, 8)
            }
            Section {
                ForEach(store.groups) { group in
                    GroupRow(group: group)
                        .contextMenu {
                            Button("编辑…") { editingGroup = group }
                            Button("删除…", role: .destructive) { deletingGroup = group }
                        }
                }
            } header: {
                HStack {
                    Text("日历组合")
                    Spacer()
                    Button("新建日历组合", systemImage: "plus") {
                        editingGroup = CalendarGroup(name: "", tint: .blue,
                                                     calendarIDs: store.selectedCalendarIDs)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                .padding(.trailing, Self.headerTrailingInset)
            }
            ForEach(store.calendarGroups, id: \.source) { group in
                let expanded = !collapsedSources.contains(group.source)
                Section {
                    if expanded {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            CalendarRow(calendar: calendar)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy) { toggleSource(group.source) }
                    } label: {
                        HStack {
                            Text(group.source)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 0 : -90))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, Self.headerTrailingInset)
                    .help(expanded ? "收起" : "展开")
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.snappy, value: store.revision)
        .animation(.snappy, value: store.groups)
        .sheet(item: $editingGroup) { group in
            CalendarGroupEditor(group: group)
        }
        .confirmationDialog("删除日历组合「\(deletingGroup?.name ?? "")」？",
                            isPresented: Binding(get: { deletingGroup != nil },
                                                 set: { if !$0 { deletingGroup = nil } }),
                            presenting: deletingGroup) { group in
            Button("删除", role: .destructive) { store.deleteGroup(group) }
        } message: { _ in
            Text("只删除组合，不影响其中的日历和日程。")
        }
    }
}

/// 日历组合行：勾选恰好等于组合时高亮
private struct GroupRow: View {
    @Environment(CalendarStore.self) private var store
    let group: CalendarGroup

    var body: some View {
        let active = store.isActive(group)
        Button {
            store.apply(group)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(group.tint.color.gradient, in: Circle())
                Text(group.name)
                    .lineLimit(1)
                    .foregroundStyle(active ? Color.accentColor : .primary)
                Spacer()
                Text(store.count(for: group), format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                .padding(.horizontal, 8)
        )
        .accessibilityAddTraits(active ? .isSelected : [])
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
