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

        // Special handling for Finder: Finder cannot be hidden via app.hide() on macOS.
        // Instead, minimize or restore its standard windows.
        if app.bundleIdentifier == "com.apple.finder" || appName == "Finder" {
            return toggleFinderMinimization(app: app)
        }

        // If the application has no open windows, do not consume the click so the Dock can create/open a window
        let appRef = AXUIElementCreateApplication(pid)
        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement] {
            let standardWindows = windows.filter { win in
                var roleVal: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleVal)
                return (roleVal as? String) == (kAXWindowRole as String)
            }
            if standardWindows.isEmpty && !app.isHidden {
                return false
            }
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

    /// Toggles minimization for Finder windows.
    /// Finder is a core macOS desktop service and cannot be hidden via app.hide().
    /// We minimize/restore its standard windows using the Accessibility API.
    private func toggleFinderMinimization(app: NSRunningApplication) -> Bool {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return false
        }

        // Filter only actual standard windows (excluding desktop scroll area)
        let standardWindows = windows.filter { win in
            var roleVal: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleVal)
            return (roleVal as? String) == (kAXWindowRole as String)
        }

        // If Finder has no standard windows, do not consume click so the Dock creates a new window
        if standardWindows.isEmpty {
            LogService.shared.log(category: "WindowMinimizer", message: "Finder 无打开窗口，传递给 Dock 打开新窗口")
            return false
        }

        let allMinimized = standardWindows.allSatisfy { win in
            var minVal: AnyObject?
            if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minVal) == .success,
               let isMin = minVal as? Bool {
                return isMin
            }
            return false
        }

        if allMinimized {
            for win in standardWindows {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            app.activate()
            LogService.shared.log(category: "WindowMinimizer", message: "恢复 Finder 窗口 (\(standardWindows.count) 个)")
            return true
        } else {
            for win in standardWindows {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
            LogService.shared.log(category: "WindowMinimizer", message: "最小化 Finder 窗口 (\(standardWindows.count) 个)")
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