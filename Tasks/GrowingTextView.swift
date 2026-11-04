import AppKit
import SwiftUI

/// 自适应高度的多行输入框（NSTextView 封装）：随内容变高，超过 maxLines 后在框内滚动。
/// 系统 TextField(axis: .vertical) 按回车会结束编辑并全选，不能换行，所以改用 NSTextView。
/// - returnSubmits 为 nil 时回车换行；不为 nil 时回车提交，⌥↩ 换行
/// - focusOnAppear 为 true 时出现即获得焦点，光标放在末尾（不全选）
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var maxLines = 5
    var focusOnAppear = false
    var returnSubmits: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEndEditing: (() -> Void)?

    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        if focusOnAppear {
            // 放在 NSPopover 里时，创建视图那一刻还没挂进窗口，等挂进窗口后再取焦点
            focusWhenInWindow(textView, attempts: 20)
        }
        return scrollView
    }

    /// 光标放在末尾，不全选
    private func focusWhenInWindow(_ textView: NSTextView, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = textView.window else {
                if attempts > 0 { focusWhenInWindow(textView, attempts: attempts - 1) }
                return
            }
            window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    /// 按给定宽度排版后取内容高度，限制在 1 行到 maxLines 行之间
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView,
              let container = textView.textContainer, let layout = textView.layoutManager else { return nil }
        let width = proposal.width ?? 240
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lineHeight = layout.defaultLineHeight(for: Self.font)
        let used = layout.usedRect(for: container).height
        let height = min(max(used, lineHeight), lineHeight * CGFloat(maxLines))
        return CGSize(width: width, height: ceil(height))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing?()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard let submit = parent.returnSubmits else { return false }
                submit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard let cancel = parent.onCancel else { return false }
                cancel()
                return true
            default:
                return false
            }
        }
    }
}

extension GrowingTextView {
    /// 内容为空时显示的占位文字，不拦截点击
    func placeholderOverlay() -> some View {
        overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Font(Self.font))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
    }
}
