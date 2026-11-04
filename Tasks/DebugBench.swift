#if DEBUG
import AppKit
import QuartzCore

/// 仅 Debug 版：用启动参数 `-debugBench resize` 程序化地把主窗口宽度从 1000 拖到 300 再拖回，
/// 统计每次改尺寸（含布局与绘制）的耗时，结果写到容器临时目录的 bench.txt，用来量化拖动是否跟手
enum DebugBench {
    /// 边栏右边缘的位置变化（时间, x），用来判断展开收起是否有逐帧动画
    static var sidebarWidths: [(Double, CGFloat)] = []

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
