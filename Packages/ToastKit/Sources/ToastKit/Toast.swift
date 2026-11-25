import SwiftUI

/// 一条提示：图标 + 文案，可带一个操作按钮（如「撤销」）
@MainActor
public struct Toast: Identifiable {
    public enum Kind: Sendable {
        case info, success, error

        public var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        public var tint: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .error: .red
            }
        }
    }

    public struct Action {
        public let title: String
        public let handler: @MainActor () -> Void

        public init(_ title: String, handler: @escaping @MainActor () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    public let id = UUID()
    public let message: String
    public let kind: Kind
    /// 默认用 kind 对应的 SF Symbol，传 nil 不显示图标
    public let systemImage: String?
    public let action: Action?
    /// 显示时长；指针悬停在提示上时暂停计时，移开后重新计时
    public let duration: Duration

    public init(_ message: String, kind: Kind = .info, systemImage: String? = "",
                action: Action? = nil, duration: Duration? = nil) {
        self.message = message
        self.kind = kind
        self.systemImage = systemImage == "" ? kind.systemImage : systemImage
        self.action = action
        // 出错提示多留一会儿，方便看完
        self.duration = duration ?? (kind == .error ? .seconds(5) : .seconds(3))
    }
}

/// 管理当前显示的提示。同一时间只显示一条，新提示直接顶替旧的（连续操作时只看最新结果）
@MainActor
@Observable
public final class ToastCenter {
    public private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ toast: Toast) {
        current = toast
        scheduleDismiss()
    }

    public func show(_ message: String, kind: Toast.Kind = .info, action: Toast.Action? = nil) {
        show(Toast(message, kind: kind, action: action))
    }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    func pause() {
        dismissTask?.cancel()
    }

    func resume() {
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard let toast = current else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: toast.duration)
            guard !Task.isCancelled, let self, self.current?.id == toast.id else { return }
            self.current = nil
        }
    }
}
