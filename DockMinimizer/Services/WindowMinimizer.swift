import Cocoa
import os.log

/// Handles window minimization operations using Accessibility API
class WindowMinimizer {
    static let shared = WindowMinimizer()

    private let logger = Logger(subsystem: "com.dockminimizer.app", category: "WindowMinimizer")

    private init() {
        logger.info("WindowMinimizer 初始化")
    }

    /// Toggles minimization state of the given application
    /// If app is hidden, activates it. Otherwise, hides the app.
    /// - Parameter app: The running application to toggle
    /// - Returns: True if event should be consumed (hide action), false if system should handle it (activate action)
    @discardableResult
    func toggleMinimization(app: NSRunningApplication) -> Bool {
        NSLog("========================================")
        NSLog("  [WindowMinimizer] 开始切换应用状态")
        NSLog("  目标应用: %@", app.localizedName ?? "Unknown")
        NSLog("  目标 PID: %d", app.processIdentifier)

        logger.info("========== 开始切换应用状态 ==========")
        logger.info("目标应用: \(app.localizedName ?? "Unknown")")

        // Check accessibility permission
        let hasPermission = AXIsProcessTrusted()
        NSLog("[WindowMinimizer] 辅助功能权限: %@", hasPermission ? "已授权" : "未授权")
        logger.info("辅助功能权限: \(hasPermission ? "已授权" : "未授权")")

        guard hasPermission else {
            NSLog("[WindowMinimizer] 错误: 辅助功能权限未授予")
            logger.error("辅助功能权限未授予，无法操作")
            showPermissionNotification()
            return false
        }

        // Check if app is hidden
        let isHidden = app.isHidden
        NSLog("[WindowMinimizer] 应用隐藏状态: %@", isHidden ? "已隐藏" : "可见")
        logger.info("应用隐藏状态: \(isHidden ? "已隐藏" : "可见")")

        if isHidden {
            // Restore: activate the app
            NSLog("[WindowMinimizer] 决策: 激活应用")
            logger.info("决策: 激活应用")

            let success = app.activate()
            NSLog("[WindowMinimizer] 激活结果: %@", success ? "成功" : "失败")
            logger.info("激活结果: \(success ? "成功" : "失败")")

            // Let system handle the click event for activation
            return false
        } else {
            // Hide: hide the entire app
            NSLog("[WindowMinimizer] 决策: 隐藏应用")
            logger.info("决策: 隐藏应用")

            app.hide()
            NSLog("[WindowMinimizer] 已隐藏应用")
            logger.info("已隐藏应用")

            // Consume the event to prevent system from re-activating
            return true
        }
    }

    private func showPermissionNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.logger.info("显示权限提示")
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "DockMinimizer 需要辅助功能权限才能最小化其他应用的窗口。请在系统设置中授权。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
