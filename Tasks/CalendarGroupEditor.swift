import EventKit
import SwiftUI

/// 新建 / 编辑日历组合：名称、颜色、所含日历
struct CalendarGroupEditor: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CalendarGroup
    private let isNew: Bool

    init(group: CalendarGroup) {
        _draft = State(initialValue: group)
        isNew = group.name.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "新建日历组合" : "编辑日历组合")
                .font(.headline)

            TextField("名称", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(CalendarGroup.Tint.allCases) { tint in
                    Button {
                        draft.tint = tint
                    } label: {
                        Circle()
                            .fill(tint.color.gradient)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if draft.tint == tint {
                                    Circle().strokeBorder(.primary, lineWidth: 2).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tint.rawValue)
                }
            }

            List {
                ForEach(store.calendarGroups, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: binding(for: calendar)) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(cgColor: calendar.cgColor))
                                        .frame(width: 10, height: 10)
                                    Text(calendar.title)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 260)

            HStack {
                Text("已选 \(store.validIDs(of: draft).count) 个日历")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("存储") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.saveGroup(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.validIDs(of: draft).isEmpty
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { draft.calendarIDs.contains(calendar.calendarIdentifier) },
            set: { isOn in
                if isOn {
                    draft.calendarIDs.insert(calendar.calendarIdentifier)
                } else {
                    draft.calendarIDs.remove(calendar.calendarIdentifier)
                }
            }
        )
    }
}
