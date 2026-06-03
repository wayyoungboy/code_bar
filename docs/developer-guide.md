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

### 4. 注册 Provider

在 `UsageTracker.loadConfig()` 中读取配置并注册：

```swift
if let data = allConfigs[PlatformType.yourPlatform.rawValue],
   let config = try? JSONDecoder().decode(YourPlatformConfig.self, from: data) {
    providers[.yourPlatform] = YourPlatformProvider(config: config)
}
```

再添加保存和读取配置的方法，参考 `saveMimoConfig` 或 `saveCodexProxyURL`。

### 5. 添加设置 UI

在 `SettingsWindow.swift` 中：

- 添加 `@State` 字段
- 在 `body` 中加入 `manualConfigSection`
- 添加配置表单
- 添加帮助 sheet 内容
- 在 `onAppear` 加载已保存配置

## Codex Provider 注意事项

Codex 与其他平台不同：

- 不在 CodeBar 中保存 access token
- 自动读取 Keychain `Codex Auth` 或 `~/.codex/auth.json`
- 仅支持 `auth_mode == "chatgpt"`
- 代理配置可选，保存到 CodeBar Keychain
- 请求 `chatgpt.com/backend-api/wham/usage`

新增 Codex 字段时，应优先保持与接口原始字段名对应的 `CodingKeys`，再映射成 UI 需要的 `UsageItem` 或 `extraInfo`。

## 配置与缓存

| 数据 | 存储位置 |
| --- | --- |
| 平台凭据 | Keychain `PlatformConfigs` |
| Codex 代理配置 | Keychain `PlatformConfigs` |
| Codex OAuth | Codex CLI Keychain / `~/.codex/auth.json` |
| 平台启用状态 | UserDefaults |
| 展示项配置 | UserDefaults |
| 重置时间展示配置 | UserDefaults |
| 用量缓存 | UserDefaults |

## UI 约定

- 平台卡片由 `MenuBarView.platformUsageCard` 渲染
- Provider 不直接操作 UI
- `UsageItem.key` 必须稳定，避免用户展示配置失效
- `extraInfo` 用于展示套餐、账号状态、余额、到期时间等非进度条信息
- 按钮、开关和帮助内容放在 `SettingsWindow`

## 发布

发布不需要手动上传本地 DMG。流程：

1. 更新 `CodeBar/Info.plist`：

```xml
<key>CFBundleShortVersionString</key>
<string>2.1.0</string>
```

2. 提交版本变更：

```bash
git add CodeBar/Info.plist
git commit -m "Bump version to 2.1.0"
git push origin main
```

3. 创建并推送 tag：

```bash
git tag -a v2.1.0 -m "CodeBar v2.1.0"
git push origin v2.1.0
```

4. GitHub Actions 自动构建、签名、创建 DMG 并上传 Release。

## 验证清单

发布前至少运行：

```bash
xcodebuild -project CodeBar.xcodeproj -scheme CodeBar -configuration Debug build
```

涉及发布时额外运行 Release 构建。涉及 UI 变更时，启动 Debug app 并人工检查菜单栏弹窗和设置窗口。
