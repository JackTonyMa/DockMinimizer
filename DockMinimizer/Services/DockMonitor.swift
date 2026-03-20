import Cocoa
import Carbon

// Global callback function for CGEventTap
private func globalEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let consumed = monitor.handleEvent(proxy: proxy, type: type, event: event)

    return consumed ? nil : Unmanaged.passRetained(event)
}

/// Monitors Dock icon clicks
class DockMonitor {
    private var currentFrontmostPID: pid_t?
    private var currentFrontmostName: String?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?

    init() {
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
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        currentFrontmostPID = app.processIdentifier
        currentFrontmostName = app.localizedName
    }

    private func tryStartEventTap() {
        let trusted = AXIsProcessTrusted()

        guard trusted else { return }

        if eventTap != nil { return }
        startEventTap()
    }

    private func startEventTap() {
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
            LogService.shared.log(level: .error, category: "DockMonitor", message: "无法创建 CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
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