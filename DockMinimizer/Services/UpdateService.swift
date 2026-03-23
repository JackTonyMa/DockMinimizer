import Foundation
import Cocoa

/// 更新检查策略
enum UpdateCheckPolicy: String, CaseIterable {
    case onStartup = "onStartup"       // 每次启动时
    case daily = "daily"               // 每天
    case weekly = "weekly"             // 每周
    case disabled = "disabled"         // 关闭自动检查

    var displayName: String {
        switch self {
        case .onStartup:
            return NSLocalizedString("On Startup", comment: "")
        case .daily:
            return NSLocalizedString("Daily", comment: "")
        case .weekly:
            return NSLocalizedString("Weekly", comment: "")
        case .disabled:
            return NSLocalizedString("Disabled", comment: "")
        }
    }

    /// 对应的检查间隔（秒）
    var checkInterval: TimeInterval? {
        switch self {
        case .onStartup:
            return nil  // 启动时检查，无间隔限制
        case .daily:
            return 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .disabled:
            return nil
        }
    }
}

/// GitHub Release 数据模型
struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let body: String?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
        case publishedAt = "published_at"
    }
}

/// 更新检查服务
class UpdateService: ObservableObject {
    static let shared = UpdateService()

    // MARK: - Published Properties

    /// 是否正在检查更新
    @Published var isChecking = false

    /// 是否有可用更新
    @Published var updateAvailable = false

    /// 最新版本号
    @Published var latestVersion: String?

    /// Release 页面 URL
    @Published var releaseURL: URL?

    /// 错误信息
    @Published var errorMessage: String?

    /// 更新检查策略
    @Published var checkPolicy: UpdateCheckPolicy {
        didSet {
            UserDefaults.standard.set(checkPolicy.rawValue, forKey: checkPolicyKey)
        }
    }

    // MARK: - Properties

    /// 当前版本号
    let currentVersion: String

    /// GitHub 仓库信息
    private let githubOwner = "JackTonyMa"
    private let githubRepo = "DockMinimizer"

    /// API URL
    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }

    /// 上次检查时间缓存 key
    private let lastCheckKey = "lastUpdateCheckTime"

    /// 检查策略缓存 key
    private let checkPolicyKey = "updateCheckPolicy"

    // MARK: - Initialization

    private init() {
        // 从 Bundle 获取当前版本
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            currentVersion = version
        } else {
            currentVersion = "1.0"
        }

        // 加载保存的策略
        if let savedPolicy = UserDefaults.standard.string(forKey: checkPolicyKey),
           let policy = UpdateCheckPolicy(rawValue: savedPolicy) {
            checkPolicy = policy
        } else {
            checkPolicy = .onStartup  // 默认启动时检查
        }
    }

    // MARK: - Public Methods

    /// 检查更新
    /// - Parameter force: 是否强制检查（忽略时间限制和策略）
    func checkForUpdates(force: Bool = false) async {
        // 非强制检查时，检查是否需要跳过
        if !force {
            // 如果禁用了自动检查，跳过
            if checkPolicy == .disabled {
                LogService.shared.log(category: "UpdateService", message: "跳过更新检查（自动检查已禁用）")
                return
            }

            // 检查是否在时间间隔内
            if !shouldCheckForUpdates() {
                LogService.shared.log(category: "UpdateService", message: "跳过更新检查（时间间隔内已检查）")
                return
            }
        }

        await MainActor.run {
            isChecking = true
            errorMessage = nil
        }

        LogService.shared.log(category: "UpdateService", message: "开始检查更新，当前版本: \(currentVersion)")

        do {
            let release = try await fetchLatestRelease()

            // 解析版本号（去掉 v 前缀）
            let latestVersionRaw = release.tagName
            let latestVersionClean = latestVersionRaw.hasPrefix("v")
                ? String(latestVersionRaw.dropFirst())
                : latestVersionRaw

            let hasUpdate = isNewerVersion(latestVersionClean, than: currentVersion)

            await MainActor.run {
                self.latestVersion = latestVersionClean
                self.updateAvailable = hasUpdate
                self.releaseURL = URL(string: release.htmlUrl)
                self.isChecking = false

                // 记录检查时间
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            }

            LogService.shared.log(category: "UpdateService",
                message: "检查完成，最新版本: \(latestVersionClean)，有更新: \(hasUpdate)")

        } catch {
            await MainActor.run {
                self.isChecking = false
                self.errorMessage = error.localizedDescription
            }

            LogService.shared.log(level: .error, category: "UpdateService",
                message: "检查更新失败: \(error.localizedDescription)")
        }
    }

    /// 打开 Release 页面
    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        } else {
            // 如果没有获取到 Release URL，打开仓库主页
            if let url = URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 打开 GitHub 仓库主页
    func openGitHubPage() {
        if let url = URL(string: "https://github.com/\(githubOwner)/\(githubRepo)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private Methods

    /// 判断是否应该检查更新
    private func shouldCheckForUpdates() -> Bool {
        // 启动时检查策略：每次启动都检查（由 AppDelegate 控制）
        if checkPolicy == .onStartup {
            return true
        }

        guard let interval = checkPolicy.checkInterval else {
            return false
        }

        guard let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastCheck) >= interval
    }

    /// 获取最新 Release 信息
    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// 比较版本号，判断是否有新版本
    private func isNewerVersion(_ newVersion: String, than currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(newComponents.count, currentComponents.count)

        for i in 0..<maxCount {
            let new = i < newComponents.count ? newComponents[i] : 0
            let current = i < currentComponents.count ? currentComponents[i] : 0

            if new > current {
                return true
            } else if new < current {
                return false
            }
        }

        return false // 版本相同
    }
}

// MARK: - Error Types

enum UpdateError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError:
            return "Failed to parse update information"
        }
    }
}