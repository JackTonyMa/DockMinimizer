import SwiftUI
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
    @State private var hasPermission = false
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @State private var permissionCheckTimer: Timer?

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

            Divider()

            // 辅助功能权限状态
            HStack {
                if hasPermission {
                    Label(L10n.permissionGranted, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label(L10n.permissionNotGranted, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                Spacer()
            }

            if !hasPermission {
                HStack {
                    Button(L10n.openSystemSettings) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button(L10n.refreshStatus) {
                        refreshPermission()
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
        .onAppear {
            refreshPermission()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: hasPermission) { newValue in
            if newValue {
                stopAutoRefresh()
            }
        }
    }

    private func refreshPermission() {
        hasPermission = AXIsProcessTrusted()
    }

    private func startAutoRefresh() {
        guard !hasPermission else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                refreshPermission()
            }
        }
    }

    private func stopAutoRefresh() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
}

#Preview {
    SettingsView()
}

@main
struct DockMinimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
        .windowStyle(.automatic)
        .defaultPosition(.center)
        .defaultSize(width: 320, height: 320)

        Settings {
            SettingsView()
        }
    }
}