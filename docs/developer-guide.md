# CodeBar 开发者指南

> 本文档面向希望扩展 CodeBar 的开发者：添加新 AI 平台 Provider、修改前端 UI、或理解内部工作机制。

---

## 目录

1. [快速开始](#1-快速开始)
2. [添加新 Provider](#2-添加新-provider)
3. [凭据存储键命名规范](#3-凭据存储键命名规范)
4. [前端组件开发](#4-前端组件开发)
5. [Wails 绑定与事件](#5-wails-绑定与事件)
6. [测试](#6-测试)
7. [构建与发布](#7-构建与发布)
8. [常见问题](#8-常见问题)

---

## 1. 快速开始

### 环境要求

| 工具 | 版本 | 安装 |
|------|------|------|
| Go | ≥ 1.25 | `brew install go` |
| Node.js | ≥ 20 | `brew install node` |
| Wails CLI | v2 | `go install github.com/wailsapp/wails/v2/cmd/wails@latest` |
| Xcode Command Line Tools | 最新 | `xcode-select --install` (macOS) |

### 首次运行

```bash
git clone <repo> && cd code_bar
go mod download
cd frontend && npm install && cd ..
wails dev
```

`wails dev` 会:
1. 启动 Vite 开发服务器 (http://localhost:5173)
2. 编译 Go 后端
3. 启动带热重载的桌面窗口

### 项目结构速览

```
main.go           ← App 结构体 (Wails 绑定), 菜单, 启动逻辑
internal/config/  ← 凭据存储 (跨平台)
internal/provider/ ← AI 平台适配器 (每个一个 .go 文件)
internal/tracker/  ← 定时刷新、缓存、事件推送
internal/tray/     ← 系统托盘
frontend/src/      ← React UI
```

---

## 2. 添加新 Provider

添加新 AI 平台只需 **两个文件**，无需修改其他代码。

### 步骤 1: 创建 Go Provider 文件

在 `internal/provider/` 下创建 `yourprovider.go`:

```go
package provider

import (
    "codebar/internal/config"
    "encoding/json"
    "fmt"
    "net/http"
)

// init() 自注册 — 编译时自动加入全局 registry
func init() { RegisterProvider(&YourProvider{}) }

type YourProvider struct{ store config.Store }

// SetStore 由 InstantiateProviders() 通过类型断言调用
func (y *YourProvider) SetStore(s config.Store) { y.store = s }

// Name 返回显示名称 (出现在 UI 卡片标题)
func (y *YourProvider) Name() string { return "YourPlatform" }

// Icon 返回图标键 (对应前端 PROVIDER_CONFIG 中的 key)
func (y *YourProvider) Icon() string { return "yourplatform" }

// IsConfigured 检查凭据是否已配置
func (y *YourProvider) IsConfigured() bool {
    if y.store == nil {
        return false
    }
    ok, _ := y.store.Exists("yourplatform.api_key")
    return ok
}

// FetchUsage 调用真实 API 获取用量数据
func (y *YourProvider) FetchUsage() (*Usage, error) {
    if y.store == nil {
        return nil, fmt.Errorf("yourplatform: config store not set")
    }
    key, _ := y.store.Get("yourplatform.api_key")
    if key == "" {
        return nil, fmt.Errorf("yourplatform: API key not configured")
    }

    req, _ := http.NewRequest(http.MethodGet, "https://api.yourplatform.com/v1/usage", nil)
    req.Header.Set("Authorization", "Bearer "+key)

    // 使用共享 HTTP 辅助函数 (自动处理 401/403/429)
    body, err := doRequest("yourplatform", req)
    if err != nil {
        return nil, err
    }

    var result struct {
        Plan  string  `json:"plan"`
        Used  float64 `json:"used"`
        Limit float64 `json:"limit"`
    }
    if err := json.Unmarshal(body, &result); err != nil {
        return nil, fmt.Errorf("yourplatform: parse response: %w", err)
    }

    return &Usage{
        PlatformName: "YourPlatform",
        PlanType:     result.Plan,
        Items: []UsageItem{{
            Key:   "quota",
            Label: "配额使用",
            Used:  result.Used,
            Total: result.Limit,
            Unit:  "requests",
        }},
    }, nil
}

// ValidateConfig 验证凭据有效性 (实际调用 FetchUsage)
func (y *YourProvider) ValidateConfig() error {
    if !y.IsConfigured() {
        return fmt.Errorf("yourplatform: not configured")
    }
    _, err := y.FetchUsage()
    return err
}
```

### 步骤 2: 注册前端配置

在 `frontend/src/App.tsx` 中添加两处配置:

**1. PROVIDER_CONFIG** — 图标颜色和缩写:

```typescript
const PROVIDER_CONFIG: Record<string, { color: string; label: string }> = {
  // ... 现有配置
  yourplatform: { color: '#FF6B6B', label: 'YP' },
}
```

**2. CREDENTIAL_FIELDS** — 设置面板字段:

```typescript
const CREDENTIAL_FIELDS: Record<string, { key: string; label: string; secret: boolean }[]> = {
  // ... 现有配置
  'YourPlatform': [{ key: 'yourplatform.api_key', label: 'API Key', secret: true }],
}
```

### 完成

重新运行 `wails dev`，新 Provider 会自动出现在设置面板中。配置凭据后，下次刷新即可看到用量数据。

### 多凭据字段

如果 Provider 需要多个凭据 (如百炼需要 Cookie + sec_token):

```go
func (b *BailianProvider) IsConfigured() bool {
    ok, _ := b.store.Exists("bailian.cookie")
    return ok
}

func (b *BailianProvider) FetchUsage() (*Usage, error) {
    cookie, _ := b.store.Get("bailian.cookie")
    secToken, _ := b.store.Get("bailian.sec_token")
    region, _ := b.store.Get("bailian.region")
    // ...
}
```

对应前端:

```typescript
'阿里云百炼': [
    { key: 'bailian.cookie', label: 'Cookie', secret: true },
    { key: 'bailian.sec_token', label: 'Sec Token', secret: true },
    { key: 'bailian.region', label: '地域 (默认 cn-beijing)', secret: false },
],
```

### 多个 UsageItem

Provider 可返回多个用量条目 (如 ZenMux 返回 5小时和 7天配额):

```go
items := []UsageItem{
    {Key: "5hour", Label: "5小时", Used: 800, Total: 6182, Unit: "flows", ResetDate: resetTime5h},
    {Key: "7day",  Label: "7天",   Used: 2400, Total: 12000, Unit: "flows", ResetDate: resetTime7d},
}
```

### ExtraInfo

额外信息以键值对形式显示在卡片底部:

```go
extra := []ExtraInfoKV{
    {Label: "账户状态", Value: "active"},
    {Label: "套餐", Value: "Ultra $199/month"},
    {Label: "单价", Value: "$0.0322/flow"},
}
```

---

## 3. 凭据存储键命名规范

格式: `{provider}.{field}`

| Provider | 键 | 说明 |
|----------|-----|------|
| ZenMux | `zenmux.api_key` | API Key |
| 百炼 | `bailian.cookie` | Cookie |
| 百炼 | `bailian.sec_token` | Security Token |
| 百炼 | `bailian.region` | 地域 (非密钥) |
| Claude | `claude.oauth_token` | OAuth Token |
| Copilot | `copilot.api_key` | API Key |
| ... | `{name}.api_key` | 标准格式 |

---

## 4. 前端组件开发

### 组件概览

| 组件 | 文件位置 | 职责 |
|------|---------|------|
| `App` | App.tsx:335 | 根组件，管理全局状态和路由 |
| `UsageCard` | App.tsx:172 | 单个平台的用量卡片 |
| `ProgressBar` | App.tsx:142 | 进度条，支持标签和重置时间 |
| `ProviderIcon` | App.tsx:74 | 彩色圆形图标 |
| `SettingsPanel` | App.tsx:212 | 凭据配置面板 |
| `Toast` | App.tsx:127 | 通知弹窗 (4s 自动消失) |
| `Spinner` | App.tsx:318 | SVG 加载旋转动画 |

### 状态管理

使用 React `useState` + `useEffect`，无外部状态库:

```typescript
const [snapshots, setSnapshots] = useState<Record<string, UsageSnapshot>>({})
const [lastRefresh, setLastRefresh] = useState<string>('')
const [view, setView] = useState<'panel' | 'settings'>('panel')
const [providers, setProviders] = useState<ProviderInfo[]>([])
const [isRefreshing, setIsRefreshing] = useState(false)
```

### 事件监听

在 `App` 组件的 `useEffect` 中注册 Wails 事件:

```typescript
useEffect(() => {
    EventsOn('usage-update', (snap: UsageSnapshot) => {
        setSnapshots(prev => ({ ...prev, [snap.platformName]: snap }))
        setLastRefresh(new Date().toLocaleTimeString())
        setIsRefreshing(false)
    })

    EventsOn('navigate', (target: string) => {
        if (target === 'settings') setView('settings')
        else if (target === 'panel') setView('panel')
    })
}, [])
```

### 样式约定

- 使用 Tailwind CSS v4 utility classes
- 深色主题: 背景 `#0f0f14` (`bg-[#0f0f14]`)
- 卡片: `bg-gray-800 rounded-xl border border-gray-700`
- 文字: 白色 (`text-white`) / 灰色 (`text-gray-300`/`text-gray-400`)
- 按钮: `bg-indigo-600 hover:bg-indigo-500` (主要) / `bg-gray-700 hover:bg-gray-600` (次要)

### Wails 拖拽区域

窗口标题栏使用 CSS 自定义属性实现拖拽:

```tsx
<div style={{ '--wails-draggable': 'drag' } as React.CSSProperties}>
    {/* 可拖拽区域 */}
    <div style={{ '--wails-draggable': 'no-drag' } as React.CSSProperties}>
        {/* 按钮等不可拖拽元素 */}
    </div>
</div>
```

---

## 5. Wails 绑定与事件

### 绑定机制

Wails 通过反射将 `App` 结构体的公开方法暴露为 JavaScript 函数:

```go
// main.go
Bind: []interface{}{app}
```

自动生成的 TypeScript 声明: `frontend/src/wailsjs/go/main/App.d.ts`

### 重新生成绑定

修改 `App` 结构体的方法签名后:

```bash
wails generate module
```

这会重新生成 `App.d.ts` 和 `models.ts`。

### 事件方向

| 方向 | Go 端 | Frontend 端 |
|------|-------|------------|
| Go → Frontend | `runtime.EventsEmit(ctx, "event-name", data)` | `EventsOn("event-name", callback)` |
| Frontend → Go | 通过绑定方法调用 | `api.MethodName(args)` |

---

## 6. 测试

### Go 测试

```bash
# 全部测试
go test ./...

# 特定包
go test ./internal/provider/ -v

# ZenMux 集成测试 (需要真实 API Key)
ZENMUX_API_KEY=sk-... go test ./internal/provider/ -run TestZenMux -v
```

### 编写集成测试

参考 `internal/provider/zenmux_test.go`:

```go
func TestZenMuxFetch(t *testing.T) {
    key := os.Getenv("ZENMUX_API_KEY")
    if key == "" {
        t.Skip("ZENMUX_API_KEY not set")
    }

    p := &ZenMuxProvider{}
    p.SetStore(newMemStore(map[string]string{
        "zenmux.api_key": key,
    }))

    usage, err := p.FetchUsage()
    if err != nil {
        t.Fatalf("FetchUsage failed: %v", err)
    }
    // 验证数据
}
```

### memStore 测试辅助

```go
type memStore struct{ data map[string]string }

func (m *memStore) Get(key string) (string, error) { return m.data[key], nil }
func (m *memStore) Set(key, value string) error     { m.data[key] = value; return nil }
func (m *memStore) Delete(key string) error          { delete(m.data, key); return nil }
func (m *memStore) Exists(key string) (bool, error)  { _, ok := m.data[key]; return ok, nil }
func (m *memStore) Keys() ([]string, error) {
    keys := make([]string, 0, len(m.data))
    for k := range m.data { keys = append(keys, k) }
    return keys, nil
}
```

### 前端类型检查

```bash
cd frontend && npx tsc -b
```

### 代码质量检查

```bash
go vet ./...
cd frontend && npm run lint
```

---

## 7. 构建与发布

### 本地构建

```bash
# 生产构建
wails build

# macOS — 指定架构
wails build -platform darwin/arm64
wails build -platform darwin/amd64

# Linux
wails build -platform linux/amd64

# Windows
wails build -platform windows/amd64
```

### 构建产物

| 平台 | 路径 | 大小 (约) |
|------|------|---------|
| macOS | `build/bin/CodeBar.app` | 9 MB (arm64) |
| Linux | `build/bin/CodeBar` | — |
| Windows | `build/bin/CodeBar.exe` | — |

### macOS 代码签名

```bash
# Ad-hoc 签名 (本地使用)
codesign --force --deep --sign - build/bin/CodeBar.app

# 开发者签名 (分发)
codesign --force --deep --sign "Developer ID Application: ..." build/bin/CodeBar.app
```

### Info.plist 配置

关键配置项 (`build/darwin/Info.plist`):

- `LSUIElement: 1` — 不显示 Dock 图标 (菜单栏应用)
- `NSHighResolutionCapable: true` — Retina 支持
- `LSMinimumSystemVersion: 10.13.0` — 最低 macOS 版本

---

## 8. 常见问题

### Q: 为什么 Linux/Windows 的凭据存储回退到文件?

A: MVP 阶段优先保证功能可用。`libsecretStore` 和 `dpapiStore` 目前委托给 `fileStore` (AES-GCM 加密)。后续版本会完善原生 D-Bus/DPAPI 实现。

### Q: Keychain 写入失败怎么办?

A: `Set()` 使用 delete-then-add 模式避免重复键错误。如果仍然失败，检查 Keychain Access 中是否有 "codebar" 服务的权限问题。

### Q: 如何调试 Provider API 调用?

A: 使用 `slog` 日志。Tracker 会在 `fetchOne()` 失败时输出 warning:

```
slog.Warn("provider fetch failed", "provider", p.Name(), "err", err)
```

运行 `wails dev` 时日志输出到终端。

### Q: 前端如何知道 Provider 是否已配置?

A: `ListKnownProviders()` 返回每个 provider 的 `configured` 字段 (`"true"/"false"`)。前端据此决定是否显示绿色指示器和空状态引导。

### Q: 为什么使用 init() 自注册而不是显式注册?

A: 零耦合。新 provider 只需创建一个文件，`go build` 自动编译并注册。无需在 main.go 或其他文件中添加 import 或注册代码。

### Q: tray 标签轮换如何工作?

A: `main.go` 中的协程每 5 秒递增 `atomic.Int64` 索引，从 `trayLabels` 切片中取下一个 provider 名，查找其最新 snapshot，格式化为 `"ZM 83%"` 并调用 `sysTray.UpdateLabel()`。

### Q: SingleInstanceLock 如何工作?

A: Wails v2 的 `SingleInstanceLock` 使用 OS 级别的锁机制。当第二个实例启动时:
1. 检测到锁已被持有
2. 将启动参数发送给第一个实例
3. 第一个实例的 `OnSecondInstanceLaunch` 回调被触发
4. 第一个实例显示窗口并发送 `"second-instance"` 事件
5. 第二个实例自动退出
