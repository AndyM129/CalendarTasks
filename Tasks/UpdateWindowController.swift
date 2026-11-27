import SwiftUI

/// 软件更新窗口：显示新版本与更新说明，可下载并打开安装包，或先去 Release 页看
enum UpdateWindowController {
    private static var window: NSWindow?

    @MainActor
    static func show(_ update: UpdateInfo) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "软件更新"
        window.contentView = NSHostingView(rootView: UpdateView(update: update))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct UpdateView: View {
    let update: UpdateInfo
    @State private var isWorking = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("新版本 v\(update.version)")
                    .font(.title3.bold())
                Text("当前 v\(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(update.notes.isEmpty ? "（作者没写更新说明）" : update.notes)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .border(.quaternary)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button(isWorking ? "准备中…" : "下载并打开安装包") { prepare() }
                    .disabled(isWorking)
                Button("打开发布页") { NSWorkspace.shared.open(update.pageURL) }
                Spacer()
                Button("稍后") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }

    private func prepare() {
        isWorking = true
        message = ""

        UpdateInstaller.shared.prepare(update) { failure in
            isWorking = false
            if failure.isEmpty {
                message = "已在访达中打开安装包，把 \(AppInfo.name) 拖进「应用程序」替换，再重新打开即可。"
            } else {
                message = failure
            }
        }
    }
}