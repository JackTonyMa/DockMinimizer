import Cocoa
import Carbon
import UserNotifications

/// 检测 Accessibility API 是否真正可用
func isAccessibilityActuallyWorking() -> Bool {
    guard AXIsProcessTrusted() else { return false }
    guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        return false
    }
    let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(dockRef, kAXChildrenAttribute as CFString, &value)
    return result == .success
}

// Global callback function for CGEventTap
private func globalEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // 处理 tap 被禁用的事件（权限被撤销或超时）
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        LogService.shared.log(level: .warning, category: "DockMonitor", message: "[回调] 检测到 tap 禁用事件")
        monitor.handleTapDisabled()
        return Unmanaged.passRetained(event)
    }

    // 检查 tap 是否仍然有效
    if let tap = monitor.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
        LogService.shared.log(level: .warning, category: "DockMonitor", message: "[回调] tap 已被禁用，立即停止并返回事件")
        monitor.handleTapDisabled()
        return Unmanaged.passRetained(event)
    }

    // 使用轻量的权限检查，避免在回调中执行可能阻塞的 API 调用
    // AXIsProcessTrusted() 是非阻塞的，而 isAccessibilityActuallyWorking() 可能会阻塞
    if !AXIsProcessTrusted() {
        LogService.shared.log(level: .warning, category: "DockMonitor", message: "[回调] 权限已撤销，立即停止并返回事件")
        monitor.handleTapDisabled()
        return Unmanaged.passRetained(event)
    }

    let consumed = monitor.handleEvent(proxy: proxy, type: type, event: event)
    return consumed ? nil : Unmanaged.passRetained(event)
}

/// Monitors Dock icon clicks
class DockMonitor: ObservableObject {
    static let shared = DockMonitor()

    private var currentFrontmostPID: pid_t?
    private var currentFrontmostName: String?
    var eventTap: CFMachPort?  // internal 访问级别，供回调函数使用
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?
    private var lastPermissionState: Bool = false  // 记录上次权限状态，用于检测变化

    /// 权限和功能是否完全可用
    @Published var isFullyFunctional: Bool = false

