import Cocoa
import os.log
import Carbon

// Global callback function for CGEventTap
private func globalEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let consumed = monitor.handleEvent(proxy: proxy, type: type, event: event)

    // If event was consumed (app was minimized), return nil to prevent system from processing it
    return consumed ? nil : Unmanaged.passRetained(event)
}

/// Monitors Dock icon clicks
class DockMonitor {
    private var currentFrontmostPID: pid_t?
    private var currentFrontmostName: String?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?

    private let logger = Logger(subsystem: "com.dockminimizer.app", category: "DockMonitor")

    init() {
        NSLog("[DockMonitor] === 初始化开始 ===")

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            currentFrontmostPID = frontApp.processIdentifier
            currentFrontmostName = frontApp.localizedName
            NSLog("[DockMonitor] 初始前台应用: %@ (PID: %d)", frontApp.localizedName ?? "Unknown", frontApp.processIdentifier)
        }

        startWorkspaceMonitoring()
        tryStartEventTap()
        startPermissionCheckTimer()
    }

    deinit {
        permissionCheckTimer?.invalidate()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("DockMonitor 已销毁")
    }

    private func startPermissionCheckTimer() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAndStartEventTap()
        }
    }

    private func checkAndStartEventTap() {
        let trusted = AXIsProcessTrusted()
        if trusted && eventTap == nil {
            tryStartEventTap()
        }
    }

    private func startWorkspaceMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSLog("[DockMonitor] NSWorkspace 通知已注册")
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        currentFrontmostPID = app.processIdentifier
        currentFrontmostName = app.localizedName
        NSLog("[DockMonitor] 应用激活: %@ (PID: %d)", app.localizedName ?? "Unknown", app.processIdentifier)
    }

    private func tryStartEventTap() {
        let trusted = AXIsProcessTrusted()
        NSLog("[DockMonitor] 辅助功能权限: %@", trusted ? "已授权" : "未授权")

        guard trusted else {
            NSLog("[DockMonitor] 请前往: 系统设置 → 隐私与安全性 → 辅助功能")
            return
        }

        if eventTap != nil { return }
        startEventTap()
    }

    private func startEventTap() {
        NSLog("[DockMonitor] 开始创建 CGEventTap...")

        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: globalEventCallback,
            userInfo: selfPointer
        ) else {
            NSLog("[DockMonitor] ⚠️ 无法创建 CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[DockMonitor] ✓ CGEventTap 已启用")
        }
    }

    /// Get the name of the app whose Dock icon is at the given click location
    /// - Parameter clickPoint: The click location in Quartz coordinates (origin at top-left)
    private func getAppNameAtDockLocation(_ clickPoint: CGPoint) -> String? {
        // Find Dock process
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            NSLog("[DockMonitor] 未找到 Dock 进程")
            return nil
        }

        let dockPID = dockApp.processIdentifier
        let dockAppRef = AXUIElementCreateApplication(dockPID)

        NSLog("[DockMonitor] 点击坐标: (%.0f, %.0f)", clickPoint.x, clickPoint.y)

        // Try to find AXList by iterating children
        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(dockAppRef, kAXChildrenAttribute as CFString, &childrenValue)

        guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
            NSLog("[DockMonitor] 无法获取 Dock 子元素, 错误: %ld", childrenResult.rawValue)
            return nil
        }

        NSLog("[DockMonitor] Dock 有 %ld 个子元素", children.count)

        // Find the AXList (contains all dock icons)
        for child in children {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)

            guard let role = roleValue as? String else {
                NSLog("[DockMonitor] 子元素无 role")
                continue
            }

            NSLog("[DockMonitor] 子元素 role: %@", role)

            guard role == kAXListRole as String else {
                continue
            }

            // Get all items in the list
            var itemsValue: AnyObject?
            let itemsResult = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemsValue)

            guard itemsResult == .success, let items = itemsValue as? [AXUIElement] else {
                NSLog("[DockMonitor] 无法获取列表项, 错误: %ld", itemsResult.rawValue)
                continue
            }

            NSLog("[DockMonitor] Dock 列表有 %ld 个项目", items.count)

            // Find which item contains the click point
            for (index, item) in items.enumerated() {
                // Get role first to check type
                var itemRoleValue: AnyObject?
                AXUIElementCopyAttributeValue(item, kAXRoleAttribute as CFString, &itemRoleValue)

                // Get position and size
                var positionValue: AnyObject?
                var sizeValue: AnyObject?

                let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
                let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)

                guard posResult == .success, sizeResult == .success,
                      let posVal = positionValue, let sizeVal = sizeValue else {
                    continue
                }

                // Convert AXValue to CGPoint/CGSize
                var position = CGPoint.zero
                var size = CGSize.zero

                guard AXValueGetValue(posVal as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
                    continue
                }

                // Check if click point is within this item's bounds
                let rect = CGRect(x: position.x, y: position.y, width: size.width, height: size.height)

                NSLog("[DockMonitor] 项目 %ld: position=(%.0f, %.0f), size=(%.0f, %.0f), click=(%.0f, %.0f)",
                      index, position.x, position.y, size.width, size.height, clickPoint.x, clickPoint.y)

                if rect.contains(clickPoint) {
                    // Get the title (app name)
                    var titleValue: AnyObject?
                    let titleResult = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)

                    let title = (titleResult == .success) ? (titleValue as? String ?? "无标题") : "无标题"

                    // Get role description to check if it's an app icon
                    var roleDescValue: AnyObject?
                    AXUIElementCopyAttributeValue(item, kAXRoleDescriptionAttribute as CFString, &roleDescValue)

                    let roleDesc = (roleDescValue as? String) ?? "无描述"

                    NSLog("[DockMonitor] 点击了项目 %ld: title=%@, roleDesc=%@, role=%@", index, title, roleDesc, itemRoleValue as? String ?? "无")

                    // Only handle "应用程序的程序坞项目" (application dock item)
                    if roleDesc.contains("应用程序") || roleDesc.contains("application") {
                        NSLog("[DockMonitor] 找到应用图标: %@", title)
                        return title
                    }

                    NSLog("[DockMonitor] 不是应用图标，跳过")
                    return nil
                }
            }
        }

        NSLog("[DockMonitor] 未找到点击位置对应的应用")
        return nil
    }

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        guard type == .leftMouseDown else { return false }

        let location = event.location

        // Get screen dimensions using CGDisplay (Quartz coordinates)
        let mainScreenID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(mainScreenID)
        let screenHeight = displayBounds.height

        NSLog("[DockMonitor] 鼠标点击: (%.0f, %.0f), 屏幕高度: %.0f", location.x, location.y, screenHeight)

        let dockHeight: CGFloat = 100

        // Check if click is in Dock area (bottom of screen in Quartz coords)
        guard location.y >= screenHeight - dockHeight else {
            NSLog("[DockMonitor] 不在 Dock 区域 (y < %.0f)", screenHeight - dockHeight)
            return false
        }

        NSLog("[DockMonitor] Dock 区域点击: (%.0f, %.0f)", location.x, location.y)

        // Get which app's icon was clicked
        guard let clickedAppName = getAppNameAtDockLocation(location) else {
            NSLog("[DockMonitor] 点击的不是应用图标，忽略")
            return false
        }

        NSLog("[DockMonitor] 点击的应用: %@, 当前前台: %@", clickedAppName, currentFrontmostName ?? "无")

        // Check if clicked app is the current frontmost app
        guard let frontmostName = currentFrontmostName,
              clickedAppName == frontmostName || clickedAppName.contains(frontmostName) || frontmostName.contains(clickedAppName) else {
            NSLog("[DockMonitor] 点击的是其他应用，不触发最小化")
            return false
        }

        NSLog("[DockMonitor] *** 点击前台应用图标，触发切换 ***")

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            NSLog("[DockMonitor] 切换应用窗口状态: %@", frontApp.localizedName ?? "Unknown")
            let shouldConsume = WindowMinimizer.shared.toggleMinimization(app: frontApp)
            // 最小化时消费事件（阻止系统重新激活应用）
            // 恢复时让系统处理事件（系统会激活应用并恢复窗口）
            return shouldConsume
        }

        return false
    }
}