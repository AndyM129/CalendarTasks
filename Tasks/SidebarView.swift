import EventKit
import SwiftUI

struct SidebarView: View {
    @Environment(CalendarStore.self) private var store
    /// 正在编辑的组合；新建时为空名的新组合
    @State private var editingGroup: CalendarGroup?
    @State private var deletingGroup: CalendarGroup?
    /// 已收起的账户，换行分隔存 UserDefaults
    @AppStorage("collapsedSources") private var savedCollapsedSources = ""
    /// 同 DayListView：用 @State 驱动界面，折叠才有动画
    @State private var collapsedSourcesText = UserDefaults.standard.string(forKey: "collapsedSources") ?? ""

    private var collapsedSources: Set<String> {
        Set(collapsedSourcesText.split(separator: "\n").map(String.init))
    }

    /// 分区标题：小号灰字，右侧放 + 或折叠箭头，与下方各行的计数右对齐
    private func sectionHeader<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            accessory()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func toggleSource(_ source: String) {
        var sources = collapsedSources
        if sources.remove(source) == nil { sources.insert(source) }
        collapsedSourcesText = sources.sorted().joined(separator: "\n")
    }

    var body: some View {
        // 用 ScrollView + LazyVStack 而不是 List：List 底层表格增删行一步完成，账户分组折叠没有过渡动画（与日程列表同因）
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SummaryCards()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                sectionHeader("日历组合") {
                    Button("新建日历组合", systemImage: "plus") {
                        editingGroup = CalendarGroup(name: "", tint: .blue,
                                                     calendarIDs: store.selectedCalendarIDs)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                ForEach(store.groups) { group in
                    GroupRow(group: group)
                        .contextMenu {
                            Button("编辑…") { editingGroup = group }
                            Button("删除…", role: .destructive) { deletingGroup = group }
                        }
                        .transition(.opacity)
                }
                ForEach(store.calendarGroups, id: \.source) { group in
                    let expanded = !collapsedSources.contains(group.source)
                    Button {
                        withAnimation(.ui) { toggleSource(group.source) }
                    } label: {
                        sectionHeader(group.source) {
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 0 : -90))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "收起" : "展开")
                    // 内容单独裁切，收起时向上滑出、不盖住账户标题
                    VStack(spacing: 0) {
                        if expanded {
                            VStack(spacing: 0) {
                                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                                    CalendarRow(calendar: calendar)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .clipped()
                }
            }
            .padding(.vertical, 8)
        }
        #if DEBUG
        // 验证用：-debugBench sourceCollapse，先展开第一个账户，再用 3 秒慢动画收起并写标记文件，外部中途截屏
        .task {
            guard UserDefaults.standard.string(forKey: "debugBench") == "sourceCollapse",
                  let source = store.calendarGroups.first?.source else { return }
            try? await Task.sleep(for: .seconds(4))
            if collapsedSources.contains(source) { toggleSource(source) }
            try? await Task.sleep(for: .seconds(1))
            try? "start\n".write(to: FileManager.default.temporaryDirectory.appending(path: "collapse-start"),
                                 atomically: true, encoding: .utf8)
            withAnimation(.linear(duration: 3)) { toggleSource(source) }
        }
        #endif
        .onChange(of: collapsedSourcesText) { _, text in savedCollapsedSources = text }
        .animation(.ui, value: store.revision)
        .animation(.ui, value: store.groups)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        .padding(.horizontal, 10)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
