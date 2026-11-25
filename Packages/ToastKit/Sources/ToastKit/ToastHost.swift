import SwiftUI

public extension View {
    /// 在当前视图上显示 center 里的提示，默认贴底部居中
    func toastHost(_ center: ToastCenter, alignment: Alignment = .bottom, padding: CGFloat = 16,
                   animation: Animation = .smooth(duration: 0.25)) -> some View {
        modifier(ToastHost(center: center, alignment: alignment, padding: padding, animation: animation))
    }
}

private struct ToastHost: ViewModifier {
    let center: ToastCenter
    let alignment: Alignment
    let padding: CGFloat
    let animation: Animation
    @Environment(\.toastStyle) private var style

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            ZStack {
                if let toast = center.current {
                    (style ?? AnyToastStyle(GlassToastStyle())).make(ToastStyleConfiguration(
                        toast: toast,
                        performAction: { [center] in
                            toast.action?.handler()
                            center.dismiss()
                        },
                        dismiss: { [center] in center.dismiss() }
                    ))
                    .onHover { [center] hovering in hovering ? center.pause() : center.resume() }
                    .padding(padding)
                    .transition(.move(edge: alignment.vertical == .top ? .top : .bottom).combined(with: .opacity))
                    .id(toast.id)
                }
            }
            .animation(animation, value: center.current?.id)
        }
    }
}
