import AppKit
import Darwin
import Foundation
import NetSpeedCore
import OSLog

/// Owns the menu-bar UI and its lifecycle, leaving counter reads to an isolated actor.
@MainActor
final class NetSpeedApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Selects ordinary continuous operation or bounded diagnostics.
    private let options: LaunchOptions
    /// Records application lifecycle events through the common subsystem.
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "Application")
    /// Serializes reader and calculator access independently of the main actor.
    private let sampler = NetworkSamplingService()
    /// Retains the status item for the full lifetime of the application.
    private var statusItem: NSStatusItem?
    /// Retains the native menu displayed by the status button.
    private let menu = NSMenu()
    /// Displays the most recent upload measurement or explicit unavailable state.
    private let uploadMenuItem = NSMenuItem(title: "上传：采样中", action: nil, keyEquivalent: "")
    /// Displays the most recent download measurement or explicit unavailable state.
    private let downloadMenuItem = NSMenuItem(title: "下载：采样中", action: nil, keyEquivalent: "")
    /// Identifies the interfaces included in the current measurement.
    private let interfaceMenuItem = NSMenuItem(title: "当前网卡：识别中", action: nil, keyEquivalent: "")
    /// Retains the interval choices so their checkmarks can follow changes.
    private var intervalMenuItems: [NSMenuItem] = []
    /// Holds the active repeating timer while the system is awake.
    private var refreshTimer: Timer?
    /// Bounds smoke-test duration if startup or sampling cannot finish.
    private var smokeTimeoutTimer: Timer?
    /// Keeps one outstanding sample task, preventing overlapping scheduled reads.
    private var pendingSample: Task<Void, Never>?
    /// Invalidates older sample results across sleep, wake, and shutdown.
    private var lifecycleGeneration = 0
    /// Prevents sampling while the workspace is asleep.
    private var isSleeping = false
    /// Prevents duplicate report writes and shutdown work.
    private var isFinishingSmoke = false
    /// Stores the selected, validated interval without changing settings during smoke tests.
    private var refreshInterval: TimeInterval = 1
    /// Counts actual smoke-test sampling attempts, including failed reads.
    private var smokeSamplingAttemptCount = 0
    /// Counts successful reads of real system counters for smoke evidence.
    private var smokeRealSampleCount = 0
    /// Counts repeating scheduler ticks independently of the immediate startup sample.
    private var smokeScheduledRefreshCount = 0
    /// Anchors diagnostic elapsed time to a monotonic clock.
    private var smokeStartTime: TimeInterval = 0
    /// Stores the approved interval choices in seconds.
    private let supportedIntervals: [TimeInterval] = [0.5, 1, 2]
    /// Names the sole persisted application preference.
    private let intervalPreferenceKey = "refreshIntervalSeconds"

    /// Retains immutable launch options before AppKit begins delivering callbacks.
    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    /// Builds the native status item, registers sleep notifications, and starts sampling.
    func applicationDidFinishLaunching(_ notification: Notification) {
        smokeStartTime = ProcessInfo.processInfo.systemUptime
        refreshInterval = loadRefreshInterval()
        buildMenu()
        let item = NSStatusBar.system.statusItem(withLength: StatusImageRenderer.width)
        item.menu = menu
        statusItem = item
        updateDisplay(upload: "采样中", download: "采样中")

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if options.smokeTest {
            let timeout = Timer(
                timeInterval: 12,
                target: self,
                selector: #selector(smokeTestTimedOut(_:)),
                userInfo: nil,
                repeats: false
            )
            smokeTimeoutTimer = timeout
            RunLoop.main.add(timeout, forMode: .common)
        }

        logger.info("菜单栏网速应用已启动")
        startRefreshTimer()
        requestSample()
    }

    /// Releases the timer and native status item when the user quits normally.
    func applicationWillTerminate(_ notification: Notification) {
        cleanUp()
        logger.info("菜单栏网速应用已退出")
    }

    /// Constructs read-only speed details, persisted refresh choices, and quit action.
    private func buildMenu() {
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: "实时速度", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for item in [uploadMenuItem, downloadMenuItem, interfaceMenuItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let intervalItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu(title: "刷新间隔")
        intervalMenu.autoenablesItems = false
        for interval in supportedIntervals {
            let title = interval == 0.5 ? "0.5 秒" : "\(Int(interval)) 秒"
            let choice = NSMenuItem(title: title, action: #selector(changeRefreshInterval(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = NSNumber(value: interval)
            choice.state = interval == refreshInterval ? .on : .off
            intervalMenu.addItem(choice)
            intervalMenuItems.append(choice)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出网速", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Loads only approved intervals and uses a safe default for invalid stored data.
    private func loadRefreshInterval() -> TimeInterval {
        guard let storedValue = UserDefaults.standard.object(forKey: intervalPreferenceKey) else {
            return 1
        }
        guard let value = storedValue as? NSNumber,
              supportedIntervals.contains(value.doubleValue) else {
            logger.warning("刷新间隔配置无效，使用默认 1 秒")
            return 1
        }
        return value.doubleValue
    }

    /// Replaces the repeating timer while allowing menu tracking to keep refreshing.
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard !isSleeping, !isFinishingSmoke else { return }
        let timer = Timer(
            timeInterval: refreshInterval,
            target: self,
            selector: #selector(refreshTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        // Timer tolerance permits macOS to coalesce wakeups without changing rate math.
        timer.tolerance = refreshInterval * 0.1
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Requests the next measurement and records actual scheduler delivery in smoke mode.
    @objc private func refreshTimerFired(_ timer: Timer) {
        if options.smokeTest { smokeScheduledRefreshCount += 1 }
        requestSample()
    }

    /// Allows one sample task at a time and ignores results from an older lifecycle.
    private func requestSample() {
        guard !isSleeping, !isFinishingSmoke, pendingSample == nil else { return }
        let generation = lifecycleGeneration
        pendingSample = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.sampler.sample()
            self.pendingSample = nil
            // A completed read after sleep or quit is no longer a current UI measurement.
            guard !Task.isCancelled,
                  generation == self.lifecycleGeneration,
                  !self.isSleeping,
                  !self.isFinishingSmoke else { return }
            self.handle(outcome)
        }
    }

    /// Applies a completed measurement to the native menu and status image.
    private func handle(_ outcome: SamplingOutcome) {
        if options.smokeTest { smokeSamplingAttemptCount += 1 }
        switch outcome {
        case .establishingBaseline(let rate):
            if options.smokeTest { smokeRealSampleCount += 1 }
            updateInterfaceDetails(rate.interfaceNames)
            updateDisplay(upload: "采样中", download: "采样中")
        case .available(let rate):
            if options.smokeTest { smokeRealSampleCount += 1 }
            updateInterfaceDetails(rate.interfaceNames)
            updateDisplay(
                upload: RateFormatter.string(bytesPerSecond: rate.uploadBytesPerSecond),
                download: RateFormatter.string(bytesPerSecond: rate.downloadBytesPerSecond)
            )
        case .unavailable:
            interfaceMenuItem.title = "当前网卡：不可用"
            updateDisplay(upload: "不可用", download: "不可用")
        }

        // The bounded diagnostic covers exactly three sampling attempts and never sends traffic.
        if options.smokeTest, smokeSamplingAttemptCount >= 3 {
            finishSmokeTest(timedOut: false)
        }
    }

    /// Shows the interfaces included by the system reader without logging identifiers.
    private func updateInterfaceDetails(_ identifiers: [String]) {
        let summary = identifiers.isEmpty ? "未检测到活动网卡" : identifiers.joined(separator: "、")
        interfaceMenuItem.title = "当前网卡：\(summary)"
    }

    /// Keeps native accessibility text and detailed menu values aligned with the image.
    private func updateDisplay(upload: String, download: String) {
        uploadMenuItem.title = "上传：\(upload)"
        downloadMenuItem.title = "下载：\(download)"
        let description = "上传：\(upload)，下载：\(download)"
        guard let button = statusItem?.button else { return }
        button.image = StatusImageRenderer.image(upload: upload, download: download)
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    /// Persists a selected approved interval and restarts the awake scheduler.
    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber,
              supportedIntervals.contains(value.doubleValue) else { return }
        refreshInterval = value.doubleValue
        UserDefaults.standard.set(refreshInterval, forKey: intervalPreferenceKey)
        for item in intervalMenuItems {
            let itemValue = (item.representedObject as? NSNumber)?.doubleValue
            item.state = itemValue == refreshInterval ? .on : .off
        }
        logger.info("已更新网速刷新间隔")
        startRefreshTimer()
    }

    /// Stops scheduled reads and invalidates in-flight UI results before system sleep.
    @objc private func workspaceWillSleep(_ notification: Notification) {
        isSleeping = true
        lifecycleGeneration += 1
        refreshTimer?.invalidate()
        refreshTimer = nil
        pendingSample?.cancel()
        updateDisplay(upload: "暂停", download: "暂停")
        logger.info("系统即将睡眠，已暂停网络采样")
    }

    /// Resets counter continuity before resuming scheduled sampling after wake.
    @objc private func workspaceDidWake(_ notification: Notification) {
        isSleeping = false
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sampler.reset()
            guard generation == self.lifecycleGeneration,
                  !self.isSleeping,
                  !self.isFinishingSmoke else { return }
            self.updateDisplay(upload: "采样中", download: "采样中")
            self.startRefreshTimer()
            self.requestSample()
            self.logger.info("系统已唤醒，重新建立网络采样基线")
        }
    }

    /// Exits through AppKit so normal termination cleanup is delivered.
    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(sender)
    }

    /// Converts an incomplete bounded smoke test into an explicit failing report.
    @objc private func smokeTestTimedOut(_ timer: Timer) {
        logger.error("冒烟测试未在规定时间内完成")
        finishSmokeTest(timedOut: true)
    }

    /// Verifies bounded smoke evidence, atomically reports it, and exits with a clear code.
    private func finishSmokeTest(timedOut: Bool) {
        guard !isFinishingSmoke else { return }
        isFinishingSmoke = true
        let image = statusItem?.button?.image
        let size = image?.size ?? .zero
        let visiblePixels = image.map(StatusImageRenderer.hasVisiblePixels) ?? false
        var checks: [String: Bool] = [
            "startup": statusItem?.button != nil && NSApplication.shared.activationPolicy() == .accessory,
            "threeRealSamples": smokeRealSampleCount == 3 && smokeSamplingAttemptCount == 3,
            "menuConstruction": statusItem?.menu === menu && intervalMenuItems.count == supportedIntervals.count
                && menu.items.contains(where: { $0.action == #selector(quit(_:)) }),
            "imageDimensions": size.width == StatusImageRenderer.width && size.height == StatusImageRenderer.height,
            "imageContent": visiblePixels,
            "scheduledRefresh": smokeScheduledRefreshCount >= 2 && refreshTimer?.isValid == true,
            "completedWithinDeadline": !timedOut
        ]

        if let previewURL = options.renderPreviewURL {
            do {
                guard let image else { throw StatusImageError.encodingFailed }
                try StatusImageRenderer.writePNG(image, to: previewURL)
                checks["previewWritten"] = true
            } catch {
                checks["previewWritten"] = false
                logger.error("冒烟测试图像预览写入失败")
            }
        }

        let success = checks.values.allSatisfy { $0 }
        let report = SmokeReport(
            success: success,
            realSampleCount: smokeRealSampleCount,
            samplingAttemptCount: smokeSamplingAttemptCount,
            scheduledRefreshCount: smokeScheduledRefreshCount,
            refreshIntervalSeconds: refreshInterval,
            menuItemCount: menu.items.count,
            imageWidthPoints: Double(size.width),
            imageHeightPoints: Double(size.height),
            imageHasVisiblePixels: visiblePixels,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - smokeStartTime,
            checks: checks
        )

        // Remove the visible status item before writing evidence and terminating the test process.
        cleanUp()
        do {
            guard let reportURL = options.smokeReportURL else { throw LaunchOptionError.reportRequired }
            try report.write(to: reportURL)
            if success {
                logger.info("冒烟测试已通过")
            } else {
                logger.error("冒烟测试未通过，详情见 JSON 报告")
            }
            exit(success ? 0 : 1)
        } catch {
            logger.error("冒烟测试报告写入失败")
            FileHandle.standardError.write(Data("冒烟测试报告写入失败。\n".utf8))
            exit(1)
        }
    }

    /// Stops all scheduled work and removes the application's status item.
    private func cleanUp() {
        lifecycleGeneration += 1
        refreshTimer?.invalidate()
        refreshTimer = nil
        smokeTimeoutTimer?.invalidate()
        smokeTimeoutTimer = nil
        pendingSample?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
}
