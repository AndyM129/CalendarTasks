import AppKit
import SwiftUI

/// 关掉 SwiftUI List 底层 NSTableView 的系统选中高亮（强调色蓝底），选中背景改由 listRowBackground 自绘。
/// 放在任意一行的 background 里即可，会沿视图层级向上找到所属的表格
struct SystemSelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // 刚创建时还没挂进表格，下一轮再找
        DispatchQueue.main.async {
            var current = view.superview
            while let next = current, !(next is NSTableView) { current = next.superview }
            if let table = current as? NSTableView, table.selectionHighlightStyle != .none {
                table.selectionHighlightStyle = .none
            }
        }
    }
}
