# CodeBar 开发者指南

本文档面向希望扩展 CodeBar 的开发者：添加新 Provider、修改 SwiftUI UI、或发布新版本。

## 快速开始

### 环境要求

| 工具 | 要求 |
| --- | --- |
| macOS | 13.0+ |
| Xcode | 15.0+ |
| GitHub CLI | 发布时需要 |

### 构建

```bash
xcodebuild -project CodeBar.xcodeproj -scheme CodeBar -configuration Debug build
```

Release 验证：

```bash
xcodebuild -project CodeBar.xcodeproj \
  -scheme CodeBar \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 添加新 Provider

### 1. 添加平台枚举

在 `UsageTracker.swift` 的 `PlatformType` 中添加平台：

```swift
case yourPlatform = "Your Platform"
```

同时补齐：

- `icon`
- `shortName`
- `brandColor`

### 2. 添加配置模型

在 `Providers/PlatformProvider.swift` 中添加配置结构：

```swift
struct YourPlatformConfig: PlatformConfig, Codable {
    let platform: PlatformType = .yourPlatform
    var apiKey: String

    var isValid: Bool {
        !apiKey.isEmpty
    }
}
```

如果平台不需要 CodeBar 保存凭据，可以像 `CodexConfig` 一样让 `isValid` 始终为 `true`，只保存网络配置或展示配置。

### 3. 实现 Provider

在 `CodeBar/Providers/` 下创建 Provider：

```swift
struct YourPlatformProvider: PlatformProvider {
    let platformName = "Your Platform"
    private let config: YourPlatformConfig

    var isConfigured: Bool {
        config.isValid
    }

    func fetchUsage() async throws -> PlatformUsageData {
        // 1. 构造 URLRequest
        // 2. 调用 URLSession
        // 3. 解析平台响应
        // 4. 映射成 PlatformUsageData
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }
}
```

UI 只依赖 `PlatformUsageData`，Provider 可以自由定义 `UsageItem.key`、`label`、`unit` 和 `extraInfo`。

如果平台需要同平台多账号展示，可以填充 `PlatformUsageData.accountBreakdowns`。ZenMux 是当前参考实现：账号级配置保存在 `ZenMuxAccountConfig`，Provider 对每个账号独立请求并汇总为平台层 `items`，弹窗再展示账号明细。

### 4. 接入监控模块

在 `Providers/PlatformProvider.swift` 的 `MonitorModuleConfig` 中添加该平台的配置 case，并补齐 `platform`、`isValid`、`Codable` 编解码逻辑：

```swift
case yourPlatform(YourPlatformConfig)
```

然后在 `UsageTracker.provider(for:)` 中把模块配置转换为 Provider：

```swift
case .yourPlatform(let config):
    return YourPlatformProvider(config: config)
```

`MonitorModule` 会保存别名、展示开关、显示项、重置时间项和排序。新增平台通常不需要再新增独立的 UserDefaults 展示配置。

### 5. 添加设置 UI

在 `SettingsWindow.swift` 中：

- 在 `ModuleEditorView` 中添加对应供应商的凭据字段
- 在供应商 picker、`providerForm`、`quotaOptionsSection`、`canSave` 和 `makeModule()` 中接入新平台
- 如果需要帮助内容，在 `HelpWindowView` 中添加平台说明
- 保持所有配置为模块级配置，不再添加全局平台级开关

## Codex Provider 注意事项

Codex 与其他平台不同：

- 不在 CodeBar 中保存 access token
- 自动读取 `~/.codex/auth.json`
- 仅支持 `auth_mode == "chatgpt"`
- 代理配置可选，保存到 `~/.code_bar/`
- 请求 `chatgpt.com/backend-api/wham/usage`

新增 Codex 字段时，应优先保持与接口原始字段名对应的 `CodingKeys`，再映射成 UI 需要的 `UsageItem` 或 `extraInfo`。

## 配置与缓存

| 数据 | 存储位置 |
| --- | --- |
| 监控模块、模块凭据、指标选择策略、排序 | `~/.code_bar/MonitorModules.json` |
| 平台代理等配置 | `~/.code_bar/PlatformConfigs.json` |
| Codex OAuth | `~/.codex/auth.json` |
| 用量缓存 | UserDefaults |

## UI 约定

- 详情页模块卡片由 `MenuBarView.moduleUsageCard` 渲染
- Provider 不直接操作 UI
- `UsageItem.key` 必须稳定，避免用户展示配置失效
- `extraInfo` 用于展示套餐、账号状态、余额、到期时间等非进度条信息
- 模块级 `metricSelectionMode` 决定菜单栏使用自动发现还是自定义指标
- 自定义模式下，模块级 `displayKeys` 决定菜单栏轮换哪些用量项；缺失项保留配置并由可用项临时补位
- 详情页始终展示 Provider 当前实际返回的全部用量项
- 模块级 `resetTimeKeys` 决定菜单栏指标是否附带重置倒计时
- `showInMenuBar` 为 true 的模块会创建独立 `NSStatusItem`
- 按钮、开关、拖动排序和帮助内容放在 `SettingsWindow`

## 发布

发布不需要手动上传本地 DMG。流程：

1. 更新 `CodeBar/Info.plist`：

```xml
<key>CFBundleShortVersionString</key>
<string>2.2.0</string>
```

2. 提交版本变更：

```bash
git add CodeBar/Info.plist CodeBar.xcodeproj/project.pbxproj README.md
git commit -m "Bump version to 2.2.0"
git push origin main
```

3. 创建并推送 tag：

```bash
git tag -a v2.2.0 -m "CodeBar v2.2.0"
git push origin v2.2.0
```

4. GitHub Actions 自动构建、签名、创建 DMG 并上传 Release。

## 验证清单

发布前至少运行：

```bash
xcodebuild -project CodeBar.xcodeproj -scheme CodeBar -configuration Debug build
```

涉及发布时额外运行 Release 构建。涉及 UI 变更时，启动 Debug app 并人工检查菜单栏弹窗和设置窗口。

## 平台 Logo

平台 Logo 资产放在 `CodeBar/Assets.xcassets`，由 `PlatformType.logoAssetName` 关联到 UI。新增品牌 Logo 时需要：

1. 新增 `*.imageset`，包含 `Contents.json` 和图片/SVG 文件
2. 在 `PlatformType.logoAssetName` 中返回 asset 名称
3. 如果 Logo 必须保留原色，在 `usesOriginalLogoColor` 中返回 `true`
4. 在 `README.md` 的“商标与 Logo”章节补充来源和声明
