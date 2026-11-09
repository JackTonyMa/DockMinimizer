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

        let appRef = AXUIElementCreateApplication(pid)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            // Fallback to app.hide() if accessibility window list is unavailable
            if app.isHidden {
                app.activate()
                return false
            } else {
                app.hide()
                return true
            }
        }

        // Filter only actual standard windows (excluding desktop scroll area, menus, popups, etc.)
        let standardWindows = windows.filter { win in
            var roleVal: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleVal)
            return (roleVal as? String) == (kAXWindowRole as String)
        }

        // If the application has no open standard windows, do not consume click so Dock can open/create one
        if standardWindows.isEmpty && !app.isHidden {
            LogService.shared.log(category: "WindowMinimizer", message: "\(appName) 无打开窗口，传递给 Dock 打开新窗口")
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

        if allMinimized || app.isHidden {
            // Restore: unminimize all standard windows and activate the app
            for win in standardWindows {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            let success = app.activate()
            LogService.shared.log(category: "WindowMinimizer", message: "恢复应用窗口: \(appName) (\(standardWindows.count) 个) - \(success ? "成功" : "失败")")
            return true
        } else {
            // Minimize all standard windows with genie animation
            for win in standardWindows {
                // First try setting kAXMinimizedAttribute
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)

                // If not minimized (e.g. Electron / Chromium apps), press the minimize button directly
                var minVal: AnyObject?
                if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minVal) != .success || (minVal as? Bool) != true {
                    var minBtnVal: AnyObject?
                    if AXUIElementCopyAttributeValue(win, kAXMinimizeButtonAttribute as CFString, &minBtnVal) == .success,
                       let minBtn = minBtnVal {
                        AXUIElementPerformAction(minBtn as! AXUIElement, kAXPressAction as CFString)
                    }
                }
            }
            LogService.shared.log(category: "WindowMinimizer", message: "最小化应用窗口: \(appName) (\(standardWindows.count) 个)")
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