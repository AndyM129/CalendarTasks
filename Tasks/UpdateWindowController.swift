import AppKit

/// 「软件更新」窗口，排版参考 FinderWand：左侧 App 图标，右侧标题、版本对比、更新说明卡片，
/// 底部左侧显示进度与结果，右侧「查看发布页」「稍后」「下载并安装」。
/// 沙箱内不能自己替换 /Applications，「下载并安装」会下载校验后在访达打开安装包，由用户拖进「应用程序」。
final class UpdateWindowController: NSObject, NSWindowDelegate {
    /// 当前打开的窗口；同一版本再次检查时置前，换了版本则重建
    private static var current: UpdateWindowController?

    static func show(_ update: UpdateInfo) {
        if let current = current {
            if current.update.version == update.version && !(current.update.notes.isEmpty && !update.notes.isEmpty) {
                current.bringToFront()
                return
            }
            current.window?.close()
        }

        let controller = UpdateWindowController(update: update)
        current = controller
        controller.present()
    }

    private let update: UpdateInfo
    private var window: NSWindow?

    private let installButton = NSButton(title: "下载并安装", target: nil, action: nil)
    private let laterButton = NSButton(title: "稍后", target: nil, action: nil)
    private let pageButton = NSButton(title: "查看发布页", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var notesScrollView: NSScrollView?

    /// 右侧内容宽度
    private let contentWidth: CGFloat = 400

    private init(update: UpdateInfo) {
        self.update = update
        super.init()
    }

    private func present() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = Self.label("\(AppInfo.name) 有新版本可用", font: .boldSystemFont(ofSize: 15))
        let subtitle = Self.label("v\(update.version) 已发布，当前版本为 v\(AppInfo.version)。",
                                  font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        let right = NSStackView(views: [title, subtitle])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 4
        right.setCustomSpacing(14, after: subtitle)
        right.addArrangedSubview(Self.label("更新说明", font: .boldSystemFont(ofSize: 12)))
        right.addArrangedSubview(notesView())

        let top = NSStackView(views: [icon, right])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 16

        let root = NSStackView(views: [top, buttonRow()])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "软件更新"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = container
        window.defaultButtonCell = installButton.cell as? NSButtonCell
        window.setContentSize(container.fittingSize)
        window.center()
        self.window = window

        // 更新说明从顶部开始显示
        if let scroll = notesScrollView {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        bringToFront()
    }

    // MARK: - 视图

    /// 更新说明：按内容高度显示，最高 240pt，超出可滚动；去掉 GitHub 自动附加的「Full Changelog」行
    private func notesView() -> NSView {
        let markdown = ReleaseNotesRenderer.removingChangelogLink(update.notes)
        let text = markdown.isEmpty
            ? NSAttributedString(string: "这个版本没有填写更新说明，可在发布页查看。",
                                 attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            : ReleaseNotesRenderer.attributedString(markdown: markdown)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 10))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(text)
        var used: CGFloat = 40
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            used = layout.usedRect(for: container).height
        }
        let height = min(max(used + 16, 44), 240)
        textView.frame.size.height = max(used + 16, height)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = used + 16 > 240
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        notesScrollView = scroll

        // 圆角浅底卡片（NSBox 的颜色随深浅色自动适配）
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .quaternaryLabelColor.withAlphaComponent(0.06)
        box.contentViewMargins = .zero
        box.titlePosition = .noTitle
        box.contentView = scroll
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        box.heightAnchor.constraint(equalToConstant: height).isActive = true
        return box
    }

    /// 底部：左侧进度与结果，右侧「查看发布页」「稍后」「下载并安装」
    private func buttonRow() -> NSView {
        for (button, action) in [(installButton, #selector(install)), (laterButton, #selector(later)), (pageButton, #selector(openPage))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        installButton.keyEquivalent = "\r"
        laterButton.keyEquivalent = "\u{1b}"
        if update.downloadURL == nil {
            installButton.isEnabled = false
            installButton.toolTip = "该版本没有提供安装包，请到发布页下载。"
        }

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = 220
        statusLabel.isHidden = true

        let status = NSStackView(views: [spinner, statusLabel])
        status.orientation = .horizontal
        status.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [status, spacer, pageButton, laterButton, installButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 64 + 16 + contentWidth).isActive = true
        return row
    }

    // MARK: - 动作

    @objc private func install() {
        setBusy(true, status: "正在下载并校验 v\(update.version)…")
        UpdateInstaller.shared.prepare(update) { [weak self] failure in
            guard let self = self else { return }

            if failure.isEmpty {
                self.setBusy(false, status: "已在访达中打开安装包，把 \(AppInfo.name) 拖进「应用程序」替换后重新打开。")
            } else {
                self.setBusy(false, status: "更新失败：\(failure)", isError: true)
            }
        }
    }

    @objc private func later() {
        window?.close()
    }

    @objc private func openPage() {
        NSWorkspace.shared.open(update.pageURL)
    }

    private func setBusy(_ busy: Bool, status: String, isError: Bool = false) {
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        statusLabel.stringValue = status
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.isHidden = false
        installButton.isEnabled = !busy && update.downloadURL != nil
        laterButton.isEnabled = !busy
        window?.standardWindowButton(.closeButton)?.isEnabled = !busy
        if let container = window?.contentView {
            window?.setContentSize(container.fittingSize)
        }
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }

    private static func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }
}
