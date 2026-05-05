# CodeBar UML 图集

> 所有图表使用 Mermaid 语法，可在 GitHub、VS Code (Mermaid 插件) 或 mermaid.live 中渲染。

---

## 1. 系统上下文图 (C4 Level 1)

```mermaid
C4Context
    title CodeBar 系统上下文图

    Person(user, "用户", "AI 开发者/研究员")

    System(codebar, "CodeBar", "跨平台 AI 用量监控桌面应用")

    System_Ext(zenmux, "ZenMux API", "AI 代理平台")
    System_Ext(bailian, "阿里云百炼 API", "阿里云 AI 平台")
    System_Ext(claude, "Claude API", "Anthropic AI")
    System_Ext(copilot, "GitHub Copilot API", "GitHub AI")
    System_Ext(gemini, "Gemini API", "Google AI")
    System_Ext(others, "... 14+ AI APIs", "其他 AI 平台")

    System_Ext(keychain, "OS 安全存储", "Keychain/libsecret/DPAPI")

    Rel(user, codebar, "查看用量、配置凭据")
    Rel(codebar, zenmux, "HTTPS", "获取用量数据")
    Rel(codebar, bailian, "HTTPS", "获取用量数据")
    Rel(codebar, claude, "HTTPS", "获取用量数据")
    Rel(codebar, copilot, "HTTPS", "获取用量数据")
    Rel(codebar, gemini, "HTTPS", "获取用量数据")
    Rel(codebar, others, "HTTPS", "获取用量数据")
    Rel(codebar, keychain, "读写凭据")
```

## 2. 容器图 (C4 Level 2)

```mermaid
C4Container
    title CodeBar 容器图

    Person(user, "用户")

    System_Boundary(codebar, "CodeBar") {
        Container(frontend, "React 前端", "React 19, Tailwind v4, TypeScript", "用量面板 + 设置界面")
        Container(backend, "Go 后端", "Go 1.25, Wails v2", "Provider 管理, 定时刷新, 事件推送")
        Container(tray, "系统托盘", "energye/systray", "常驻菜单栏, 用量标签轮换")
        ContainerDb(cache, "磁盘缓存", "JSON 文件", "usage.json")
    }

    System_Ext(apis, "AI Platform APIs", "19 个外部 AI 平台")
    System_Ext(keychain, "OS 安全存储", "Keychain/libsecret/DPAPI")

    Rel(user, frontend, "查看/交互", "Wails WebView")
    Rel(user, tray, "查看状态/菜单操作")
    Rel(frontend, backend, "IPC 调用", "Wails bindings")
    Rel(backend, frontend, "推送事件", "EventsEmit")
    Rel(backend, apis, "HTTPS", "获取用量")
    Rel(backend, keychain, "读写凭据")
    Rel(backend, cache, "读写缓存")
    Rel(tray, backend, "触发刷新/导航")
```

## 3. 完整类图

