import Cocoa
import ApplicationServices
import os.log

/// Handles window minimization operations using Accessibility API
class WindowMinimizer {
    static let shared = WindowMinimizer()

    private let logger = Logger(subsystem: "com.dockminimizer.app", category: "WindowMinimizer")

    private init() {
        logger.info("WindowMinimizer 初始化")
    }

    /// Toggles minimization state of all windows of the given application
    /// If all windows are minimized, restores them. Otherwise, minimizes all visible windows.
    /// - Parameter app: The running application whose windows should be toggled
    func toggleMinimization(app: NSRunningApplication) {
        NSLog("========================================")
        NSLog("  [WindowMinimizer] 开始切换窗口状态")
        NSLog("  目标应用: %@", app.localizedName ?? "Unknown")
        NSLog("  目标 PID: %d", app.processIdentifier)

        print("\n")
        print("========================================")
        print("  [WindowMinimizer] 开始切换窗口状态")
        print("========================================")
        print("目标应用: \(app.localizedName ?? "Unknown")")
        print("目标 PID: \(app.processIdentifier)")

        logger.info("========== 开始切换窗口状态 ==========")
        logger.info("目标应用: \(app.localizedName ?? "Unknown")")
        logger.info("目标 PID: \(app.processIdentifier)")
        logger.info("目标 Bundle ID: \(app.bundleIdentifier ?? "无")")

        // Check accessibility permission
        let hasPermission = AXIsProcessTrusted()
        NSLog("[WindowMinimizer] 辅助功能权限: %@", hasPermission ? "已授权" : "未授权")
        print("[WindowMinimizer] 辅助功能权限: \(hasPermission ? "已授权" : "未授权")")
        logger.info("辅助功能权限: \(hasPermission ? "已授权" : "未授权")")

        guard hasPermission else {
            NSLog("[WindowMinimizer] 错误: 辅助功能权限未授予")
            print("[WindowMinimizer] 错误: 辅助功能权限未授予")
            logger.error("辅助功能权限未授予，无法操作")
            showPermissionNotification()
            return
        }

        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        NSLog("[WindowMinimizer] 创建了 AXUIElement 引用")
        print("[WindowMinimizer] 创建了 AXUIElement 引用")
        logger.info("创建了 AXUIElement 引用")

        // Get all windows of the application
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)

        NSLog("[WindowMinimizer] 获取窗口列表结果: %ld (%@)", result.rawValue, result == .success ? "success" : "failed")
        print("[WindowMinimizer] 获取窗口列表结果: \(result.rawValue) (\(result == .success ? "success" : "failed"))")
        logger.info("获取窗口列表结果: \(result.rawValue)")

        guard result == .success else {
            print("[WindowMinimizer] 错误: 无法获取应用窗口，错误码: \(result.rawValue)")
            logger.error("无法获取应用窗口")
            return
        }

        guard let windows = windowsValue as? [AXUIElement] else {
            print("[WindowMinimizer] 警告: 窗口列表为空或类型转换失败")
            logger.warning("窗口列表为空或类型转换失败")
            if let windowsValue = windowsValue {
                logger.debug("windowsValue 类型: \(type(of: windowsValue))")
            }
            return
        }

        print("[WindowMinimizer] 找到 \(windows.count) 个窗口")
        NSLog("[WindowMinimizer] 找到 %ld 个窗口", windows.count)

        if windows.isEmpty {
            NSLog("[WindowMinimizer] 警告: 没有找到任何窗口！")
            logger.warning("没有找到任何窗口！")
            return
        }

        // Check if all windows are minimized
        var allMinimized = true
        var windowStates: [(window: AXUIElement, isMinimized: Bool, title: String)] = []

        for window in windows {
            let (isMinimized, title) = getWindowState(window)
            windowStates.append((window, isMinimized, title))
            if !isMinimized {
                allMinimized = false
            }
            NSLog("[WindowMinimizer] 窗口 '%@' 最小化状态: %@", title, isMinimized ? "是" : "否")
        }

        // Decide action: if all minimized -> restore, otherwise -> minimize
        let shouldRestore = allMinimized

        NSLog("[WindowMinimizer] 决策: %@", shouldRestore ? "恢复所有窗口" : "最小化可见窗口")
        print("[WindowMinimizer] 决策: \(shouldRestore ? "恢复所有窗口" : "最小化可见窗口")")
        logger.info("决策: \(shouldRestore ? "恢复所有窗口" : "最小化可见窗口")")

        var successCount = 0

        for (index, state) in windowStates.enumerated() {
            NSLog("[WindowMinimizer] 处理窗口 %d/%d: '%@'", index + 1, windowStates.count, state.title)
            print("[WindowMinimizer] --- 处理窗口 \(index + 1)/\(windowStates.count): \(state.title) ---")

            let success: Bool
            if shouldRestore {
                // Restore minimized windows
                if state.isMinimized {
                    success = restoreWindow(state.window)
                    if success {
                        NSLog("[WindowMinimizer] 窗口恢复成功!")
                        print("[WindowMinimizer] 窗口恢复成功!")
                        // Also raise the window to bring it to front
                        raiseWindow(state.window)
                    } else {
                        NSLog("[WindowMinimizer] 窗口恢复失败")
                        print("[WindowMinimizer] 窗口恢复失败")
                    }
                } else {
                    // Already visible, just raise it
                    success = raiseWindow(state.window)
                    NSLog("[WindowMinimizer] 窗口已在可见状态，提升到前台")
                    print("[WindowMinimizer] 窗口已在可见状态，提升到前台")
                }
            } else {
                // Minimize visible windows
                if !state.isMinimized {
                    success = minimizeWindow(state.window)
                    if success {
                        NSLog("[WindowMinimizer] 窗口最小化成功!")
                        print("[WindowMinimizer] 窗口最小化成功!")
                    } else {
                        NSLog("[WindowMinimizer] 窗口最小化失败")
                        print("[WindowMinimizer] 窗口最小化失败")
                    }
                } else {
                    success = false
                    NSLog("[WindowMinimizer] 窗口已是最小化状态，跳过")
                    print("[WindowMinimizer] 窗口已是最小化状态，跳过")
                }
            }

            if success {
                successCount += 1
            }
        }

