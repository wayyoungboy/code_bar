# CodeBar UML 图集

以下图表使用 Mermaid 语法，可在 GitHub 或 VS Code Mermaid 插件中渲染。

## 系统上下文

```mermaid
flowchart TB
    User["用户"]
    CodeBar["CodeBar macOS 菜单栏应用"]
    Keychain["macOS Keychain"]
    Defaults["UserDefaults"]
    Bailian["阿里云百炼 API"]
    ZenMux["ZenMux API"]
    Mimo["小米 MiMo API"]
    CodexAuth["Codex CLI Auth\nKeychain / ~/.codex/auth.json"]
    ChatGPT["chatgpt.com/backend-api/wham/usage"]
    GitHub["GitHub Releases"]

    User -->|查看用量 / 设置| CodeBar
    CodeBar -->|读写 CodeBar 配置| Keychain
    CodeBar -->|读写 UI 状态和缓存| Defaults
    CodeBar -->|HTTPS| Bailian
    CodeBar -->|HTTPS| ZenMux
    CodeBar -->|HTTPS| Mimo
    CodeBar -->|读取 OAuth| CodexAuth
    CodeBar -->|HTTPS, 可选代理| ChatGPT
    CodeBar -->|检查更新| GitHub
```

## 组件图

```mermaid
flowchart LR
    App["CodeBarApp"]
    Tracker["UsageTracker"]
    Menu["MenuBarView"]
    Settings["SettingsWindow"]
    KeychainHelper["KeychainHelper"]
    UpdateChecker["UpdateChecker"]

    subgraph Providers
        PlatformProvider["PlatformProvider"]
        BailianProvider["BailianProvider"]
        ZenMuxProvider["ZenMuxProvider"]
        MimoProvider["MimoProvider"]
        CodexProvider["CodexProvider"]
    end

    App --> Tracker
    App --> Menu
    App --> Settings
    App --> UpdateChecker
    Menu --> Tracker
    Settings --> Tracker
    Tracker --> PlatformProvider
    Tracker --> KeychainHelper
    PlatformProvider <|-- BailianProvider
    PlatformProvider <|-- ZenMuxProvider
    PlatformProvider <|-- MimoProvider
    PlatformProvider <|-- CodexProvider
```

## Provider 类图

```mermaid
classDiagram
    class PlatformProvider {
        <<protocol>>
        +platformName String
        +isConfigured Bool
        +fetchUsage() async throws PlatformUsageData
        +validateConfig() async throws Bool
    }

    class PlatformUsageData {
        +platformName String
        +planType String
        +items [UsageItem]
        +extraInfo [(label, value)]
    }

    class UsageItem {
        +key String
        +label String
        +used Int
        +total Int
        +unit String
        +resetDate Date
        +percent Double
    }

    class UsageTracker {
        +platforms [PlatformType: PlatformUsageData]
        +errorMessages [PlatformType: String]
        +enabledPlatforms [PlatformType: Bool]
        +providers [PlatformType: PlatformProvider]
        +refresh() async
        +saveCodexProxyURL(String?)
    }

    class BailianProvider
    class ZenMuxProvider
    class MimoProvider
    class CodexProvider

    PlatformProvider <|.. BailianProvider
    PlatformProvider <|.. ZenMuxProvider
    PlatformProvider <|.. MimoProvider
    PlatformProvider <|.. CodexProvider
    UsageTracker --> PlatformProvider
    PlatformProvider --> PlatformUsageData
    PlatformUsageData *-- UsageItem
```

## 刷新时序

```mermaid
sequenceDiagram
    participant Timer
    participant Tracker as UsageTracker
    participant Provider as PlatformProvider
    participant API as Platform API
    participant UI as SwiftUI Views
    participant Cache as UserDefaults

    Timer->>Tracker: refresh()
    Tracker->>Tracker: filter enabled providers
    loop each enabled provider
        Tracker->>Provider: fetchUsage()
        Provider->>API: HTTPS request
        API-->>Provider: JSON response
        Provider-->>Tracker: PlatformUsageData
        Tracker->>Tracker: update platforms
    end
    Tracker->>Cache: saveToStorage()
    Tracker-->>UI: @Published state change
```

## Codex 查询时序

```mermaid
sequenceDiagram
    participant Tracker as UsageTracker
    participant Codex as CodexProvider
    participant Keychain as Keychain Codex Auth
    participant File as ~/.codex/auth.json
    participant Proxy as Optional Proxy
    participant API as chatgpt.com wham usage

    Tracker->>Codex: fetchUsage()
    Codex->>Keychain: read Codex Auth
    alt Keychain missing or invalid
        Codex->>File: read auth.json
    end
    Codex->>Codex: validate auth_mode == chatgpt
    Codex->>Codex: build URLSession
    alt proxy configured
        Codex->>Proxy: request through proxy
        Proxy->>API: GET /backend-api/wham/usage
    else no proxy
        Codex->>API: GET /backend-api/wham/usage
    end
    API-->>Codex: rate_limit, plan_type, credits
    Codex-->>Tracker: PlatformUsageData
```

## 发布流程

```mermaid
flowchart LR
    Version["Bump Info.plist version"]
    Commit["Commit to main"]
    Tag["Push v* tag"]
    Actions["GitHub Actions"]
    Build["Build Release app"]
    DMG["Create CodeBar.dmg"]
    Release["Publish GitHub Release"]

    Version --> Commit --> Tag --> Actions --> Build --> DMG --> Release
```
