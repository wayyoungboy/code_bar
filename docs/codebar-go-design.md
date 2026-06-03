# CodeBar Go — Design Spec

> Historical draft. This document describes an earlier Go + Wails rewrite idea and is not the current implementation.
> The active app is the SwiftUI + AppKit macOS implementation documented in `README.md`, `docs/architecture.md`, and `docs/developer-guide.md`.

## Problem

CodeBar is macOS-only (SwiftUI + AppKit). The architecture tightly couples UI with provider logic, and adding new platforms requires modifying enum-based switch statements throughout the codebase.

## Goal

Rewrite CodeBar in Go + Wails to achieve cross-platform support (macOS / Linux / Windows) while keeping the project lightweight and independently maintained.

## Architecture

```
code_bar/
├── cmd/app/main.go              # Wails app entry point
├── internal/
│   ├── provider/
│   │   ├── provider.go          # PlatformProvider interface + registry
│   │   ├── amp.go
│   │   ├── antigravity.go
│   │   ├── bailian.go           # 阿里云百炼
│   │   ├── claude.go
│   │   ├── codex.go
│   │   ├── copilot.go
│   │   ├── cursor.go
│   │   ├── factory.go
│   │   ├── gemini.go
│   │   ├── jetbrains.go
│   │   ├── kimi.go
│   │   ├── kiro.go
│   │   ├── minimax.go
│   │   ├── opencode.go
│   │   ├── perplexity.go
│   │   ├── synthetic.go
│   │   ├── windsurf.go
│   │   ├── zai.go
│   │   └── zenmux.go
│   ├── config/
│   │   └── store.go             # Cross-platform credential storage
│   └── tracker/
│       └── tracker.go           # Scheduled refresh, cache, notifications
├── frontend/
│   └── src/
│       ├── App.tsx              # Main usage panel
│       ├── components/
│       │   ├── UsageCard.tsx
│       │   ├── ProgressBar.tsx
│       │   └── Settings.tsx
│       └── wailsjs/             # Auto-generated Go bindings
└── wails.json
```

## Core Interface

```go
type PlatformProvider interface {
    Name() string              // "阿里云百炼"
    Icon() string              // icon key for frontend
    IsConfigured() bool        // credentials present?
    FetchUsage() (*Usage, error)
    ValidateConfig() error     // test credentials against API
}

type Usage struct {
    PlatformName string
    PlanType     string
    Items        []UsageItem
    ExtraInfo    []ExtraInfoKV
}

type UsageItem struct {
    Key        string
    Label      string
    Used       float64
    Total      float64
    Unit       string
    ResetDate  time.Time
}

type ExtraInfoKV struct {
    Label string
    Value string
}
```

## Provider Registration

Each provider file has an `init()` that registers itself:

```go
// bailian.go
func init() { RegisterProvider(&BailianProvider{}) }
```

New provider = one `.go` file implementing the interface. No other code changes needed.

## Credential Storage

Platform-specific storage via a unified `config.Store` interface:

| Platform | Storage |
|----------|---------|
| macOS    | Keychain (`github.com/keybase/go-keychain`) |
| Linux    | libsecret over D-Bus |
| Windows  | DPAPI via `golang.org/x/sys/windows` |

Fallback: encrypted file store for platforms without native secret storage.

## Tracker

`tracker.Tracker` manages the lifecycle:
- Loads all registered providers at startup
- Restores cached usage from disk (cold start display)
- Refreshes every 60s + random jitter (−5s to +5s) to avoid rate limiting
- Pushes new data to frontend via `runtime.EventsEmit()`
- Persists cache to disk after each refresh

## UI (Wails Frontend)

- **Tray icon** with dynamic text label: `百炼 45%` (single platform) or rotating between platforms (multi-platform, 5s cycle)
- **Popover panel** on click: usage cards with progress bars, plan info, last-refresh timestamp
- **Settings window**: credential configuration, per-platform display toggles
- **React + Tailwind**: consistent styling language with openusage project

## Data Flow

```
[Timer] → Tracker → Provider.FetchUsage() → Go struct
                                          → runtime.EventsEmit()
                                          → React state update
                                          → UsageCard render
```

## MVP Scope (v1)

1. Tray icon with dynamic text (usage percentage)
2. Popover panel with usage cards (progress bars + plan info)
3. Settings window (configure credentials per-platform, display toggles)
4. Scheduled refresh (60s + jitter) with disk cache
5. Cold start: show cached data immediately
6. All 19 providers from openusage:

| Provider | Auth | Key Fields |
|----------|------|------------|
| Amp | env/API key | credits |
| Antigravity | API key | quota |
| 百炼 | cookies + token | tokens |
| Claude | OAuth / credentials file | 5h, 7d, Opus utilization |
| Codex | env/API key | credits |
| Copilot | API key | quota |
| Cursor | API key | credits |
| Factory | API key | usage |
| Gemini | API key | quota |
| JetBrains | token | usage |
| Kimi | API key | quota |
| Kiro | API key | credits |
| MiniMax | API key | tokens |
| OpenCode Go | API key | credits |
| Perplexity | API key | queries |
| Synthetic | API key | credits |
| Windsurf | API key | credits |
| Z.ai | API key | credits |
| ZenMux | API key | flows (5h/7d/monthly) |

## Post-MVP (v2+)

1. System notifications (quota refresh alerts)
2. Low-usage warning badges
3. Update checker
4. Dark mode
5. Additional providers as openusage adds more

## Not in Scope

- Plugin sandbox (QuickJS) — personal project, compile-time registration is sufficient
- Feature parity with openusage — CodeBar is a separate product with its own identity
- Auto-update mechanism for MVP

## Platform Support

| Platform | Status |
|----------|--------|
| macOS    | Full (tray + panel + settings) |
| Linux    | Supported by Wails (systray may vary by DE) |
| Windows  | Supported by Wails (systray native) |
