#if DEBUG
import AppKit
import QuartzCore

/// 仅 Debug 版：用启动参数 `-debugBench resize` 程序化地把主窗口宽度从 1000 拖到 300 再拖回，
/// 统计每次改尺寸（含布局与绘制）的耗时，结果写到容器临时目录的 bench.txt，用来量化拖动是否跟手
enum DebugBench {
    /// 边栏右边缘的位置变化（时间, x），用来判断展开收起是否有逐帧动画
    static var sidebarWidths: [(Double, CGFloat)] = []

    /// 通用采样：(时间, 标签, 值)，用来判断某个位置变化是逐帧动画还是一步跳变
    static var samples: [(Double, String, CGFloat)] = []

    static func record(_ tag: String, _ value: CGFloat) {
        samples.append((CACurrentMediaTime(), tag, value))
    }

    static func writeSamples() {
        let start = samples.first?.0 ?? 0
        let lines = samples.map { String(format: "%.3fs %@ %.3f", $0.0 - start, $0.1, $0.2) }
        try? ("samples=\(samples.count)\n" + lines.joined(separator: "\n") + "\n").write(
            to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"), atomically: true, encoding: .utf8)
    }

    static func recordSidebar(_ maxX: CGFloat) {
        sidebarWidths.append((CACurrentMediaTime(), maxX))
    }

    static func writeSidebarReport() {
        let start = sidebarWidths.first?.0 ?? 0
        let lines = sidebarWidths.map { String(format: "%.3fs x=%.1f", $0.0 - start, $0.1) }
        let report = "samples=\(sidebarWidths.count)\n" + lines.joined(separator: "\n") + "\n"
        let url = FileManager.default.temporaryDirectory.appending(path: "bench.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    static func runIfRequested() {
        if UserDefaults.standard.string(forKey: "debugBench") == "newline" {
            // 配合 -debugEditFirst：编辑浮层打开后向焦点输入框投递回车，报告前后文字与选中范围（只改草稿，不存储）
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                // 浮层是独立的 NSPopover 窗口，不一定是 keyWindow，逐个窗口找焦点在文本框上的那个
                let window = NSApp.windows.first { $0.isVisible && $0.firstResponder is NSTextView }
                let keyInfo = "key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")"
                guard let window, let textView = window.firstResponder as? NSTextView,
                      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                   characters: "\r", charactersIgnoringModifiers: "\r",
                                                   isARepeat: false, keyCode: 36) else {
                    try? "no text view focused \(keyInfo) windows=\(NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) })\n".write(to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"),
                                                         atomically: true, encoding: .utf8)
                    return
                }
                let before = "\(keyInfo) window=\(type(of: window)) selection=\(textView.selectedRange()) length=\((textView.string as NSString).length)"
                NSApp.postEvent(event, atStart: false)
                try? await Task.sleep(for: .seconds(1))
                let after = "newlines=\(textView.string.filter(\.isNewline).count) length=\((textView.string as NSString).length) popoverOpen=\(textView.window != nil)"
                try? "\(before)\n\(after)\n".write(to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"),
                                                   atomically: true, encoding: .utf8)
            }
            return
        }
        if UserDefaults.standard.string(forKey: "debugBench") == "highlight" {
            // 启动 6 秒后报告各表格的选中高亮样式与选中行，屏幕锁定时也能验证
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                var lines: [String] = []
                func walk(_ view: NSView) {
                    if let table = view as? NSTableView {
                        lines.append("table rows=\(table.numberOfRows) style=\(table.selectionHighlightStyle.rawValue) selected=\(Array(table.selectedRowIndexes))")
                    }
                    view.subviews.forEach(walk)
                }
                NSApp.windows.compactMap(\.contentView).forEach(walk)
                try? (lines.joined(separator: "\n") + "\n").write(
                    to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"), atomically: true, encoding: .utf8)
            }
            return
        }
        if UserDefaults.standard.string(forKey: "debugBench") == "arrow" {
            // 启动 6 秒后向主窗口投递真实形态的 ⌘← 按键（带 .function、.numericPad），看日期是否前移一天
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
                      let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                   modifierFlags: [.command, .function, .numericPad],
                                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                   characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}",
                                                   isARepeat: false, keyCode: 123) else { return }
                let before = window.contentView?.subviews.isEmpty == false
                NSApp.postEvent(event, atStart: false)
                try? await Task.sleep(for: .seconds(1))
                try? "posted=\(before)\n".write(to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"),
                                                atomically: true, encoding: .utf8)
            }
            return
        }
        if UserDefaults.standard.string(forKey: "debugBench") == "responder" {
            // 启动 6 秒后记录主窗口的第一响应者，用来排查快捷键被文本框拦下的问题
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                let responder = NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?.firstResponder
                let report = "firstResponder=\(responder.map { String(describing: type(of: $0)) } ?? "nil")\n"
                try? report.write(to: FileManager.default.temporaryDirectory.appending(path: "bench.txt"),
                                  atomically: true, encoding: .utf8)
            }
            return
        }
        guard UserDefaults.standard.string(forKey: "debugBench") == "resize" else { return }
        Task { @MainActor in
            // 冷启动时窗口出现较慢
            var window: NSWindow?
            for _ in 0..<40 where window == nil {
                try? await Task.sleep(for: .milliseconds(250))
                window = NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
            }
            guard let window else { return }
            try? await Task.sleep(for: .seconds(1))
            var frame = window.frame
            let widths = Array(stride(from: 1000, through: 300, by: -10)) + Array(stride(from: 300, through: 1000, by: 10))
            var durations: [Double] = []
            for width in widths {
                frame.size.width = CGFloat(width)
                let start = CACurrentMediaTime()
                window.setFrame(frame, display: true)
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                durations.append((CACurrentMediaTime() - start) * 1000)
                // 让出主线程，模拟逐帧拖动
                try? await Task.sleep(for: .milliseconds(8))
            }
            let sorted = durations.sorted()
            let average = durations.reduce(0, +) / Double(durations.count)
            let report = String(format: "steps=%d avg=%.1fms p50=%.1fms p90=%.1fms max=%.1fms over16ms=%d\n",
                                durations.count, average, sorted[sorted.count / 2],
                                sorted[sorted.count * 9 / 10], sorted.last ?? 0,
                                durations.filter { $0 > 16 }.count)
            let url = FileManager.default.temporaryDirectory.appending(path: "bench.txt")
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif

#if DEBUG
import SwiftUI

/// 动画进度探针：动画期间 SwiftUI 每帧用插值后的 value 计算 body，记录下来即可得到真实的动画时长与曲线
struct AnimationProbe: View, Animatable {
    var value: Double
    let tag: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        DebugBench.record(tag, value)
        return Color.clear.frame(width: 0, height: 0)
    }
}
#endif
