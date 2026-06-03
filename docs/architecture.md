# CodeBar 架构文档

> 版本：2.1.0  
> 框架：SwiftUI + AppKit  
> 平台：macOS 13+

## 概述

CodeBar 是一个 macOS 菜单栏应用，用于监控多个 AI Coding 平台的用量。应用常驻菜单栏，通过 SwiftUI popover 展示用量卡片，并通过设置窗口管理平台凭据、展示项和通知选项。

当前支持平台：

- 阿里云百炼
- ZenMux
- 小米 MiMo
- Codex

## 技术栈

| 层次 | 技术 |
| --- | --- |
| 应用框架 | SwiftUI + AppKit |
| 菜单栏 | `NSStatusItem` + `NSPopover` |
| 数据刷新 | `UsageTracker` + `Timer` |
| 本地配置 | macOS Keychain + UserDefaults |
| 网络请求 | `URLSession` |
| 日志 | `OSLog` |
| 发布 | GitHub Actions + GitHub Releases |

## 核心模块

```text
CodeBar/
├── CodeBarApp.swift
├── MenuBarView.swift
├── SettingsWindow.swift
├── UsageTracker.swift
├── Constants.swift
├── KeychainHelper.swift
├── Logger.swift
├── UpdateChecker.swift
└── Providers/
    ├── PlatformProvider.swift
    ├── BailianProvider.swift
    ├── ZenMuxProvider.swift
    ├── MimoProvider.swift
    └── CodexProvider.swift
```

## 数据模型

`PlatformProvider` 是所有平台 Provider 的统一协议：

```swift
protocol PlatformProvider {
    var platformName: String { get }
    var isConfigured: Bool { get }
    func fetchUsage() async throws -> PlatformUsageData
    func validateConfig() async throws -> Bool
}
```

`PlatformUsageData` 是 UI 的统一输入：

```swift
struct PlatformUsageData {
    let platformName: String
    let planType: String
    let items: [UsageItem]
    var extraInfo: [(label: String, value: String)]
}
```

每个平台可以返回任意数量的 `UsageItem`，例如 5 小时、7 天、月用量或总用量。UI 不关心平台 API 细节，只按统一结构渲染进度条和额外信息。

## 刷新流程

1. `CodeBarApp` 启动并创建共享的 `UsageTracker`
2. `UsageTracker.loadConfig()` 从 Keychain 加载平台配置
3. Codex Provider 无需用户配置，启动时默认注册
4. 用户在设置页启用平台后，`refresh()` 调用各 Provider 的 `fetchUsage()`
5. 成功结果写入 `platforms` 并缓存到 UserDefaults
6. SwiftUI 视图订阅 `@Published` 状态并刷新 UI
7. 定时器每 60 秒加随机 jitter 自动刷新

## Provider 行为

| Provider | 凭据来源 | 主要用量 |
| --- | --- | --- |
| BailianProvider | CodeBar Keychain 配置 | 账单月、5 小时、周 |
| ZenMuxProvider | CodeBar Keychain 配置 | 5 小时、7 天 |
| MimoProvider | CodeBar Keychain 配置 | 月用量、总用量 |
| CodexProvider | Codex CLI Keychain / `~/.codex/auth.json` | 5 小时、7 天、额外 rate limits |

## Codex 设计

Codex 不在 CodeBar 中保存 token。Provider 按优先级读取已有 Codex CLI OAuth：

1. macOS Keychain service：`Codex Auth`
2. 文件：`~/.codex/auth.json`

仅 `auth_mode == "chatgpt"` 时可查询用量。请求接口：

```text
GET https://chatgpt.com/backend-api/wham/usage
```

请求头与 Codex CLI / cc-switch 对齐：

```text
Authorization: Bearer <access_token>
User-Agent: codex-cli
Accept: application/json
ChatGPT-Account-Id: <account_id>
```

Codex 支持可选代理。未配置代理时直接请求；配置 `http://host:port`、`https://host:port`、`socks://host:port` 或 `socks5://host:port` 时，`URLSessionConfiguration.connectionProxyDictionary` 会使用指定代理。

## 配置存储

- 平台凭据和 Codex 代理配置存储在 Keychain 的统一条目 `PlatformConfigs`
- 平台启用状态、展示项、重置时间展示项、用量缓存存储在 UserDefaults
- Codex OAuth token 不复制到 CodeBar 配置，只读取 Codex CLI 已存在的凭据

## 发布流程

发布由 GitHub Actions 完成：

1. 更新 `CodeBar/Info.plist` 的 `CFBundleShortVersionString`
2. 提交版本变更
3. 创建并推送 `v*` tag
4. `.github/workflows/release.yml` 构建 Release app
5. CI ad-hoc sign、生成 `CodeBar.dmg` 并上传 GitHub Release

本地构建只用于验证，不需要手动上传 DMG。
