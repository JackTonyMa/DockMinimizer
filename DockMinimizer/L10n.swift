import Foundation

enum AppLanguage: String, CaseIterable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("Follow System", comment: "")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    private var currentBundle: Bundle?

    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        self.currentLanguage = AppLanguage(rawValue: savedLanguage) ?? .system
        updateBundle()
    }

    private func updateBundle() {
        if currentLanguage == .system {
            currentBundle = nil
        } else {
            if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                currentBundle = bundle
            } else {
                currentBundle = nil
            }
        }
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        updateBundle()
    }

    func localizedString(key: String, comment: String = "") -> String {
        if let bundle = currentBundle {
            return NSLocalizedString(key, bundle: bundle, comment: comment)
        }
        return NSLocalizedString(key, comment: comment)
    }
}

enum L10n {
    private static var lm: LocalizationManager { LocalizationManager.shared }

    // Language Settings
    static var language: String { lm.localizedString(key: "Language", comment: "") }
    static var followSystem: String { lm.localizedString(key: "Follow System", comment: "") }

    // Menu Items
    static var settings: String { lm.localizedString(key: "Settings...", comment: "") }
    static var dockMinimizerRunning: String { lm.localizedString(key: "DockMinimizer Running", comment: "") }
    static var checkPermissions: String { lm.localizedString(key: "Check Permissions", comment: "") }
    static var viewLogs: String { lm.localizedString(key: "View Logs", comment: "") }
    static var quit: String { lm.localizedString(key: "Quit (⌘Q)", comment: "") }

    // Settings Window
    static var settingsWindowTitle: String { lm.localizedString(key: "DockMinimizer Settings", comment: "") }
    static var settingsSubtitle: String { lm.localizedString(key: "Click Dock icon to minimize windows", comment: "") }

    // Permission Status
    static var permissionGranted: String { lm.localizedString(key: "Accessibility Permission Granted", comment: "") }
    static var permissionNotGranted: String { lm.localizedString(key: "Accessibility Permission Not Granted", comment: "") }
    static var openSystemSettings: String { lm.localizedString(key: "Open System Settings", comment: "") }
    static var refreshStatus: String { lm.localizedString(key: "Refresh Status", comment: "") }

    // App Status
    static var enabled: String { lm.localizedString(key: "Enabled", comment: "") }
    static var runningDescription: String { lm.localizedString(key: "App is running in the background. Click the frontmost app's Dock icon to minimize its windows.", comment: "") }

    // Logging
    static var enableLogging: String { lm.localizedString(key: "Enable Logging", comment: "") }
    static var logLocation: String { lm.localizedString(key: "Log location: ~/Library/Logs/DockMinimizer/", comment: "") }
    static var quitApp: String { lm.localizedString(key: "Quit App", comment: "") }
    static var enableLoggingHelp: String { lm.localizedString(key: "Enable logging to record app operations for troubleshooting", comment: "") }

    // Launch at Login
    static var launchAtLogin: String { lm.localizedString(key: "Launch at Login", comment: "") }
    static var launchAtLoginHelp: String { lm.localizedString(key: "Automatically start DockMinimizer when you log in", comment: "") }

    // Permission Alerts
    static var permissionRequiredTitle: String { lm.localizedString(key: "Accessibility Permission Required", comment: "") }
    static var permissionRequiredMessage: String { lm.localizedString(key: "DockMinimizer requires accessibility permission to monitor and operate windows of other applications.\n\nPlease go to:\nSystem Settings → Privacy & Security → Accessibility\n\nClick the \"+\" button to add DockMinimizer to the authorized list.", comment: "") }
    static var later: String { lm.localizedString(key: "Later", comment: "") }

    // Permission Status Dialog
    static var permissionGrantedTitle: String { lm.localizedString(key: "Permission Granted", comment: "") }
    static var permissionGrantedMessage: String { lm.localizedString(key: "DockMinimizer has been granted accessibility permission and can work properly.", comment: "") }
    static var ok: String { lm.localizedString(key: "OK", comment: "") }

    // Status Bar Tooltip
    static var statusBarTooltip: String { lm.localizedString(key: "DockMinimizer - Click Dock icon to minimize windows", comment: "") }

    // Permission Notifications
    static var permissionGrantedNotificationTitle: String { lm.localizedString(key: "Permission Granted", comment: "") }
    static var permissionGrantedNotificationBody: String { lm.localizedString(key: "Accessibility permission has been granted, DockMinimizer is now active.", comment: "") }
    static var permissionRevoked: String { lm.localizedString(key: "Permission Revoked", comment: "") }
    static var permissionRevokedMessage: String { lm.localizedString(key: "Accessibility permission has been revoked, DockMinimizer has stopped working.", comment: "") }

    // Update
    static var checkForUpdates: String { lm.localizedString(key: "Check for Updates...", comment: "") }
    static var updateAvailable: String { lm.localizedString(key: "Update Available!", comment: "") }
    static var currentVersion: String { lm.localizedString(key: "Current Version", comment: "") }
    static var latestVersion: String { lm.localizedString(key: "Latest Version", comment: "") }
    static var checkingForUpdates: String { lm.localizedString(key: "Checking for updates...", comment: "") }
    static var alreadyUpToDate: String { lm.localizedString(key: "You're up to date!", comment: "") }
    static var updateError: String { lm.localizedString(key: "Failed to check for updates", comment: "") }
    static var downloadUpdate: String { lm.localizedString(key: "Download Update", comment: "") }
    static var viewOnGitHub: String { lm.localizedString(key: "View on GitHub", comment: "") }
    static var autoCheckPolicy: String { lm.localizedString(key: "Auto Check Policy", comment: "") }
    static var onStartup: String { lm.localizedString(key: "On Startup", comment: "") }
    static var daily: String { lm.localizedString(key: "Daily", comment: "") }
    static var weekly: String { lm.localizedString(key: "Weekly", comment: "") }
    static var disabled: String { lm.localizedString(key: "Disabled", comment: "") }
    static var checkNow: String { lm.localizedString(key: "Check Now", comment: "") }
    static var visitGitHub: String { lm.localizedString(key: "Visit GitHub", comment: "") }
}