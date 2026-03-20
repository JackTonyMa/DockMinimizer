import SwiftUI

struct SettingsView: View {
    @AppStorage("loggingEnabled") private var loggingEnabled = false
    @State private var hasPermission = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading) {
                    Text("DockMinimizer")
                        .font(.headline)
                    Text("点击 Dock 图标最小化窗口")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 辅助功能权限状态
            HStack {
                if hasPermission {
                    Label("辅助功能权限已授权", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("辅助功能权限未授权", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                Spacer()
            }

            if !hasPermission {
                HStack {
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("刷新状态") {
                        refreshPermission()
                    }
                    Spacer()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("已启用", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text("应用正在后台运行，点击 Dock 中的前台应用图标即可最小化其窗口。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("启用日志记录", isOn: $loggingEnabled)
                .help("开启后记录应用操作日志，方便排查问题")

            if loggingEnabled {
                HStack {
                    Text("日志位置: ~/Library/Logs/DockMinimizer/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            HStack {
                if loggingEnabled {
                    Button("查看日志") {
                        LogService.shared.openLogFolder()
                    }
                }
                Spacer()
                Button("退出应用") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            refreshPermission()
        }
    }

    private func refreshPermission() {
        hasPermission = AXIsProcessTrusted()
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