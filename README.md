# DockMinimizer

点击 Dock 图标隐藏应用窗口 — 一个优雅的 macOS 后台工具

[中文](#中文说明) | [English](#english)

---

## English

### Introduction

DockMinimizer is a lightweight macOS background utility that brings Windows-style taskbar behavior to macOS. Click the Dock icon of the active application to hide all its windows — just like clicking a taskbar button in Windows.

### Features

- 🎯 **One-click hide**: Click the active app's Dock icon to hide its windows
- 🔄 **Toggle restore**: Click the same Dock icon again to restore all windows
- 🪟 **Windows-style workflow**: Familiar behavior for users switching from Windows
- 🔒 **Privacy first**: Runs locally, no network requests, no data collection
- 📝 **Optional logging**: Built-in log service for troubleshooting (disabled by default)

### Requirements

- macOS 15.0 or later
- Accessibility permissions required (will prompt on first launch)

### Installation

1. **Build from source**
   ```bash
   git clone https://github.com/YOUR_USERNAME/DockMinimizer.git
   cd DockMinimizer
   xcodebuild -project DockMinimizer.xcodeproj -scheme DockMinimizer -configuration Release build
   ```

2. **Or open in Xcode**
   - Open `DockMinimizer.xcodeproj` in Xcode
   - Build and run (⌘R)

### Usage

1. Launch DockMinimizer — it runs in the background (status bar shows its status)
2. Grant Accessibility permissions when prompted
3. Click any active application's Dock icon to hide all its windows
4. Click the same Dock icon again to restore all windows

### Status Bar Menu

- **Settings...** — Open settings window (language, logging, etc.)
- **DockMinimizer Running** — App status indicator
- **Check Permissions** — Verify accessibility access
- **View Logs** — Open log folder in Finder
- **Quit (⌘Q)** — Exit the application

### Settings

- **Language** — Switch between English, 简体中文, or follow system
- **Launch at Login** — Automatically start when you log in
- **Logging** — Enable/disable operation logging for troubleshooting

### Technical Details

**Architecture:**
- SwiftUI + AppDelegate lifecycle pattern
- CGEventTap for global Dock click monitoring
- Accessibility API (AXUIElement) for hiding apps
- Local file-based logging service

**Key Files:**
```
DockMinimizer/
├── DockMinimizerApp.swift    # App entry point
├── AppDelegate.swift         # Status bar & permissions
├── Services/
│   ├── DockMonitor.swift     # Dock click monitoring
│   ├── WindowMinimizer.swift # App hiding logic
│   └── LogService.swift      # Logging service
└── Models/
    └── AppState.swift        # App state model
```

### Troubleshooting

**App doesn't hide:**
- Check Accessibility permissions in System Settings → Privacy & Security → Accessibility
- Use "Check Permissions" from the status bar menu

**Logs location:** `~/Library/Logs/DockMinimizer/app.log`

### License

MIT License

---

## Contributing Translations / 贡献翻译

We welcome community contributions for translations! Here's how to add a new language:

### Supported Languages / 支持的语言

| Language | Code | Status |
|----------|------|--------|
| English | `en` | ✅ Complete |
| 简体中文 | `zh-Hans` | ✅ Complete |

### How to Add a New Language / 如何添加新语言

1. Navigate to `DockMinimizer/Resources/` directory
2. Create a new folder named `{language-code}.lproj` (e.g., `ja.lproj` for Japanese)
3. Copy `en.lproj/Localizable.strings` to your new folder
4. Translate the strings in the copied file
5. Submit a pull request!

### Example / 示例

For Japanese (`ja`):
```bash
mkdir -p DockMinimizer/Resources/ja.lproj
cp DockMinimizer/Resources/en.lproj/Localizable.strings DockMinimizer/Resources/ja.lproj/
# Edit the .strings file with Japanese translations
```

### File Structure / 文件结构

```
DockMinimizer/Resources/
├── en.lproj/
│   └── Localizable.strings    # English
├── zh-Hans.lproj/
│   └── Localizable.strings    # Simplified Chinese
└── {your-lang}.lproj/
    └── Localizable.strings    # Your translation
```

### String Keys Reference / 字符串键参考

| Key | Description |
|-----|-------------|
| `Settings...` | Menu item to open settings |
| `DockMinimizer Running` | Status indicator in menu |
| `Check Permissions` | Menu item to check accessibility |
| `View Logs` | Menu item to open log folder |
| `Quit (⌘Q)` | Menu item to quit app |
| `Accessibility Permission Granted` | Permission status label |
| `Enable Logging` | Toggle for logging feature |

---

---

## 中文说明

### 简介

DockMinimizer 是一款轻量级 macOS 后台工具，为 macOS 带来 Windows 任务栏的操作习惯。点击当前激活应用的 Dock 图标，即可隐藏该应用的所有窗口 — 就像在 Windows 中点击任务栏按钮一样。

### 功能特性

- 🎯 **一键隐藏**：点击当前应用 Dock 图标，隐藏其所有窗口
- 🔄 **切换恢复**：再次点击同一 Dock 图标，恢复所有窗口
- 🪟 **Windows 风格操作**：从 Windows 切换过来的用户无需改变习惯
- 🔒 **隐私优先**：本地运行，无网络请求，无数据收集
- 📝 **可选日志**：内置日志服务便于排查问题（默认关闭）

### 系统要求

- macOS 15.0 或更高版本
- 需要辅助功能权限（首次启动时会提示）

### 安装方法

1. **源码编译**
   ```bash
   git clone https://github.com/YOUR_USERNAME/DockMinimizer.git
   cd DockMinimizer
   xcodebuild -project DockMinimizer.xcodeproj -scheme DockMinimizer -configuration Release build
   ```

2. **或使用 Xcode**
   - 在 Xcode 中打开 `DockMinimizer.xcodeproj`
   - 编译并运行 (⌘R)

### 使用方法

1. 启动 DockMinimizer — 它在后台运行（状态栏显示状态）
2. 根据提示授予辅助功能权限
3. 点击任意激活应用的 Dock 图标，隐藏其所有窗口
4. 再次点击同一 Dock 图标，恢复所有窗口

### 状态栏菜单

- **设置...** — 打开设置窗口（语言、日志等）
- **DockMinimizer 运行中** — 应用状态指示
- **检查权限** — 验证辅助功能访问权限
- **查看日志** — 在访达中打开日志文件夹
- **退出 (⌘Q)** — 退出应用

### 设置

- **语言** — 切换 English、简体中文 或跟随系统
- **开机自启** — 登录时自动启动应用
- **日志** — 启用/禁用操作日志便于排查问题

### 技术细节

**架构：**
- SwiftUI + AppDelegate 生命周期模式
- CGEventTap 全局 Dock 点击监控
- Accessibility API (AXUIElement) 应用隐藏
- 本地文件日志服务

**关键文件：**
```
DockMinimizer/
├── DockMinimizerApp.swift    # 应用入口
├── AppDelegate.swift         # 状态栏与权限管理
├── Services/
│   ├── DockMonitor.swift     # Dock 点击监控
│   ├── WindowMinimizer.swift # 应用隐藏逻辑
│   └── LogService.swift      # 日志服务
└── Models/
    └── AppState.swift        # 应用状态模型
```

### 常见问题

**无法隐藏窗口：**
- 检查系统设置 → 隐私与安全性 → 辅助功能 中的权限
- 使用状态栏菜单中的"检查权限"功能

**日志位置：** `~/Library/Logs/DockMinimizer/app.log`

### 许可证

MIT License
