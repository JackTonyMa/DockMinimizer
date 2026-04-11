import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var dockMonitor: DockMonitor?
    private var permissionAlertShown = false
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var updateService = UpdateService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogService.shared.log(category: "AppDelegate", message: "应用启动: \(Bundle.main.bundlePath)")

        // Set activation policy to accessory (no dock icon, but can show status bar)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create status bar item
        createStatusItem()

        // Observe language changes
        LocalizationManager.shared.$currentLanguage
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemMenu()
                }
            }
            .store(in: &cancellables)

        // Check for accessibility permissions
        checkAccessibilityPermission()

        // Start monitoring Dock clicks
        dockMonitor = DockMonitor.shared

        // 启动时根据设置决定是否打开设置窗口
        // UserDefaults.bool returns false if key doesn't exist, but we want default true
        let hasKey = UserDefaults.standard.object(forKey: "showPanelOnLaunch") != nil
        let showPanelOnLaunch = hasKey ? UserDefaults.standard.bool(forKey: "showPanelOnLaunch") : true
        if showPanelOnLaunch {
            openSettings()
        }

        // 启动后延迟检查更新
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 延迟 2 秒
            await updateService.checkForUpdates()
        }

        // 监听更新状态变化
        updateService.$updateAvailable
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemMenu()
                }
            }
            .store(in: &cancellables)
    }

    private func checkAccessibilityPermission() {
        let hasPermission = AXIsProcessTrusted()

        if !hasPermission {
            showPermissionAlert()
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    private func showPermissionAlert() {
        guard !permissionAlertShown else { return }
        permissionAlertShown = true

        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = L10n.permissionRequiredTitle
            alert.informativeText = L10n.permissionRequiredMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.openSystemSettings)
            alert.addButton(withTitle: L10n.later)

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func createStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let item = self.statusItem else { return }
        guard let button = item.button else { return }

        button.title = "▼"
        button.font = NSFont.systemFont(ofSize: 14)
        button.toolTip = L10n.statusBarTooltip

        updateStatusItemMenu()

        item.isVisible = true
        button.isHidden = false
    }

    private func updateStatusItemMenu() {
        guard let item = self.statusItem else { return }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: L10n.dockMinimizerRunning, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let permissionItem = NSMenuItem(title: L10n.checkPermissions, action: #selector(checkPermissionStatus), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let logItem = NSMenuItem(title: L10n.viewLogs, action: #selector(openLogFolder), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        // 更新检查
        menu.addItem(NSMenuItem.separator())

        let updateTitle = updateService.updateAvailable
            ? "\(L10n.checkForUpdates) (\(L10n.updateAvailable))"
            : L10n.checkForUpdates
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        if updateService.updateAvailable {
            updateItem.state = .on
        }
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func checkPermissionStatus() {
        let hasPermission = AXIsProcessTrusted()

        if hasPermission {
            let alert = NSAlert()
            alert.messageText = L10n.permissionGrantedTitle
            alert.informativeText = L10n.permissionGrantedMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.ok)
            alert.runModal()
        } else {
            showPermissionAlert()
        }
    }

    @objc private func openLogFolder() {
        LogService.shared.openLogFolder()
    }

    @objc private func checkForUpdates() {
        Task {
            await updateService.checkForUpdates(force: true)

            await MainActor.run {
                if updateService.updateAvailable {
                    let alert = NSAlert()
                    alert.messageText = L10n.updateAvailable
                    alert.informativeText = "\(L10n.currentVersion): \(updateService.currentVersion)\n\(L10n.latestVersion): \(updateService.latestVersion ?? "?")"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: L10n.downloadUpdate)
                    alert.addButton(withTitle: L10n.ok)

                    if alert.runModal() == .alertFirstButtonReturn {
                        updateService.openReleasePage()
                    }
                } else if let error = updateService.errorMessage {
                    let alert = NSAlert()
                    alert.messageText = L10n.updateError
                    alert.informativeText = error
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.ok)
                    alert.runModal()
                } else {
                    let alert = NSAlert()
                    alert.messageText = L10n.alreadyUpToDate
                    alert.informativeText = "\(L10n.currentVersion): \(updateService.currentVersion)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: L10n.ok)
                    alert.runModal()
                }
            }
        }
    }

    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 如果窗口已存在，直接激活
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // 通过窗口标题查找是否已有 SwiftUI 创建的窗口
        let settingsTitle = L10n.settingsWindowTitle
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == settingsTitle }) {
            settingsWindow = existingWindow
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // 创建新窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = settingsTitle
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            // 窗口关闭时不清除引用，下次打开时可以复用
            // 因为 isReleasedWhenClosed = false，窗口对象仍然存在
        }
    }
}