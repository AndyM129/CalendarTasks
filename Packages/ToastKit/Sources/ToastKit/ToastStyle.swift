import SwiftUI

/// 提示的外观，参照 ButtonStyle 的写法：实现 makeBody，再用 `.toastStyle(_:)` 套到界面上
@MainActor
public protocol ToastStyle {
    associatedtype Body: View
    typealias Configuration = ToastStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

@MainActor
public struct ToastStyleConfiguration {
    public let toast: Toast
    /// 执行提示上的操作并关闭提示
    public let performAction: () -> Void
    public let dismiss: () -> Void
}

/// 默认外观：胶囊形，macOS 26 / iOS 26 起用 Liquid Glass，之前的系统用材质背景
public struct GlassToastStyle: ToastStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let toast = configuration.toast
        HStack(spacing: 8) {
            if let symbol = toast.systemImage {
                Image(systemName: symbol)
                    .foregroundStyle(toast.kind.tint)
            }
            Text(toast.message)
                .lineLimit(2)
            if let action = toast.action {
                Button(action.title, action: configuration.performAction)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(CapsuleBackground())
    }
}

private struct CapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}

@MainActor
struct AnyToastStyle {
    let make: (ToastStyleConfiguration) -> AnyView

    init<S: ToastStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }
}

/// 环境里存可选值：默认值在非主线程上下文里构造，不能直接建 GlassToastStyle，没设时由 ToastHost 回落到它
private struct ToastStyleKey: EnvironmentKey {
    static let defaultValue: AnyToastStyle? = nil
}

extension EnvironmentValues {
    var toastStyle: AnyToastStyle? {
        get { self[ToastStyleKey.self] }
        set { self[ToastStyleKey.self] = newValue }
    }
}

public extension View {
    func toastStyle<S: ToastStyle>(_ style: S) -> some View {
        environment(\.toastStyle, AnyToastStyle(style))
    }
}
