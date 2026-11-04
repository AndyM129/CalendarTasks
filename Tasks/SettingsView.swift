import SwiftUI

/// 设置（⌘,）：编辑状态序列与优先级序列、界面动画时长
struct SettingsView: View {
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities
    @AppStorage(Animation.durationKey) private var animationDuration = Animation.defaultDuration

    var body: some View {
        Form {
            Section {
                MarkerField(title: "状态", text: $statusText, fallback: EmojiMarkers.defaultStatuses)
                MarkerField(title: "优先级", text: $priorityText, fallback: EmojiMarkers.defaultPriorities)
            } footer: {
                Text("识别日程标题开头的 emoji：先状态、后优先级，如「✅‼️写周报」。点击状态弹出可选项，点选后切换；无状态时显示 \(EmojiMarkers.placeholder)。")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("动画时长") {
                    HStack {
                        Slider(value: $animationDuration, in: 0.1...1.0, step: 0.05)
                            .frame(width: 180)
                        Text(String(format: "%.2f 秒", animationDuration))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            } footer: {
                Text("分组折叠、新增删除、浮动边栏等界面过渡使用无回弹的平滑弹簧曲线（与 iOS 页面 push 同类）。边栏两栏模式的展开收起、浮层弹出由系统控制，不受此设置影响。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("恢复默认") {
                    statusText = EmojiMarkers.defaultStatuses
                    priorityText = EmojiMarkers.defaultPriorities
                    animationDuration = Animation.defaultDuration
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