```mermaid
classDiagram
    direction TB

    %% === config 包 ===
    namespace config {
        class Store {
            <<interface>>
            +Get(key string) (string, error)
            +Set(key string, value string) error
            +Delete(key string) error
            +Exists(key string) (bool, error)
            +Keys() ([]string, error)
        }

        class keychainStore {
            +Get(key) (string, error)
            +Set(key, value) error
            +Delete(key) error
            +Exists(key) (bool, error)
            +Keys() ([]string, error)
        }

        class libsecretStore {
            -conn *dbus.Conn
        }

        class dpapiStore {
        }

        class fileStore {
            -path string
            -read() (map~string string~, error)
            -write(m map~string string~) error
            -encrypt(plain []byte) ([]byte, error)
            -decrypt(data []byte) ([]byte, error)
            -deriveKey() []byte
        }
    }

    Store <|.. keychainStore
    Store <|.. libsecretStore
    Store <|.. dpapiStore
    Store <|.. fileStore
    libsecretStore ..> fileStore : 回退
    dpapiStore ..> fileStore : 回退

    %% === provider 包 ===
    namespace provider {
        class PlatformProvider {
            <<interface>>
            +Name() string
            +Icon() string
            +IsConfigured() bool
            +FetchUsage() (*Usage, error)
            +ValidateConfig() error
        }

        class Usage {
            +PlatformName string
            +PlanType string
            +Items []UsageItem
            +ExtraInfo []ExtraInfoKV
        }

        class UsageItem {
            +Key string
            +Label string
            +Used float64
            +Total float64
            +Unit string
            +ResetDate time.Time
        }

        class ExtraInfoKV {
            +Label string
            +Value string
        }

        class ZenMuxProvider {
            -store Store
            +SetStore(s Store)
        }

        class BailianProvider {
            -store Store
            +SetStore(s Store)
        }

        class ClaudeProvider {
            -store Store
            +SetStore(s Store)
        }

        class CopilotProvider {
            -store Store
            +SetStore(s Store)
        }

        class GeminiProvider {
            -store Store
            +SetStore(s Store)
        }

        class AmpProvider {
            -store Store
            +SetStore(s Store)
        }

        class AntigravityProvider {
            -store Store
        }

        class CodexProvider {
            -store Store
        }

        class CursorProvider {
            -store Store
        }

        class FactoryProvider {
            -store Store
        }

        class JetBrainsProvider {
            -store Store
        }

        class KimiProvider {
            -store Store
        }

        class KiroProvider {
            -store Store
        }

        class MinimaxProvider {
            -store Store
        }

        class OpenCodeProvider {
            -store Store
        }

        class PerplexityProvider {
            -store Store
        }

        class SyntheticProvider {
            -store Store
        }

        class WindsurfProvider {
            -store Store
        }

        class ZaiProvider {
            -store Store
        }
    }

    PlatformProvider <|.. ZenMuxProvider
    PlatformProvider <|.. BailianProvider
    PlatformProvider <|.. ClaudeProvider
    PlatformProvider <|.. CopilotProvider
    PlatformProvider <|.. GeminiProvider
    PlatformProvider <|.. AmpProvider
    PlatformProvider <|.. AntigravityProvider
    PlatformProvider <|.. CodexProvider
    PlatformProvider <|.. CursorProvider
    PlatformProvider <|.. FactoryProvider
    PlatformProvider <|.. JetBrainsProvider
    PlatformProvider <|.. KimiProvider
    PlatformProvider <|.. KiroProvider
    PlatformProvider <|.. MinimaxProvider
    PlatformProvider <|.. OpenCodeProvider
    PlatformProvider <|.. PerplexityProvider
    PlatformProvider <|.. SyntheticProvider
    PlatformProvider <|.. WindsurfProvider
    PlatformProvider <|.. ZaiProvider

    PlatformProvider ..> Usage : returns
    Usage *-- UsageItem
    Usage *-- ExtraInfoKV
    ZenMuxProvider --> Store : uses
    BailianProvider --> Store : uses

    %% === tracker 包 ===
    namespace tracker {
        class Tracker {
            -providers []PlatformProvider
            -cachePath string
            -ctx context.Context
            -mu sync.RWMutex
            -cache map~string UsageSnapshot~
            -stopCh chan struct{}
            +New(providers, cachePath) *Tracker
            +Start(ctx context.Context)
            +Stop()
            +Snapshot() map~string UsageSnapshot~
            +Refresh()
            -loop()
            -emitAll()
            -fetchOne(p) UsageSnapshot
            -emit(name, snap)
            -loadCache()
            -persistCache()
        }

        class UsageSnapshot {
            +PlatformName string
            +PlanType string
            +Items []UsageItem
            +ExtraInfo []ExtraInfoKV
            +Error string
        }
    }

    Tracker o-- PlatformProvider : aggregates
    Tracker ..> UsageSnapshot : produces

    %% === tray 包 ===
    namespace tray {
        class Tray {
            -ctx context.Context
            -tracker *Tracker
            -mu sync.RWMutex
            -label string
            +New(tr *Tracker) *Tray
            +Start(ctx context.Context)
            +Stop()
            +UpdateLabel(text string)
            -onReady()
            -onExit()
        }
    }

    Tray --> Tracker : references

    %% === main 包 ===
    namespace main {
        class App {
            -ctx context.Context
            -tracker *Tracker
            -store Store
            +GetSnapshot() map~string UsageSnapshot~
            +Configure(key, value) error
            +GetCredential(key) (string, error)
            +DeleteCredential(key) error
            +ListKnownProviders() []map~string string~
            +ValidateProvider(name) error
            +RefreshNow()
        }
    }

    App --> Tracker : owns
    App --> Store : uses
```

