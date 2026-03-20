import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var dockMonitor: DockMonitor?
    private var permissionAlertShown = false
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogService.shared.log(category: "AppDelegate", message: "应用启动: \(Bundle.main.bundlePath)")

        // Set activation policy to accessory (no dock icon, but can show status bar)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create status bar item
        createStatusItem()

        // Check for accessibility permissions
        checkAccessibilityPermission()

        // Start monitoring Dock clicks
        dockMonitor = DockMonitor()
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
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = """
            DockMinimizer 需要辅助功能权限才能监控和操作其他应用的窗口。

            请前往：
            系统设置 → 隐私与安全性 → 辅助功能

            点击 "+" 按钮添加 DockMinimizer 到授权列表。
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后设置")

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
        button.toolTip = "DockMinimizer - 点击 Dock 图标最小化窗口"

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "DockMinimizer 运行中", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let permissionItem = NSMenuItem(title: "检查权限", action: #selector(checkPermissionStatus), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let logItem = NSMenuItem(title: "查看日志", action: #selector(openLogFolder), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 (⌘Q)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        item.isVisible = true
        button.isHidden = false
    }

    @objc private func checkPermissionStatus() {
        let hasPermission = AXIsProcessTrusted()

        if hasPermission {
            let alert = NSAlert()
            alert.messageText = "权限已授权"
            alert.informativeText = "DockMinimizer 已获得辅助功能权限，可以正常工作。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        } else {
            showPermissionAlert()
        }
    }

    @objc private func openLogFolder() {
        LogService.shared.openLogFolder()
    }

    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DockMinimizer 设置"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}