import SwiftUI

/// 设置（⌘,）：编辑状态序列与优先级序列
struct SettingsView: View {
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities

    var body: some View {
        Form {
            Section {
                MarkerField(title: "状态", text: $statusText, fallback: EmojiMarkers.defaultStatuses)
                MarkerField(title: "优先级", text: $priorityText, fallback: EmojiMarkers.defaultPriorities)
            } footer: {
                Text("识别日程标题开头的 emoji：先状态、后优先级，如「✅‼️写周报」。单击状态按序列顺序切换；无状态时显示 \(EmojiMarkers.placeholder)，点击写入第一个状态。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("恢复默认") {
                    statusText = EmojiMarkers.defaultStatuses
                    priorityText = EmojiMarkers.defaultPriorities
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MarkerField: View {
    let title: String
    @Binding var text: String
    let fallback: String

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(title, text: $text, prompt: Text(fallback))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                Text("序列：" + EmojiMarkers.items(text, fallback: fallback).joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