## 4. 序列图 — 完整启动流程

```mermaid
sequenceDiagram
    autonumber
    participant M as main()
    participant S as config.NewStore()
    participant R as provider Registry
    participant IP as InstantiateProviders
    participant T as Tracker
    participant TR as Tray
    participant A as App
    participant W as Wails
    participant FE as React Frontend
    participant API as AI APIs

    M->>S: NewStore()
    Note over S: 根据平台选择<br/>Keychain/libsecret/DPAPI
    S-->>M: Store 实例

    M->>R: init() 已注册 19 个 Provider
    M->>IP: InstantiateProviders(store)
    loop 每个 Provider
        IP->>IP: SetStore(store) — 注入凭据存储
    end
    IP-->>M: []PlatformProvider

    M->>T: tracker.New(providers, cachePath)
    M->>TR: tray.New(tracker)
    M->>A: &App{tracker, store}
    M->>M: buildMenu(app)

    M->>W: wails.Run(options)
    Note over W: 创建 WebView 窗口<br/>420x600, 深色背景

    W->>A: OnStartup(ctx)
    activate A
    A->>T: Start(ctx)
    T->>T: loadCache()
    Note over T: 从 usage.json 恢复缓存
    T->>W: emitAll() → EventsEmit × N
    T->>T: go loop() — 后台刷新

    A->>TR: Start(ctx)
    TR->>TR: go systray.Run()
    Note over TR: 注册菜单项:<br/>显示面板/刷新/设置/退出

    A->>A: go 标签轮换(5s)
    deactivate A

    Note over FE: WebView 加载完成

    FE->>W: GetSnapshot()
    W->>A: GetSnapshot()
    A->>T: Snapshot()
    T-->>FE: 缓存数据

    FE->>W: ListKnownProviders()
    W->>A: ListKnownProviders()
    A-->>FE: 19 个 Provider 信息

    FE->>FE: EventsOn("usage-update")
    FE->>FE: EventsOn("navigate")

    Note over T: 60s 后...
    T->>API: FetchUsage() × N
    API-->>T: JSON 响应
    T->>W: EventsEmit("usage-update", snap)
    W->>FE: 实时更新 UI
```

## 5. 序列图 — 手动刷新

```mermaid
sequenceDiagram
    participant U as 用户
    participant FE as React (App)
    participant W as Wails Binding
    participant A as App
    participant T as Tracker
    participant P as Providers
    participant API as AI APIs

    U->>FE: 点击「刷新」按钮
    FE->>FE: setIsRefreshing(true)
    FE->>W: api.RefreshNow()
    W->>A: RefreshNow()
    A->>T: go Refresh()
    Note over A: 异步执行，立即返回

    loop 每个已配置的 Provider
        T->>P: FetchUsage()
        P->>API: HTTP 请求
        API-->>P: JSON 响应
        P-->>T: *Usage
        T->>T: 更新 cache
        T->>W: EventsEmit("usage-update", snap)
        W->>FE: 更新 snapshots state
        FE->>FE: setIsRefreshing(false)
        FE->>FE: 渲染 UsageCard
    end

    T->>T: persistCache()
```

## 6. 序列图 — 凭据保存与验证

