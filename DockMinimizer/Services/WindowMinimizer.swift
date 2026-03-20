import Cocoa

/// Handles window minimization operations using Accessibility API
class WindowMinimizer {
    static let shared = WindowMinimizer()

    private init() {}

    /// Toggles minimization state of the given application
    /// If app is hidden, activates it. Otherwise, hides the app.
    /// - Parameter app: The running application to toggle
    /// - Returns: True if event should be consumed (hide action), false if system should handle it (activate action)
    @discardableResult
    func toggleMinimization(app: NSRunningApplication) -> Bool {
        let appName = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier

        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            LogService.shared.log(level: .error, category: "WindowMinimizer", message: "辅助功能权限未授予")
            showPermissionNotification()
            return false
        }

        // Check if app is hidden
        let isHidden = app.isHidden

        if isHidden {
            // Restore: activate the app
            let success = app.activate()
            LogService.shared.log(category: "WindowMinimizer", message: "激活应用: \(appName) (PID: \(pid)) - \(success ? "成功" : "失败")")
            return false
        } else {
            // Hide: hide the entire app
            app.hide()
            LogService.shared.log(category: "WindowMinimizer", message: "隐藏应用: \(appName) (PID: \(pid))")
            return true
        }
    }

    private func showPermissionNotification() {
        DispatchQueue.main.async {
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