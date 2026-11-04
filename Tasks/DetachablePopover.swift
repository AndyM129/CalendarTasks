import AppKit
import SwiftUI

extension View {
    /// 可拖成独立窗口的浮层。SwiftUI 的 .popover 不支持拖出，这里直接用 NSPopover，
    /// popoverShouldDetach 返回 true 后，按住浮层往外拖就会变成独立窗口（系统日历的日程简介面板同款行为）
    /// content 收到一个 close 回调，面板保存或取消后调用它关闭（已拖成窗口时也能关）
    func detachablePopover<Content: View>(isPresented: Binding<Bool>, store: CalendarStore,
                                          @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Content) -> some View {
        background(DetachablePopoverAnchor(isPresented: isPresented, store: store, content: content))
    }
}

private struct DetachablePopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let store: CalendarStore
    let content: (_ close: @escaping () -> Void) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ anchor: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onClose = { isPresented = false }
        if isPresented, coordinator.popover == nil {
            // 等锚点挂进窗口后再弹出
            DispatchQueue.main.async {
                guard anchor.window != nil, coordinator.popover == nil else { return }
                let close: () -> Void = { [weak coordinator] in coordinator?.popover?.close() }
                coordinator.show(content: content(close).environment(store), relativeTo: anchor)
            }
        } else if !isPresented, let popover = coordinator.popover, !popover.isDetached {
            popover.close()
        }
    }

    /// 日程行被刷新掉时，已拖成窗口的面板继续保留；还贴在行上的随行关闭
    static func dismantleNSView(_ anchor: NSView, coordinator: Coordinator) {
        if let popover = coordinator.popover, !popover.isDetached { popover.close() }
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var popover: NSPopover?
        var onClose: (() -> Void)?

        func show<V: View>(content: V, relativeTo anchor: NSView) {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            let host = NSHostingController(rootView: content)
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            self.popover = popover
            OpenPopovers.all.insert(self)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        }

        func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            OpenPopovers.all.remove(self)
            onClose?()
        }
    }
}

/// 打开中的面板。日程行被刷新掉后，拖成窗口的面板要靠这里保活，关闭时移除（泛型类型里不能放静态存储属性）
@MainActor
private enum OpenPopovers {
    static var all: Set<NSObject> = []
}