```mermaid
sequenceDiagram
    participant U as 用户
    participant FE as SettingsPanel
    participant W as Wails
    participant A as App
    participant S as Store
    participant KC as Keychain
    participant P as Provider
    participant API as AI API

    rect rgb(40, 40, 60)
    Note over U,KC: 保存凭据
    U->>FE: 输入 API Key
    U->>FE: 点击「保存」
    FE->>FE: setSaving(true)

    loop 每个非空字段
        FE->>W: Configure(key, value)
        W->>A: Configure(key, value)
        A->>S: Set(key, value)
        S->>KC: Delete(key) — 删除旧值
        S->>KC: AddItem(key, value)
        KC-->>S: OK
        S-->>A: nil
    end

    A-->>FE: Promise resolved
    FE->>FE: setSaving(false)
    FE->>FE: 显示「已保存」
    end

    rect rgb(40, 60, 40)
    Note over U,API: 验证凭据
    U->>FE: 点击「验证凭据」
    FE->>FE: setValidating(name)

    FE->>W: ValidateProvider(name)
    W->>A: ValidateProvider(name)
    A->>A: 查找匹配的 Provider
    A->>P: ValidateConfig()
    P->>P: IsConfigured() → true
    P->>P: FetchUsage()
    P->>S: Get(credential_key)
    S->>KC: QueryItem(key)
    KC-->>S: credential_value
    P->>API: HTTP 请求 (with credential)

    alt 成功
        API-->>P: 200 OK + data
        P-->>A: nil
        A-->>FE: Promise resolved
        FE->>FE: 显示「验证通过」(绿色)
    else 失败
        API-->>P: 401/403
        P-->>A: error("credentials invalid")
        A-->>FE: Promise rejected
        FE->>FE: 显示错误消息 (红色)
    end

    FE->>FE: setValidating(null)
    end
```

## 7. 序列图 — 系统托盘交互

```mermaid
sequenceDiagram
    participant U as 用户
    participant TRAY as 系统托盘
    participant TR as Tray
    participant T as Tracker
    participant W as Wails Runtime
    participant FE as React

    Note over TRAY: 标签显示: "ZM 83%"

    U->>TRAY: 点击「显示面板」
    TRAY->>TR: mShow.Click callback
    TR->>W: WindowShow(ctx)
    TR->>W: WindowSetAlwaysOnTop(true)
    TR->>W: WindowSetAlwaysOnTop(false)
    Note over W: 窗口出现并闪烁到最前

    U->>TRAY: 点击「刷新」
    TRAY->>TR: mRefresh.Click callback
    TR->>T: go Refresh()

    U->>TRAY: 点击「设置」
    TRAY->>TR: mSettings.Click callback
    TR->>W: WindowShow(ctx)
    TR->>W: EventsEmit("navigate", "settings")
    W->>FE: setView("settings")

    U->>TRAY: 点击「退出」
    TRAY->>TR: mQuit.Click callback
    TR->>TR: systray.Quit()
    TR->>W: runtime.Quit(ctx)
```

## 8. 序列图 — 重复实例检测

```mermaid
sequenceDiagram
    participant U as 用户
    participant I2 as CodeBar (第二实例)
    participant W as Wails SingleInstanceLock
    participant I1 as CodeBar (第一实例)
    participant A as App
    participant FE as React Frontend

    Note over I1: 已运行中 (UniqueId: codebar-single-instance)

    U->>I2: 双击启动 CodeBar
    I2->>W: 尝试获取 SingleInstanceLock
    W->>W: 检测到锁已被持有

    W->>I1: OnSecondInstanceLaunch(data)
    I1->>A: callback 执行
    A->>W: runtime.WindowShow(ctx)
    A->>W: WindowSetAlwaysOnTop(ctx, true)
    A->>W: WindowSetAlwaysOnTop(ctx, false)
    A->>W: EventsEmit(ctx, "second-instance", "CodeBar 已在运行中")
    W->>FE: 事件触发

    FE->>FE: 显示 Toast: "CodeBar 已在运行中"
    Note over FE: Toast 4秒后自动消失

    Note over I2: 自动退出
```

## 9. 状态图 — 应用完整生命周期

