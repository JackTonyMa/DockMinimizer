import Foundation
import Cocoa

/// 日志级别
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// 统一日志服务
class LogService {
    static let shared = LogService()

    private let logDirectory: URL
    private let logFileURL: URL
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter

    /// 日志开关（持久化存储）
    var loggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "loggingEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "loggingEnabled")
            if newValue {
                log(category: "LogService", message: "日志记录已启用")
            }
        }
    }

    private init() {
        // 日志目录: ~/Library/Logs/DockMinimizer/
        logDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("DockMinimizer")

        logFileURL = logDirectory.appendingPathComponent("app.log")

        // 日期格式化
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // 确保目录存在
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // 启动时清理旧日志
        cleanOldLogs()
    }

    /// 写入日志
    func log(level: LogLevel = .info, category: String, message: String) {
        guard loggingEnabled else { return }

        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)\n"

        // 写入文件
        if let data = logLine.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }

        // 同时输出到控制台（调试用）
        print(logLine, terminator: "")
    }

    /// 在 Finder 中打开日志目录
    func openLogFolder() {
        // 确保目录存在
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        NSWorkspace.shared.open(logDirectory)
    }

    /// 清理所有日志
    func clearLogs() {
        try? fileManager.removeItem(at: logFileURL)
        log(category: "LogService", message: "日志已清理")
    }

    /// 清理 7 天前的日志
    private func cleanOldLogs() {
        guard fileManager.fileExists(atPath: logFileURL.path),
              let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return
        }

        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let cutoffString = dateFormatter.string(from: sevenDaysAgo)

        let lines = content.components(separatedBy: "\n")
        let recentLines = lines.filter { line in
            guard line.hasPrefix("[") else { return false }
            let startIndex = line.index(line.startIndex, offsetBy: 1)
            let endIndex = line.index(startIndex, offsetBy: 19)
            guard endIndex <= line.endIndex else { return false }
            let timestamp = String(line[startIndex..<endIndex])
            return timestamp >= cutoffString
        }

        if recentLines.count < lines.count - 1 { // -1 因为最后可能是空行
            try? recentLines.joined(separator: "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// 获取日志文件路径（用于显示）
    var logFilePath: String {
        return logFileURL.path
    }
}