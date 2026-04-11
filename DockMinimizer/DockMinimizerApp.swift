import SwiftUI
import Cocoa
import ServiceManagement

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            setEnabled(isEnabled)
        }
    }

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}

struct SettingsView: View {
    @AppStorage("loggingEnabled") private var loggingEnabled = false
    @AppStorage("showPanelOnLaunch") private var showPanelOnLaunch = true
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @StateObject private var dockMonitor = DockMonitor.shared
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading) {
                    Text("DockMinimizer")
                        .font(.headline)
                    Text(L10n.settingsSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Language Setting
            HStack {
                Text(L10n.language)
                Spacer()
                Picker("", selection: Binding(
                    get: { localizationManager.currentLanguage },
                    set: { localizationManager.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .frame(width: 120)
            }

            // Launch at Login
            Toggle(L10n.launchAtLogin, isOn: Binding(
                get: { launchAtLoginManager.isEnabled },
                set: { launchAtLoginManager.isEnabled = $0 }
            ))
            .help(L10n.launchAtLoginHelp)

            // Show Panel on Launch
            Toggle(L10n.showPanelOnLaunch, isOn: $showPanelOnLaunch)
                .help(L10n.showPanelOnLaunchHelp)

            Divider()

            // 辅助功能权限状态
            HStack {
                if dockMonitor.isFullyFunctional {
                    Label(L10n.permissionGranted, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label(L10n.permissionNotGranted, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                Spacer()
            }

            if !dockMonitor.isFullyFunctional {
                HStack {
                    Button(L10n.openSystemSettings) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Spacer()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.enabled, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text(L10n.runningDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle(L10n.enableLogging, isOn: $loggingEnabled)
                .help(L10n.enableLoggingHelp)

            if loggingEnabled {
                HStack {
                    Text(L10n.logLocation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            // 更新检查区域
            VStack(alignment: .leading, spacing: 8) {
                // 自动检查策略
                HStack {
                    Text(L10n.autoCheckPolicy)
                        .font(.caption)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { updateService.checkPolicy },
                        set: { updateService.checkPolicy = $0 }
                    )) {
                        ForEach(UpdateCheckPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .frame(width: 90)
                }

                // 版本信息
                HStack {
                    Text(L10n.currentVersion)
                        .font(.caption)
                    Text(updateService.currentVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if updateService.isChecking {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(L10n.checkingForUpdates)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if updateService.updateAvailable {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text(L10n.updateAvailable)
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    HStack {
                        Text("\(L10n.latestVersion): \(updateService.latestVersion ?? "?")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let error = updateService.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(2)
                        Spacer()
                    }
                }

                HStack {
                    Button(L10n.checkNow) {
                        Task {
                            await updateService.checkForUpdates(force: true)
                        }
                    }
                    .disabled(updateService.isChecking)

                    if updateService.updateAvailable {
                        Button(L10n.downloadUpdate) {
                            updateService.openReleasePage()
                        }
                    }

                    Spacer()

                    Button(L10n.visitGitHub) {
                        updateService.openGitHubPage()
                    }
                }
            }

            Divider()

            HStack {
                if loggingEnabled {
                    Button(L10n.viewLogs) {
                        LogService.shared.openLogFolder()
                    }
                }
                Spacer()
                Button(L10n.quitApp) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

#Preview {
    SettingsView()
}

// MARK: - App

@main
struct DockMinimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(L10n.settingsWindowTitle, id: "settings") {
            SettingsView()
        }
        .windowStyle(.automatic)
        .defaultPosition(.center)
        .defaultSize(width: 320, height: 560)
        .commands {
            // 隐藏默认的 Window 菜单项
            CommandGroup(replacing: .windowArrangement) { }
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