```mermaid
stateDiagram-v2
    [*] --> Init: 用户启动应用

    state Init {
        [*] --> CreateStore: NewStore()
        CreateStore --> CreateProviders: InstantiateProviders()
        CreateProviders --> CreateTracker: tracker.New()
        CreateTracker --> CreateTray: tray.New()
        CreateTray --> CreateApp: &App{}
        CreateApp --> BuildMenu: buildMenu()
        BuildMenu --> WailsRun: wails.Run()
    }

    Init --> Startup: OnStartup(ctx)

    state Startup {
        [*] --> LoadCache: loadCache()
        LoadCache --> EmitCached: emitAll() 推送缓存
        EmitCached --> StartLoop: go loop()
        StartLoop --> StartTray: sysTray.Start()
        StartTray --> StartRotation: go 标签轮换
    }

    Startup --> Active

    state Active {
        [*] --> WindowVisible

        state WindowVisible {
            [*] --> PanelView
            PanelView --> SettingsView: 点击「设置」
            SettingsView --> PanelView: 点击「用量」
        }

        WindowVisible --> WindowHidden: 关闭窗口
        WindowHidden --> WindowVisible: 托盘「显示面板」
        WindowHidden --> WindowVisible: 重复实例检测

        state BackgroundTasks {
            [*] --> WaitingRefresh
            WaitingRefresh --> Refreshing: 60s 定时器
            WaitingRefresh --> Refreshing: 手动刷新
            Refreshing --> WaitingRefresh: 完成

            --

            [*] --> RotatingLabel
            RotatingLabel --> RotatingLabel: 5s 切换下一个 Provider
        }
    }

    Active --> Shutdown: Cmd+Q / 托盘退出
    
    state Shutdown {
        [*] --> StopTracker: tracker.Stop()
        StopTracker --> StopTray: tray.Stop()
        StopTray --> [*]
    }

    Shutdown --> [*]
```

## 10. 状态图 — Provider 请求状态

```mermaid
stateDiagram-v2
    [*] --> CheckStore: FetchUsage() 调用

    CheckStore --> StoreError: store == nil
    CheckStore --> GetCredential: store 可用

    GetCredential --> CredError: 凭据为空
    GetCredential --> BuildRequest: 凭据有效

    BuildRequest --> SendRequest: HTTP 请求
    SendRequest --> ParseResponse: HTTP 200
    SendRequest --> AuthError: HTTP 401/403
    SendRequest --> RateLimited: HTTP 429
    SendRequest --> OtherError: HTTP 其他
    SendRequest --> NetworkError: 网络超时/错误

    ParseResponse --> BuildUsage: JSON 解析成功
    ParseResponse --> ParseError: JSON 解析失败

    BuildUsage --> Success: 返回 *Usage

    StoreError --> [*]: error
    CredError --> [*]: error
    AuthError --> [*]: error
    RateLimited --> [*]: error
    OtherError --> [*]: error
    NetworkError --> [*]: error
    ParseError --> [*]: error
    Success --> [*]: *Usage
```

## 11. 活动图 — Tracker emitAll 流程

```mermaid
flowchart TD
    START([emitAll 开始]) --> LOOP{还有 Provider?}
    LOOP -->|是| CHECK[p.IsConfigured()?]
    CHECK -->|未配置| SKIP[UsageSnapshot{Error: not configured}]
    CHECK -->|已配置| FETCH[p.FetchUsage()]
    FETCH --> RESULT{成功?}
    RESULT -->|是| SNAP[构建 UsageSnapshot]
    RESULT -->|否| ERR_SNAP[UsageSnapshot{Error: err.Error()}]
    SNAP --> LOCK[mu.Lock() 写入 cache]
    ERR_SNAP --> EMIT_ERR[emit error snapshot]
    SKIP --> EMIT_SKIP[emit not-configured snapshot]
    LOCK --> UNLOCK[mu.Unlock()]
    UNLOCK --> EMIT[EventsEmit 'usage-update']
    EMIT --> LOOP
    EMIT_ERR --> LOOP
    EMIT_SKIP --> LOOP
    LOOP -->|否| PERSIST[persistCache()]
    PERSIST --> RLOCK[mu.RLock()]
    RLOCK --> MARSHAL[json.Marshal(cache)]
    MARSHAL --> WRITEFILE[os.WriteFile(cachePath)]
    WRITEFILE --> RUNLOCK[mu.RUnlock()]
    RUNLOCK --> END([emitAll 完成])
```

## 12. 组件图 — 前端组件树

