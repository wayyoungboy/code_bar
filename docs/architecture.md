# CodeBar 架构文档

> 版本：2.2.0  
> 框架：SwiftUI + AppKit  
> 平台：macOS 13+

## 概述

CodeBar 是一个 macOS 菜单栏应用，用于监控多个 AI Coding 平台的用量。应用常驻菜单栏，通过 SwiftUI popover 展示用量卡片，并通过设置窗口管理监控模块、凭据、展示项和通知选项。一个监控模块对应一组供应商凭据，ZenMux 多账号也会拆成多个独立模块；除 ZenMux 外，每个供应商最多只能添加一个模块。

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
| 本地配置 | `~/.code_bar/` + UserDefaults |
| 网络请求 | `URLSession` |
| 发布 | GitHub Actions + GitHub Releases |

## 菜单栏展示

菜单栏由 `CodeBarApp` 管理 `NSStatusItem`。多模块展示模式由 `MenuBarDisplayMode` 控制：`independent` 模式下，每个开启「bar栏展示」的监控模块都会创建一个独立 `NSStatusItem`，因此用户可以在 macOS 菜单栏中单独拖动每个模块；`rotating` 模式下，多个模块共用一个 `NSStatusItem`，按模块顺序和 `Constants.rotationInterval` 自动切换。点击任意状态项都会打开同一个详情 popover。

单个模块配置多个展示项时，菜单栏状态文本会分为上下两层展示，例如 `5h 8%` / `7d 1%`。如果用户在模块中启用了对应展示项的重置时间，状态文本会追加紧凑剩余时间，例如 `5h 8%(3h20m)`。如果模块只展示一个配额项，则状态文本保持单行较大字号。

平台图标优先使用 `Assets.xcassets` 中的品牌资产：

- `CodexLogo`
- `ZenMuxLogo`
- `XiaomiLogo`

未配置品牌资产的平台使用 `PlatformType.icon` 中的 SF Symbol 兜底。商标与 Logo 来源声明维护在 `README.md`。

## 核心模块

```text
CodeBar/
├── CodeBarApp.swift
├── MenuBarView.swift
├── SettingsWindow.swift
├── UsageTracker.swift
├── Constants.swift
├── CodeBarFileStore.swift
├── UpdateChecker.swift
├── Assets.xcassets
└── Providers/
    ├── PlatformProvider.swift
    ├── BailianProvider.swift
    ├── ZenMuxProvider.swift
    ├── MimoProvider.swift
    └── CodexProvider.swift
```

## 数据模型

`MonitorModule` 是设置页、详情页和菜单栏的核心配置单元：

```swift
struct MonitorModule {
    var id: String
    var alias: String
    var config: MonitorModuleConfig
    var isMonitoringEnabled: Bool
    var showInMenuBar: Bool
    var showInDetail: Bool
    var metricSelectionMode: MetricSelectionMode
    var displayKeys: [String]
    var resetTimeKeys: [String]
    var sortOrder: Int
}
```

`MonitorModuleConfig` 用 enum 包装各供应商配置。`UsageTracker.provider(for:)` 会把模块配置转换成对应 Provider。ZenMux 模块只包含一个 `ZenMuxAccountConfig`，所以多个 ZenMux 账号不会在 UI 层聚合成一张平台卡片。

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
    var accountBreakdowns: [AccountUsageData]
}
```

每个平台可以返回任意数量的 `UsageItem`，例如 5 小时、7 天、月用量或总用量。详情页渲染 Provider 当前实际返回的全部项目；菜单栏通过 `metricSelectionMode` 和 `displayKeys` 选择最多两项，并在已选项目暂时缺失时使用其他可用项目补位。

`AccountUsageData` 仍保留给 Provider 表达子账号明细，但当前主 UI 以 `MonitorModule` 为展示边界。ZenMux 在模块模式下是一账号一模块，详情页不会再按平台聚合多个账号。

## 刷新流程

1. `CodeBarApp` 启动并创建共享的 `UsageTracker`
2. `UsageTracker.loadModules()` 从 `~/.code_bar/MonitorModules.json` 加载监控模块
3. 用户在设置页添加或编辑模块后，`refresh()` 按模块创建 Provider 并调用 `fetchUsage()`
4. 成功结果写入 `moduleUsages[module.id]`
5. 失败信息写入 `moduleErrors[module.id]`
6. SwiftUI 视图订阅 `@Published` 状态并刷新 UI
7. 定时器每 60 秒加随机 jitter 自动刷新

## Provider 行为

| Provider | 凭据来源 | 主要用量 |
| --- | --- | --- |
| BailianProvider | CodeBar `~/.code_bar/` 配置 | 账单月、5 小时、周 |
| ZenMuxProvider | CodeBar `~/.code_bar/` 多账号配置 | 5 小时、7 天 |
| MimoProvider | CodeBar `~/.code_bar/` 配置 | 月用量、总用量 |
| CodexProvider | `~/.codex/auth.json` | 5 小时、7 天、额外 rate limits |

## Codex 设计

Codex 不在 CodeBar 中保存 token。Provider 只读取已有 Codex CLI OAuth 文件：`~/.codex/auth.json`。

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

- 监控模块配置存储在 `~/.code_bar/MonitorModules.json`
- 平台配置存储在 `~/.code_bar/PlatformConfigs.json`
- 模块内包含供应商凭据、别名、展示开关、模块级通知开关、显示项、重置时间项和排序
- 用量缓存存储在 UserDefaults
- ZenMux 的别名、API Key、展示项和重置时间项都是模块级配置
- Codex OAuth token 不复制到 CodeBar 配置，只读取 Codex CLI 已存在的文件凭据

## 发布流程

发布由 GitHub Actions 完成：

1. 更新 `CodeBar/Info.plist` 的 `CFBundleShortVersionString`
2. 提交版本变更
3. 创建并推送 `v*` tag
4. `.github/workflows/release.yml` 构建 Release app
5. CI ad-hoc sign、生成 `CodeBar.dmg` 并上传 GitHub Release

本地构建只用于验证，不需要手动上传 DMG。