        NSLog("[WindowMinimizer] 完成: 成功 %d/%d", successCount, windowStates.count)
        print("[WindowMinimizer] ========== 完成: 成功 \(successCount)/\(windowStates.count) ==========")
    }

    /// Gets the minimization state and title of a window
    private func getWindowState(_ window: AXUIElement) -> (isMinimized: Bool, title: String) {
        // Check minimized state
        var minimizedValue: AnyObject?
        let minimizedResult = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minimizedValue
        )

        let isMinimized = (minimizedResult == .success && (minimizedValue as? Bool) == true)

        // Get window title
        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleResult == .success) ? (titleValue as? String ?? "无标题") : "无标题"

        return (isMinimized, title)
    }

    /// Attempts to minimize a single window
    /// - Parameter window: The AXUIElement representing the window
    /// - Returns: True if minimization succeeded, false otherwise
    private func minimizeWindow(_ window: AXUIElement) -> Bool {
        print("[WindowMinimizer] 开始最小化单个窗口...")
        logger.debug("开始最小化单个窗口...")

        // Try to get the minimize button first
        if pressMinimizeButton(window) {
            print("[WindowMinimizer] 通过按钮点击最小化成功")
            return true
        }

        print("[WindowMinimizer] 按钮点击失败，尝试直接设置属性...")

        // Fallback: Set minimized attribute directly
        let setResult = AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            true as CFTypeRef
        )

        print("[WindowMinimizer] 设置属性结果: \(setResult.rawValue)")

        if setResult == .success {
            print("[WindowMinimizer] 通过设置属性最小化成功")
            return true
        } else {
            print("[WindowMinimizer] 设置属性失败，错误码: \(setResult.rawValue)")
            logger.error("设置属性失败，错误码: \(setResult.rawValue)")
            return false
        }
    }

    /// Attempts to restore a minimized window
    /// - Parameter window: The AXUIElement representing the window
    /// - Returns: True if restoration succeeded, false otherwise
    private func restoreWindow(_ window: AXUIElement) -> Bool {
        print("[WindowMinimizer] 开始恢复单个窗口...")
        logger.debug("开始恢复单个窗口...")

        // Set minimized attribute to false
        let setResult = AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            false as CFTypeRef
        )

        print("[WindowMinimizer] 设置恢复属性结果: \(setResult.rawValue)")

        if setResult == .success {
            print("[WindowMinimizer] 窗口恢复成功")
            return true
        } else {
            print("[WindowMinimizer] 窗口恢复失败，错误码: \(setResult.rawValue)")
            logger.error("窗口恢复失败，错误码: \(setResult.rawValue)")
            return false
        }
    }

    /// Attempts to raise a window to the front
    /// - Parameter window: The AXUIElement representing the window
    /// - Returns: True if raising succeeded, false otherwise
    private func raiseWindow(_ window: AXUIElement) -> Bool {
        print("[WindowMinimizer] 提升窗口到前台...")
        logger.debug("提升窗口到前台...")

        // Try to raise the window using AXRaiseAction
        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        print("[WindowMinimizer] 提升窗口结果: \(raiseResult.rawValue)")

        if raiseResult == .success {
            print("[WindowMinimizer] 窗口已提升到前台")
            return true
        } else {
            // Try focusing the window as fallback
            let focusResult = AXUIElementSetAttributeValue(
                window,
                kAXFocusedAttribute as CFString,
                true as CFTypeRef
            )
            print("[WindowMinimizer] 设置焦点结果: \(focusResult.rawValue)")
            return focusResult == .success
        }
    }

    /// Attempts to press the minimize button on the window
    /// - Parameter window: The AXUIElement representing the window
    /// - Returns: True if the minimize button was successfully pressed
    private func pressMinimizeButton(_ window: AXUIElement) -> Bool {
        print("[WindowMinimizer] 尝试获取最小化按钮...")
        logger.debug("尝试获取最小化按钮...")

        // Get the minimize button directly from the window
        var buttonValue: AnyObject?
        let buttonResult = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizeButtonAttribute as CFString,
            &buttonValue
        )

        print("[WindowMinimizer] 获取最小化按钮结果: \(buttonResult.rawValue)")

        if buttonResult == .success, let button = buttonValue {
            print("[WindowMinimizer] 成功获取最小化按钮")
            logger.debug("成功获取最小化按钮")

            // Press the minimize button
            let pressResult = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            print("[WindowMinimizer] 按钮点击结果: \(pressResult.rawValue)")
            logger.debug("按钮点击结果: \(pressResult.rawValue)")

            if pressResult == .success {
                return true
            }
        }

        return false
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
