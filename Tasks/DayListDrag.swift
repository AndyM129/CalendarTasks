import AppKit
import EventKit
import SwiftUI

/// 拖动日程改日期：拖到列表左右两侧的竖条区域往前 / 后移，停留会翻页。规则见 DayListView 的「拖动改日期」一节
struct RowDrag {
    let event: EKEvent
    /// 开始拖动时列表所在的日期
    let originDay: Date
    var location: CGPoint
    /// 指针所在区域：-1 左侧（前一天）、1 右侧（后一天）、0 中间
    var zone = 0
    /// 已翻页的天数（带方向），列表当前在 originDay + offset
    var offset = 0
    /// 本次停留距下一次翻页的计时起点与时长，画进度条用
    var tickStart = Date()
    var tickLength = 0.5

    /// 现在松手会移动的天数：在两侧还没翻过页时移 1 天，其余按已翻的天数
    var releaseDays: Int { zone != 0 && offset == 0 ? zone : offset }
}

/// 列表里各行的位置（相对列表视口）。用引用类型存，滚动时更新不触发列表重绘
@MainActor
final class RowFrames {
    var frames: [EKEvent: CGRect] = [:]

    func event(at point: CGPoint, among events: [EKEvent]) -> EKEvent? {
        events.first { frames[$0]?.contains(point) == true }
    }
}

/// 两侧的引导竖条：箭头 +「前一天 / 后一天」+ 目标日期，底部是距下一次翻页的进度条
struct DragZone: View {
    let direction: Int
    let target: Date
    let isActive: Bool
    let drag: RowDrag

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.title2.weight(.semibold))
            Text(direction < 0 ? "前一天" : "后一天")
                .font(.callout.weight(.medium))
            VStack(spacing: 2) {
                Text(target.formatted(.dateTime.month().day()))
                Text(target.formatted(.dateTime.weekday(.wide)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            progress
        }
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isActive ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.quaternary),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.secondary.opacity(isActive ? 0.5 : 0), lineWidth: 1)
        }
    }

    /// 只在指针停在这一侧时走
    private var progress: some View {
        TimelineView(.animation(paused: !isActive)) { context in
            let fraction = isActive ? min(max(context.date.timeIntervalSince(drag.tickStart) / drag.tickLength, 0), 1) : 0
            GeometryReader { proxy in
                Capsule().fill(.secondary.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.secondary).frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: 3)
            .padding(.horizontal, 6)
        }
    }
}

/// 列表底部的结果提示：松手后会移到哪天
struct DragResultCapsule: View {
    let drag: RowDrag

    var body: some View {
        Text(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }

    private var text: String {
        let days = drag.releaseDays
        guard days != 0,
              let target = Calendar.current.date(byAdding: .day, value: days, to: drag.event.startDate) else {
            return "拖到两侧改日期"
        }
        return "移至 \(target.formatted(.dateTime.month().day().weekday(.wide)))（\(days > 0 ? "+" : "")\(days) 天）"
    }
}

/// 跟着指针走的日程标题
struct DragGhost: View {
    let title: String

    var body: some View {
        Text(title.isEmpty ? "新日程" : title)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}

enum DragHaptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
