import Cocoa
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var dockMonitor: DockMonitor?
    private var permissionAlertShown = false

    private let logger = Logger(subsystem: "com.dockminimizer.app", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("========================================")
        NSLog("  DockMinimizer 应用启动")
        NSLog("========================================")
        NSLog("应用路径: %@", Bundle.main.bundlePath)

        print("\n")
        print("========================================")
        print("  DockMinimizer 应用启动")
        print("========================================")
        print("应用路径: \(Bundle.main.bundlePath)")

        logger.info("=== DockMinimizer 应用启动 ===")
        logger.info("应用路径: \(Bundle.main.bundlePath)")

        // Set activation policy to accessory (no dock icon, but can show status bar)
        NSApplication.shared.setActivationPolicy(.accessory)
        logger.info("应用模式已设置为 accessory (无 Dock 图标)")

        // Create status bar item immediately
        createStatusItem()

        // Check for accessibility permissions
        checkAccessibilityPermission()

        // Start monitoring Dock clicks
        dockMonitor = DockMonitor()
        logger.info("DockMonitor 已初始化")

        // Log current frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            logger.info("当前前台应用: \(frontApp.localizedName ?? "Unknown") (PID: \(frontApp.processIdentifier))")
        }
    }

    private func checkAccessibilityPermission() {
        let hasPermission = AXIsProcessTrusted()
        logger.info("辅助功能权限状态: \(hasPermission ? "已授权" : "未授权")")

        if !hasPermission {
            showPermissionAlert()
            // Request permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
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
                self?.logger.info("用户选择打开系统设置")
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func createStatusItem() {
        NSLog("[AppDelegate] ========== 开始创建状态栏图标 ==========")
        print("\n[AppDelegate] ========== 开始创建状态栏图标 ==========")

        // 创建状态栏项
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let item = self.statusItem else {
            NSLog("[AppDelegate] ❌ 错误: statusItem 创建失败！")
            print("[AppDelegate] ❌ 错误: statusItem 创建失败！")
            return
        }

        guard let button = item.button else {
            NSLog("[AppDelegate] ❌ 错误: 无法获取 button！")
            print("[AppDelegate] ❌ 错误: 无法获取 button！")
            return
        }

        // 使用单个字符图标 - 在刘海屏上最可靠
        button.title = "▼"
        button.font = NSFont.systemFont(ofSize: 14)
        button.toolTip = "DockMinimizer - 点击 Dock 图标最小化窗口"

        NSLog("[AppDelegate] ✓ 状态栏图标已设置: ▼")
        print("[AppDelegate] ✓ 状态栏图标已设置: ▼")

        // 创建菜单
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "DockMinimizer 运行中", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let permissionItem = NSMenuItem(title: "检查权限", action: #selector(checkPermissionStatus), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 (⌘Q)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu

        // 确保可见
        item.isVisible = true
        button.isHidden = false

        NSLog("[AppDelegate] ========== 状态栏图标创建完成 ==========")
        print("[AppDelegate] ========== 状态栏图标创建完成 ==========")
    }

    @objc private func checkPermissionStatus() {
        let hasPermission = AXIsProcessTrusted()
        logger.info("检查权限状态: \(hasPermission ? "已授权" : "未授权")")

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

    @objc private func quitApp() {
        logger.info("用户请求退出应用")
        NSApplication.shared.terminate(nil)
    }

    // Keep the app running even without windows (important for LSUIElement apps)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}