    private init() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            currentFrontmostPID = frontApp.processIdentifier
            currentFrontmostName = frontApp.localizedName
        }

        startWorkspaceMonitoring()
        tryStartEventTap()
        startPermissionCheckTimer()
    }

    deinit {
        permissionCheckTimer?.invalidate()
        stopEventTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func startPermissionCheckTimer() {
        // 根据当前权限状态决定检查间隔
        let apiWorking = isAccessibilityActuallyWorking()
        let interval: TimeInterval = apiWorking ? 5.0 : 1.0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermissionState()
        }
        lastPermissionState = apiWorking
        // 立即检查一次权限状态，确保 isFullyFunctional 值正确
        checkPermissionState()
        LogService.shared.log(category: "DockMonitor", message: "[定时器] 已启动，间隔 \(interval) 秒，API可用: \(apiWorking ? "是" : "否")")
    }

    private func checkPermissionState() {
        // 用实际 API 检测权限是否真正有效
        let apiWorking = isAccessibilityActuallyWorking()
        let trusted = AXIsProcessTrusted()
        LogService.shared.log(category: "DockMonitor", message: "[定时器检查] AXIsProcessTrusted: \(trusted ? "是" : "否"), API实际可用: \(apiWorking ? "是" : "否"), eventTap: \(eventTap != nil ? "存在" : "不存在")")

        // 更新完整功能状态
        isFullyFunctional = trusted && apiWorking && (eventTap != nil)

        // 检测权限状态变化
        if apiWorking != lastPermissionState {
            if apiWorking {
                sendNotification(title: L10n.permissionGrantedNotificationTitle, body: L10n.permissionGrantedNotificationBody)
            } else {
                sendNotification(title: L10n.permissionRevoked, body: L10n.permissionRevokedMessage)
            }
            lastPermissionState = apiWorking
            adjustTimerInterval()
        }

        if apiWorking && eventTap == nil {
            LogService.shared.log(category: "DockMonitor", message: "[定时器检查] API 可用，尝试启动 eventTap")
            tryStartEventTap()
        } else if !apiWorking && eventTap != nil {
            // 检测到权限撤销，立即停止 tap
            LogService.shared.log(level: .warning, category: "DockMonitor", message: "[定时器检查] 检测到 API 不可用，立即停止 eventTap")
            stopEventTap()
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(request)
            }
        }
    }

    private func adjustTimerInterval() {
        permissionCheckTimer?.invalidate()
        let interval: TimeInterval = lastPermissionState ? 5.0 : 1.0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermissionState()
        }
        LogService.shared.log(category: "DockMonitor", message: "[定时器] 间隔调整为 \(interval) 秒")
    }

    private func stopEventTap() {
        LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 开始停止，eventTap: \(eventTap != nil ? "存在" : "不存在")")
        guard let tap = eventTap else {
            LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] eventTap 为空，跳过")
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 已禁用 tap")

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
            LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 已移除 runLoopSource")
        }

        eventTap = nil
        LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 完成")
    }

    /// 当 CGEventTap 被系统禁用时调用（权限被撤销或超时）
    func handleTapDisabled() {
        LogService.shared.log(level: .warning, category: "DockMonitor", message: "[handleTapDisabled] 被调用")
        DispatchQueue.main.async { [weak self] in
            LogService.shared.log(category: "DockMonitor", message: "[handleTapDisabled] 主线程执行 stopEventTap")
            self?.stopEventTap()
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
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        currentFrontmostPID = app.processIdentifier
        currentFrontmostName = app.localizedName
    }

    private func tryStartEventTap() {
        guard isAccessibilityActuallyWorking() else { return }

        if eventTap != nil { return }
        startEventTap()
    }

    private func startEventTap() {
        LogService.shared.log(category: "DockMonitor", message: "[startEventTap] 开始创建 eventTap")
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
            LogService.shared.log(level: .error, category: "DockMonitor", message: "[startEventTap] 无法创建 CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            LogService.shared.log(category: "DockMonitor", message: "[startEventTap] eventTap 创建成功并已启用")
        }
    }

    /// Get the name of the app whose Dock icon is at the given click location
    private func getAppNameAtDockLocation(_ clickPoint: CGPoint) -> String? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockPID = dockApp.processIdentifier
        let dockAppRef = AXUIElementCreateApplication(dockPID)

        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(dockAppRef, kAXChildrenAttribute as CFString, &childrenValue)

        guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)

            guard let role = roleValue as? String, role == kAXListRole as String else {
                continue
            }

            var itemsValue: AnyObject?
            let itemsResult = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemsValue)

            guard itemsResult == .success, let items = itemsValue as? [AXUIElement] else {
                continue
            }

            for item in items {
                var positionValue: AnyObject?
                var sizeValue: AnyObject?

                let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
                let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)

                guard posResult == .success, sizeResult == .success,
                      let posVal = positionValue, let sizeVal = sizeValue else {
                    continue
                }

                var position = CGPoint.zero
                var size = CGSize.zero

                guard AXValueGetValue(posVal as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
                    continue
                }

                let rect = CGRect(x: position.x, y: position.y, width: size.width, height: size.height)

                if rect.contains(clickPoint) {
                    var titleValue: AnyObject?
                    let titleResult = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                    let title = (titleResult == .success) ? (titleValue as? String ?? "无标题") : "无标题"

                    var roleDescValue: AnyObject?
                    AXUIElementCopyAttributeValue(item, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
                    let roleDesc = (roleDescValue as? String) ?? ""

                    if roleDesc.contains("应用程序") || roleDesc.contains("application") {
                        return title
                    }
                    return nil
                }
            }
        }

        return nil
    }

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        guard type == .leftMouseDown else { return false }

        let location = event.location
        let mainScreenID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(mainScreenID)
        let screenHeight = displayBounds.height

        let dockHeight: CGFloat = 100

        guard location.y >= screenHeight - dockHeight else { return false }

        guard let clickedAppName = getAppNameAtDockLocation(location) else { return false }

        guard let frontmostName = currentFrontmostName,
              clickedAppName == frontmostName || clickedAppName.contains(frontmostName) || frontmostName.contains(clickedAppName) else {
            return false
        }

        LogService.shared.log(category: "DockMonitor", message: "点击 Dock 图标: \(clickedAppName)")

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let shouldConsume = WindowMinimizer.shared.toggleMinimization(app: frontApp)
            return shouldConsume
        }

        return false
    }
}