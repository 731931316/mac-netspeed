import AppKit
import NetSpeedSettings
import OSLog

/// Presents native preferences without giving the menu-bar application a Dock icon.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Shares the same refresh preference object with the status menu and scheduler.
    private let preferences: RefreshPreferences
    /// Reflects actual system login state through a real or explicitly read-only service.
    private let loginItems: LoginItemController
    /// Notifies the application after the user saves an approved refresh interval.
    private let onIntervalChanged: @MainActor () -> Void
    /// Prevents diagnostic controls from writing the user's real refresh preference.
    private let allowsPreferenceChanges: Bool
    /// Records settings lifecycle and user actions through the common subsystem.
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "SettingsWindow")
    /// Displays the bundled cat icon, with a native fallback for unbundled development.
    private let iconView = NSImageView()
    /// Presents the Chinese application identity beside its icon.
    private let nameLabel = NSTextField(labelWithString: "速喵")
    /// Offers the approved intervals without keeping a second preference store.
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// Requests login-item changes only when the user clicks this control.
    private let loginCheckbox = NSButton(checkboxWithTitle: "开机启动", target: nil, action: nil)
    /// Separately explains that startup occurs after logging into macOS.
    private let loginCaption = NSTextField(wrappingLabelWithString: "登录 macOS 后自动启动速喵")
    /// Describes the actual system state independently of the checkbox appearance.
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    /// Explains why a registered login item may still need user approval.
    private let approvalLabel = NSTextField(wrappingLabelWithString: "请在系统设置中允许速喵登录时启动。批准后将在下次登录时生效。")
    /// Opens the official login-items pane only after an explicit user click.
    private let approvalButton = NSButton(title: "打开系统登录项设置", target: nil, action: nil)
    /// Shows sanitized Chinese operation errors supplied by the settings controller.
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    /// Retains one pending user operation to prevent duplicate checkbox actions.
    private var loginChangeTask: Task<Void, Never>?
    /// Records successful decoding of the real bundled icon for smoke evidence.
    private var hasBundledIcon = false
    /// Supplies the actual fitting height so approval and error rows cannot compress away.
    private var contentStack: NSStackView?

    /// Constructs the settings view without showing it or mutating system login items.
    init(
        preferences: RefreshPreferences,
        loginItems: LoginItemController,
        allowsPreferenceChanges: Bool,
        onIntervalChanged: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.loginItems = loginItems
        self.allowsPreferenceChanges = allowsPreferenceChanges
        self.onIntervalChanged = onIntervalChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "速喵设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        loginItems.onChange = { [weak self] in
            self?.synchronizeControls()
        }
        synchronizeControls()
        window.center()
        logger.debug("已构造速喵设置窗口")
    }

    /// Rejects storyboard decoding because the native settings are constructed in code.
    required init?(coder: NSCoder) {
        return nil
    }

    /// Shows and activates the preferences window only in response to a user request.
    func present() {
        refreshSystemStatus()
        showWindow(nil)
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        logger.info("用户已打开速喵设置")
    }

    /// Refreshes real system status after reopening or returning from System Settings.
    func refreshSystemStatus() {
        loginItems.refresh()
        synchronizeControls()
    }

    /// Synchronizes the interval selection after either settings or menu changes it.
    func synchronizePreferences() {
        if let index = RefreshPreferences.supportedIntervals.firstIndex(of: preferences.interval) {
            intervalPopup.selectItem(at: index)
        }
    }

    /// Reads external login-item changes when the user focuses the settings window.
    func windowDidBecomeKey(_ notification: Notification) {
        refreshSystemStatus()
    }

    /// Releases callbacks and hides the settings window during application shutdown.
    func tearDown() {
        loginItems.onChange = nil
        loginChangeTask?.cancel()
        loginChangeTask = nil
        close()
    }

    /// Reports a stable non-identifying representation of the actual login status.
    var diagnosticLoginItemStatus: String {
        switch loginItems.status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .unavailable: "unavailable"
        }
    }

    /// Exposes capability evidence without exposing the mutable service itself.
    var supportsLoginItemChanges: Bool { loginItems.supportsChanges }

    /// Provides bounded smoke evidence without showing the window or performing writes.
    func smokeChecks() -> [String: Bool] {
        // Move only the offscreen UI selection, then verify that it follows the shared model.
        let currentInterval = preferences.interval
        let alternateIndex = RefreshPreferences.supportedIntervals.firstIndex(where: { $0 != currentInterval }) ?? 0
        intervalPopup.selectItem(at: alternateIndex)
        synchronizePreferences()
        let expectedIndex = RefreshPreferences.supportedIntervals.firstIndex(of: currentInterval)
        let expectedCheckbox: NSControl.StateValue = loginItems.status == .requiresApproval
            ? .mixed : (loginItems.status == .enabled ? .on : .off)
        let contentFits = contentStack.map { stack in
            window?.contentView?.bounds.contains(stack.frame) == true
        } ?? false
        return [
            "settingsConstruction": window?.contentView != nil && window?.isVisible == false
                && contentFits
                && window?.title == "速喵设置" && nameLabel.stringValue == "速喵"
                && intervalPopup.numberOfItems == RefreshPreferences.supportedIntervals.count
                && intervalPopup.action == #selector(intervalChanged(_:))
                && loginCheckbox.action == #selector(loginItemChanged(_:))
                && approvalButton.action == #selector(openSystemSettings(_:)),
            "refreshPreferenceSync": intervalPopup.indexOfSelectedItem == expectedIndex
                && !allowsPreferenceChanges && !intervalPopup.isEnabled,
            "loginItemReadOnly": !loginItems.supportsChanges && !loginCheckbox.isEnabled
                && !approvalButton.isEnabled,
            "loginItemStatusMapped": statusLabel.stringValue.contains(loginItems.status.description)
                && loginCheckbox.state == expectedCheckbox
                && ["notRegistered", "enabled", "requiresApproval", "unavailable"].contains(diagnosticLoginItemStatus),
            "applicationIcon": hasBundledIcon
        ]
    }

    /// Builds a compact native preferences view with explicit approval and error text.
    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
        nameLabel.font = .systemFont(ofSize: 23, weight: .semibold)
        let description = NSTextField(labelWithString: "菜单栏实时上传与下载速度")
        description.textColor = .secondaryLabelColor
        let headingText = verticalStack([nameLabel, description], spacing: 5)

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL), image.isValid {
            iconView.image = image
            hasBundledIcon = true
        } else {
            iconView.image = NSApplication.shared.applicationIconImage
            logger.debug("当前运行环境未提供可读取的应用图标资源")
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityLabel("速喵猫咪图标")
        iconView.widthAnchor.constraint(equalToConstant: 58).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let heading = NSStackView(views: [iconView, headingText])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 14

        let divider = NSBox()
        divider.boxType = .separator
        let intervalLabel = NSTextField(labelWithString: "刷新间隔")
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged(_:))
        intervalPopup.isEnabled = allowsPreferenceChanges
        for interval in RefreshPreferences.supportedIntervals {
            intervalPopup.addItem(withTitle: interval == 0.5 ? "0.5 秒" : "\(Int(interval)) 秒")
        }
        intervalPopup.widthAnchor.constraint(equalToConstant: 104).isActive = true
        let spacer = NSView()
        let intervalRow = NSStackView(views: [intervalLabel, spacer, intervalPopup])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 12

        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginItemChanged(_:))
        loginCheckbox.allowsMixedState = true
        loginCaption.font = .systemFont(ofSize: 12)
        loginCaption.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        approvalLabel.font = .systemFont(ofSize: 12)
        approvalLabel.textColor = .secondaryLabelColor
        approvalButton.bezelStyle = .rounded
        approvalButton.target = self
        approvalButton.action = #selector(openSystemSettings(_:))
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        let loginSection = verticalStack(
            [loginCheckbox, loginCaption, statusLabel, approvalLabel, approvalButton, errorLabel],
            spacing: 8
        )
        let stack = verticalStack([heading, divider, intervalRow, loginSection], spacing: 18)
        contentStack = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            intervalRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginCaption.widthAnchor.constraint(equalTo: loginSection.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: loginSection.widthAnchor),
            approvalLabel.widthAnchor.constraint(equalTo: loginSection.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: loginSection.widthAnchor)
        ])
    }

    /// Constructs consistent vertical groups while hidden state rows collapse naturally.
    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        return stack
    }

    /// Mirrors system state without inferring success from a previous preference or click.
    private func synchronizeControls() {
        synchronizePreferences()
        let status = loginItems.status
        loginCheckbox.state = status == .requiresApproval ? .mixed : (status == .enabled ? .on : .off)
        loginCheckbox.isEnabled = loginItems.supportsChanges && !loginItems.isUpdating
        statusLabel.stringValue = loginItems.isUpdating ? "状态：正在更新…" : "状态：\(status.description)"
        approvalLabel.isHidden = status != .requiresApproval
        approvalButton.isHidden = status != .requiresApproval
        approvalButton.isEnabled = loginItems.supportsChanges && !loginItems.isUpdating
        errorLabel.stringValue = loginItems.errorMessage ?? ""
        errorLabel.isHidden = loginItems.errorMessage == nil
        fitWindowToContents()
    }

    /// Sizes the content from its actual native layout instead of assuming fixed row heights.
    private func fitWindowToContents() {
        guard let window, let content = window.contentView, let stack = contentStack else { return }
        // With no bottom compression constraint, all visible rows keep their natural height.
        content.layoutSubtreeIfNeeded()
        let requiredHeight = ceil(max(stack.fittingSize.height, stack.frame.height) + 48)
        guard requiredHeight.isFinite, requiredHeight > 0 else {
            logger.error("无法确定设置窗口内容尺寸")
            return
        }
        let height = max(410, requiredHeight)
        if abs(content.bounds.height - height) > 0.5 {
            window.setContentSize(NSSize(width: content.bounds.width, height: height))
            content.layoutSubtreeIfNeeded()
        }
    }

    /// Saves an interval only after the user chooses it in the popup.
    @objc private func intervalChanged(_ sender: NSPopUpButton) {
        guard allowsPreferenceChanges else {
            logger.debug("只读检查模式忽略刷新间隔修改")
            return
        }
        guard RefreshPreferences.supportedIntervals.indices.contains(sender.indexOfSelectedItem) else { return }
        let interval = RefreshPreferences.supportedIntervals[sender.indexOfSelectedItem]
        guard preferences.setInterval(interval) else { return }
        onIntervalChanged()
    }

    /// Starts one user-authorized login operation, with mixed state treated as registered.
    @objc private func loginItemChanged(_ sender: NSButton) {
        guard loginItems.supportsChanges, !loginItems.isUpdating, loginChangeTask == nil else {
            synchronizeControls()
            return
        }
        // Derive intent from actual registration so a mixed checkbox can reliably turn off.
        let enabled = !loginItems.status.isRegistered
        logger.info("用户请求更新登录时启动设置")
        loginChangeTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.loginItems.setEnabled(enabled)
            self.loginChangeTask = nil
            self.synchronizeControls()
        }
    }

    /// Opens the system pane through the injected service after an explicit user action.
    @objc private func openSystemSettings(_ sender: NSButton) {
        guard loginItems.supportsChanges, !loginItems.isUpdating else { return }
        loginItems.openSystemSettings()
    }
}
