import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var dockMonitor: DockMonitor?
    private var permissionAlertShown = false
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogService.shared.log(category: "AppDelegate", message: "应用启动: \(Bundle.main.bundlePath)")

        // Set activation policy to accessory (no dock icon, but can show status bar)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create status bar item
        createStatusItem()

        // Observe language changes
        LocalizationManager.shared.$currentLanguage
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemMenu()
                }
            }
            .store(in: &cancellables)

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
            alert.messageText = L10n.permissionRequiredTitle
            alert.informativeText = L10n.permissionRequiredMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.openSystemSettings)
            alert.addButton(withTitle: L10n.later)

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
        button.toolTip = L10n.statusBarTooltip

        updateStatusItemMenu()

        item.isVisible = true
        button.isHidden = false
    }

    private func updateStatusItemMenu() {
        guard let item = self.statusItem else { return }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: L10n.dockMinimizerRunning, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let permissionItem = NSMenuItem(title: L10n.checkPermissions, action: #selector(checkPermissionStatus), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let logItem = NSMenuItem(title: L10n.viewLogs, action: #selector(openLogFolder), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func checkPermissionStatus() {
        let hasPermission = AXIsProcessTrusted()

        if hasPermission {
            let alert = NSAlert()
            alert.messageText = L10n.permissionGrantedTitle
            alert.informativeText = L10n.permissionGrantedMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.ok)
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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsWindowTitle
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