```mermaid
graph TB
    subgraph ReactApp["React 应用"]
        MAIN["main.tsx<br/>createRoot().render()"]
        APP["App<br/>(根组件, 状态管理)"]
        
        subgraph Views["视图层"]
            PANEL["用量面板视图"]
            SETTINGS["SettingsPanel"]
        end
        
        subgraph PanelComponents["面板组件"]
            EMPTY_STATE["空状态引导"]
            CARD_LIST["UsageCard 列表"]
            USAGE_CARD["UsageCard<br/>单个平台卡片"]
            PROGRESS["ProgressBar<br/>进度条组件"]
            ICON["ProviderIcon<br/>平台图标"]
        end
        
        subgraph SettingsComponents["设置组件"]
            PROVIDER_ROW["Provider 展开行"]
            CRED_INPUT["凭据输入框"]
            SAVE_BTN["保存按钮"]
            VALIDATE_BTN["验证按钮"]
        end
        
        subgraph Shared["共享组件"]
            TOAST["Toast<br/>通知弹窗"]
            SPINNER["Spinner<br/>加载旋转"]
        end
        
        subgraph Utilities["工具函数"]
            FMT_NUM["formatNumber()"]
            FMT_TIME["formatRelativeTime()"]
            PROVIDER_CFG["PROVIDER_CONFIG"]
            CRED_FIELDS["CREDENTIAL_FIELDS"]
        end
    end
    
    subgraph WailsBindings["Wails 绑定"]
        API["wailsjs/go/main/App"]
        EVENTS["wailsjs/runtime/runtime"]
        MODELS["wailsjs/go/models"]
    end
    
    MAIN --> APP
    APP --> PANEL
    APP --> SETTINGS
    APP --> TOAST
    
    PANEL --> EMPTY_STATE
    PANEL --> CARD_LIST
    CARD_LIST --> USAGE_CARD
    USAGE_CARD --> PROGRESS
    USAGE_CARD --> ICON
    
    SETTINGS --> PROVIDER_ROW
    PROVIDER_ROW --> CRED_INPUT
    PROVIDER_ROW --> SAVE_BTN
    PROVIDER_ROW --> VALIDATE_BTN
    PROVIDER_ROW --> ICON
    
    APP --> SPINNER
    PROGRESS --> FMT_NUM
    PROGRESS --> FMT_TIME
    ICON --> PROVIDER_CFG
    SETTINGS --> CRED_FIELDS
    
    APP -->|"API 调用"| API
    APP -->|"事件监听"| EVENTS
    API -->|"类型引用"| MODELS
```

## 13. ER 图 — 数据模型关系

```mermaid
erDiagram
    PROVIDER ||--o{ USAGE : "FetchUsage() 返回"
    USAGE ||--|{ USAGE_ITEM : "包含"
    USAGE ||--o{ EXTRA_INFO : "可选包含"
    
    TRACKER ||--|{ USAGE_SNAPSHOT : "缓存"
    USAGE_SNAPSHOT ||--|{ USAGE_ITEM : "包含"
    USAGE_SNAPSHOT ||--o{ EXTRA_INFO : "可选包含"
    
    STORE ||--|{ CREDENTIAL : "存储"
    PROVIDER }|--|| STORE : "读取凭据"

    PROVIDER {
        string Name "平台名称"
        string Icon "图标键"
        bool IsConfigured "凭据是否已配置"
    }

    USAGE {
        string PlatformName "平台名称"
        string PlanType "套餐类型"
    }

    USAGE_ITEM {
        string Key "唯一标识 (5hour/7day/...)"
        string Label "显示名称"
        float64 Used "已使用量"
        float64 Total "总配额"
        string Unit "单位 (flows/tokens/...)"
        time ResetDate "重置时间"
    }

    EXTRA_INFO {
        string Label "标签"
        string Value "值"
    }

    USAGE_SNAPSHOT {
        string PlatformName "平台名称"
        string PlanType "套餐类型"
        string Error "错误信息 (可选)"
    }

    CREDENTIAL {
        string Key "凭据键 (provider.field)"
        string Value "凭据值 (加密存储)"
    }

    STORE {
        string Type "keychain/libsecret/dpapi/file"
    }
```

## 14. 网络拓扑图 — API 通信

```mermaid
graph LR
    subgraph Local["本地"]
        CB["CodeBar App"]
    end

    subgraph Internet["Internet (HTTPS)"]
        direction TB
        
        subgraph Verified["已验证 API ✅"]
            ZM["zenmux.ai<br/>/api/v1/management/subscription/detail"]
            BL["bailian-cs.console.aliyun.com<br/>/data/api.json"]
        end
        
        subgraph Standard["标准 API"]
            CL["api.anthropic.com<br/>/v1/usage"]
            CP["api.github.com<br/>/copilot_internal/usage"]
            GM["generativelanguage.googleapis.com<br/>/v1beta/usage"]
        end
        
        subgraph Others["其他 AI API"]
            AMP["api.amp.com"]
            AG["api.antigravity.ai"]
            CDX["api.codex.com"]
            CUR["api.cursor.com"]
            FAC["api.factory.ai"]
            JB["api.jetbrains.com"]
            KIMI["api.kimi.ai"]
            KIRO["api.kiro.dev"]
            MM["api.minimax.chat"]
            OC["api.opencode.ai"]
            PP["api.perplexity.ai"]
            SY["api.synthetic.com"]
            WS["api.windsurf.com"]
            ZAI["api.z.ai"]
        end
    end

    CB -->|"GET + Bearer Token"| ZM
    CB -->|"POST + Cookie + sec_token"| BL
    CB -->|"GET + Bearer Token"| CL
    CB -->|"GET + Bearer Token"| CP
    CB -->|"GET + API Key in URL"| GM
    CB -->|"GET + Bearer Token"| AMP
    CB -->|"GET + Bearer Token"| AG
    CB -->|"GET + Bearer Token"| CDX
    CB -->|"GET + Bearer Token"| CUR
    CB -->|"GET + Bearer Token"| FAC
    CB -->|"GET + Bearer Token"| JB
    CB -->|"GET + Bearer Token"| KIMI
    CB -->|"GET + Bearer Token"| KIRO
    CB -->|"GET + Bearer Token"| MM
    CB -->|"GET + Bearer Token"| OC
    CB -->|"GET + Bearer Token"| PP
    CB -->|"GET + Bearer Token"| SY
    CB -->|"GET + Bearer Token"| WS
    CB -->|"GET + Bearer Token"| ZAI
```

## 15. 用户旅程图

```mermaid
journey
    title 用户首次使用 CodeBar
    section 安装启动
      下载 CodeBar.app: 5: 用户
      首次启动应用: 4: 用户
      看到空状态提示: 3: 用户
    section 配置凭据
      点击「前往设置」: 4: 用户
      展开 ZenMux: 4: 用户
      粘贴 API Key: 3: 用户
      点击「保存」: 4: 用户
      点击「验证凭据」: 4: 用户
      看到「验证通过」: 5: 用户
    section 查看用量
      切换到「用量」面板: 5: 用户
      点击「刷新」: 4: 用户
      看到用量卡片: 5: 用户
      查看进度条和重置时间: 5: 用户
    section 日常使用
      最小化到托盘: 5: 用户
      查看托盘标签 "ZM 83%": 5: 用户
      托盘点击「显示面板」: 5: 用户
```

## 16. 甘特图 — 启动时间线

```mermaid
gantt
    title CodeBar 启动时间线
    dateFormat X
    axisFormat %Lms

    section 初始化
    NewStore()                  :done, 0, 5
    InstantiateProviders()      :done, 5, 15
    tracker.New()               :done, 15, 18
    tray.New()                  :done, 18, 20
    buildMenu()                 :done, 20, 22

    section Wails 启动
    wails.Run() — WebView 初始化  :active, 22, 100

    section OnStartup
    loadCache()                  :done, 100, 110
    emitAll() — 推送缓存          :done, 110, 120
    go loop() — 后台刷新          :milestone, 120, 120
    sysTray.Start()              :done, 120, 140
    go 标签轮换                   :milestone, 140, 140

    section 前端加载
    React 渲染                   :active, 100, 200
    GetSnapshot()                :done, 200, 210
    ListKnownProviders()         :done, 210, 215
    EventsOn 注册                :done, 215, 220
    UI 就绪                      :milestone, 220, 220

    section 首次刷新
    等待 60s                     :crit, 220, 6220
    emitAll() — 真实 API 调用     :active, 6220, 8220
```
