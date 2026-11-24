#!/usr/bin/env python3
"""Build the static CodeBar GitHub Pages site (English default, /zh/, /ja/)."""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(__file__).resolve().parent / "src"
DIST = Path(__file__).resolve().parent / "dist"

PAGES = {
    "en": {"dir": "", "lang": "en", "path": "./", "to_en": "./", "to_zh": "zh/", "to_ja": "ja/"},
    "zh": {"dir": "zh", "lang": "zh-CN", "path": "zh/", "to_en": "../", "to_zh": "./", "to_ja": "../ja/"},
    "ja": {"dir": "ja", "lang": "ja", "path": "ja/", "to_en": "../", "to_zh": "../zh/", "to_ja": "./"},
}

COPY_ASSETS = [
    (ROOT / "logo" / "codebar-mark.svg", "assets/codebar-mark.svg"),
    (ROOT / "logo" / "png" / "codebar-mark-32.png", "assets/favicon-32.png"),
    (ROOT / "logo" / "png" / "codebar-mark-64.png", "assets/favicon-64.png"),
    (ROOT / "screenshots" / "image5.png", "assets/screenshot-modules.png"),
    (ROOT / "screenshots" / "codex-usage.png", "assets/screenshot-codex.png"),
    (ROOT / "screenshots" / "image4.png", "assets/screenshot-notify.png"),
    (SRC / "styles.css", "assets/styles.css"),
]

T = {
    "en": {
        "title": "CodeBar — AI coding usage in the macOS menu bar",
        "description": "A macOS menu bar app that watches BaiLian, ZenMux, MiMo, Codex, Gemini, Grok, and Antigravity quotas, plus OpenAI API costs.",
        "brand": "CodeBar",
        "nav_features": "Features",
        "nav_install": "Install",
        "nav_requirements": "Requirements",
        "nav_github": "GitHub",
        "lang_en": "English",
        "lang_zh": "简体中文",
        "lang_ja": "日本語",
        "hero_title": "AI coding usage, right in the macOS menu bar.",
        "lede": "CodeBar watches AI coding plan usage in real time. It brings quotas and reset times from BaiLian, ZenMux, MiMo, Codex, Gemini, Grok, and Antigravity, plus OpenAI API costs, into the menu bar — useful if you juggle more than one account or team allowance.",
        "cta_release": "Download the latest DMG",
        "cta_source": "View the repository",
        "cta_readme": "Full setup guide",
        "meta": "<strong>macOS 13+</strong> · Swift 5.0 · current release <strong>v2.2.10</strong> · MIT License",
        "mac_only": "This is a Mac app. There is no Package.swift, and it cannot be built or run on Linux or Windows. GitHub Actions compile and run script tests on macos-15; they do not launch the GUI.",
        "shot_alt": "CodeBar settings, usage popover, and menu bar modules on macOS",
        "features_h": "What it does",
        "features": [
            ("Several platforms, one menu bar", "Alibaba Cloud BaiLian, ZenMux, Xiaomi MiMo, Codex, Gemini, Grok, Antigravity, and OpenAI API billing."),
            ("One module per account", "ZenMux can be added as a separate module for each account, with its own alias, visibility, and quota windows."),
            ("Independent or rotating status items", "Show every module in the menu bar, or rotate them through a single item. An optional Island layout sits around the notch."),
            ("Reminders when a window resets", "Optional notifications per module for 5-hour, 7-day, weekly, or monthly windows."),
            ("Credentials stay on this Mac", "CodeBar writes its own settings under ~/.code_bar/. Codex and Gemini reuse local CLI OAuth; those tokens are not copied into CodeBar’s config."),
            ("Refresh with a little jitter", "Usage refreshes every 60 seconds, with a random ±5 second offset so requests do not all line up."),
        ],
        "preview_h": "Preview",
        "cap_modules": "Settings, the usage popover, and menu bar items",
        "cap_codex": "Codex usage detail",
        "cap_notify": "Quota refresh notification",
        "platforms_h": "Supported on v2.2.10",
        "platforms": [
            ("Alibaba Cloud BaiLian", "Coding Plan usage for the billing month, 5-hour, and weekly windows. Cookie, sec_token, and region come from the console."),
            ("ZenMux", "Flow usage for 5-hour and 7-day windows. Each Management API Key is its own module. Standard API keys are not accepted."),
            ("Xiaomi MiMo", "Monthly and total token usage, using the service token and user id from the platform cookies."),
            ("Codex", "Reads ~/.codex/auth.json from a ChatGPT-signed-in Codex CLI and queries the official 5-hour / 7-day subscription quotas."),
            ("Gemini", "Reads ~/.gemini/oauth_creds.json from a Google-signed-in Gemini CLI and queries official Code Assist quotas."),
            ("Grok", "Reads local OAuth under ~/.grok/, queries the weekly subscription quota over HTTP, and refreshes tokens automatically. It does not launch the full CLI."),
            ("OpenAI API", "An organization Admin API Key shows today’s and this month’s cost in USD, plus this month’s tokens and request counts. This is not a Codex subscription, and a $0.00 cost is not treated as a zero balance."),
            ("Antigravity / AGY", "Discovers a signed-in desktop Language Server, or calls an installed agy CLI. The detail page shows every model-pool quota the API actually returns."),
        ],
        "more_platforms": "Want another platform? Pull requests are welcome. Full credential steps are in the README.",
        "install_h": "Install",
        "install_release_h": "From a GitHub Release",
        "install_steps": [
            "Open the Releases page and download the latest CodeBar.dmg (the current latest tag is v2.2.10).",
            "Open the DMG and drag CodeBar into Applications.",
            "The first launch may say the developer cannot be verified, or that the app is damaged. The DMG is not notarized by Apple. In System Settings → Privacy & Security choose Open Anyway, or run: xattr -cr /Applications/CodeBar.app",
            "After it starts, look in the menu bar. There is no Dock icon (LSUIElement is set).",
        ],
        "install_source_h": "Build from source",
        "install_source": "You need a Mac and full Xcode 15.0 or later, not just Command Line Tools. Clone the repository, open CodeBar.xcodeproj, choose scheme CodeBar and destination My Mac, then Run. Unsigned command-line builds and the interactive ./build.sh script are documented in the README. ./build.sh asks questions in the terminal and will hang in CI.",
        "req_h": "System requirements",
        "req_rows": [
            ("Run / deploy target", "macOS 13.0+"),
            ("Language", "Swift 5.0"),
            ("Local development", "Xcode 15.0+ (full Xcode.app)"),
            ("Project shape", "CodeBar.xcodeproj / scheme CodeBar / CodeBar.app"),
            ("Current release", "2.2.10"),
            ("Launch style", "Menu bar only — no Dock icon"),
        ],
        "unreleased_h": "Unreleased work",
        "unreleased": "Draft pull request #9 improves Grok subscription usage accuracy and rate-limit handling. macOS CI on that branch has passed, but the work is not merged and is not part of v2.2.10.",
        "foot": "CodeBar is released under the MIT License. Vendor logos in the app identify those services only; trademarks belong to their owners. CodeBar is not affiliated with, endorsed by, or officially authorized by Alibaba Cloud, ZenMux, Xiaomi, OpenAI, Google, or xAI.",
        "foot_archive": "The pre-update README is preserved at docs/archive/README.before-branding.md.",
    },
    "zh": {
        "title": "CodeBar — macOS 菜单栏里的 AI Coding 用量雷达",
        "description": "macOS 菜单栏应用，实时查看百炼、ZenMux、MiMo、Codex、Gemini、Grok、Antigravity 的额度，以及 OpenAI API 费用。",
        "brand": "CodeBar",
        "nav_features": "功能",
        "nav_install": "安装",
        "nav_requirements": "系统要求",
        "nav_github": "GitHub",
        "lang_en": "English",
        "lang_zh": "简体中文",
        "lang_ja": "日本語",
        "hero_title": "macOS 菜单栏里的 AI Coding 用量雷达。",
        "lede": "一个实时监控 AI Coding 平台额度的 macOS 菜单栏应用。把 BaiLian、ZenMux、MiMo、Codex、Gemini、Grok、Antigravity 的用量与重置时间，以及 OpenAI API 费用收进菜单栏，适合同时维护多个账号、多个团队额度的人。",
        "cta_release": "下载最新 DMG",
        "cta_source": "打开仓库",
        "cta_readme": "完整配置说明",
        "meta": "<strong>macOS 13+</strong> · Swift 5.0 · 当前发行版 <strong>v2.2.10</strong> · MIT 许可证",
        "mac_only": "必须用 Mac。仓库没有 Package.swift，也不能在 Linux / Windows 上构建或运行。GitHub Actions 只在 macos-15 上做编译和脚本测试，不会启动 GUI。",
        "shot_alt": "macOS 上的 CodeBar 设置、用量弹窗和菜单栏模块",
        "features_h": "功能特性",
        "features": [
            ("多平台，一个菜单栏", "阿里云百炼、ZenMux、小米 MiMo、Codex、Gemini、Grok、Antigravity，以及 OpenAI API 计费。"),
            ("按账号添加模块", "ZenMux 可为每个账号添加独立模块，别名、可见性和配额周期都可以分开设置。"),
            ("独立或轮播状态项", "每个模块单独占据菜单栏，或在同一个状态项里轮播。也可以切换刘海 Island 展示。"),
            ("额度刷新时可提醒", "5 小时、7 天、周、月等周期可按模块开启通知。"),
            ("凭据留在本机", "CodeBar 自身配置写入 ~/.code_bar/。Codex 和 Gemini 复用本机 CLI 的 OAuth，不会把 token 复制到 CodeBar 配置里。"),
            ("自动刷新并加 jitter", "每 60 秒刷新一次用量，并带 ±5 秒随机偏移，避免请求挤在同一时刻。"),
        ],
        "preview_h": "预览",
        "cap_modules": "设置、用量弹窗和菜单栏",
        "cap_codex": "Codex 用量详情",
        "cap_notify": "额度刷新通知",
        "platforms_h": "v2.2.10 已支持的平台",
        "platforms": [
            ("阿里云百炼", "监控 Coding Plan 的账单月、5 小时和周用量。Cookie、sec_token 和区域从控制台获取。"),
            ("ZenMux", "监控 5 小时和 7 天的 Flow 用量。每个 Management API Key 都是独立模块。标准 API Key 无效。"),
            ("小米 MiMo", "监控月用量和总 Token 用量，使用平台 Cookie 中的 Service Token 和 User ID。"),
            ("Codex", "读取已登录 ChatGPT 的 Codex CLI 凭据文件 ~/.codex/auth.json，查询官方 5 小时 / 7 天订阅额度。"),
            ("Gemini", "读取已用 Google 登录的 Gemini CLI 凭据文件 ~/.gemini/oauth_creds.json，查询官方 Code Assist 配额。"),
            ("Grok", "读取 ~/.grok/ 下的本机 OAuth，通过 HTTP 查询订阅周额度并自动刷新令牌，不会启动完整 CLI。"),
            ("OpenAI API", "使用组织 Admin API Key，以美元显示今日和本月费用，以及本月 Token 与请求数。这与 Codex 订阅无关，也不会把 $0.00 费用当成余额为零。"),
            ("Antigravity / AGY", "自动发现已登录的桌面 Language Server，或调用已安装的 agy CLI。详情页展示接口实际返回的全部模型池额度。"),
        ],
        "more_platforms": "想支持更多平台？欢迎提交 PR。完整凭据步骤见 README。",
        "install_h": "安装",
        "install_release_h": "从 GitHub Release 下载",
        "install_steps": [
            "打开 Releases 页面，下载最新的 CodeBar.dmg（当前最新 tag 为 v2.2.10）。",
            "打开 DMG，把 CodeBar 拖到“应用程序”。",
            "首次打开时，系统可能提示无法验证开发者或文件已损坏。DMG 未经 Apple 公证。可在“系统设置 → 隐私与安全性”中选择“仍要打开”，或执行：xattr -cr /Applications/CodeBar.app",
            "启动后看菜单栏。没有 Dock 图标（已设置 LSUIElement）。",
        ],
        "install_source_h": "从源码构建",
        "install_source": "需要 Mac 和完整的 Xcode 15.0 或更高版本，只装 Command Line Tools 不够。克隆仓库，打开 CodeBar.xcodeproj，选择 scheme CodeBar 和 destination My Mac，然后 Run。无签名的命令行构建和交互式 ./build.sh 见 README。./build.sh 会在终端提问，在 CI 里会卡住。",
        "req_h": "系统要求",
        "req_rows": [
            ("运行 / 部署目标", "macOS 13.0+"),
            ("语言", "Swift 5.0"),
            ("本地开发", "Xcode 15.0+（完整 Xcode.app）"),
            ("工程形态", "CodeBar.xcodeproj / scheme CodeBar / CodeBar.app"),
            ("当前发行版", "2.2.10"),
            ("启动形态", "只出现在菜单栏，没有 Dock 图标"),
        ],
        "unreleased_h": "尚未发布的改动",
        "unreleased": "草稿 PR #9 改进了 Grok 订阅用量显示和限流处理。该分支上的 macOS CI 已通过，但尚未合并，也不包含在 v2.2.10 中。",
        "foot": "CodeBar 以 MIT 许可证发布。应用中的平台 Logo 仅用于标识对应服务，商标归各自权利方所有。CodeBar 与阿里云、ZenMux、小米、OpenAI、Google、xAI 无官方从属、授权或背书关系。",
        "foot_archive": "更新前的 README 原文保存在 docs/archive/README.before-branding.md。",
    },
    "ja": {
        "title": "CodeBar — macOS メニューバーで AI コーディング枠の使用量を見守る",
        "description": "BaiLian、ZenMux、MiMo、Codex、Gemini、Grok、Antigravity の枠と、OpenAI API の費用を、macOS メニューバーで見守るアプリです。",
        "brand": "CodeBar",
        "nav_features": "機能",
        "nav_install": "インストール",
        "nav_requirements": "動作環境",
        "nav_github": "GitHub",
        "lang_en": "English",
        "lang_zh": "简体中文",
        "lang_ja": "日本語",
        "hero_title": "macOS メニューバーで、AI コーディング枠の使用量を見守る。",
        "lede": "AI コーディングプランの使用量をリアルタイムで見守る、macOS メニューバーアプリです。BaiLian、ZenMux、MiMo、Codex、Gemini、Grok、Antigravity の使用量とリセット時刻、それに OpenAI API の費用をメニューバーにまとめます。複数アカウントやチーム枠を同時に扱う人向けです。",
        "cta_release": "最新の DMG を入手",
        "cta_source": "リポジトリを見る",
        "cta_readme": "詳しいセットアップ",
        "meta": "<strong>macOS 13+</strong> · Swift 5.0 · 現在のリリース <strong>v2.2.10</strong> · MIT ライセンス",
        "mac_only": "Mac が必要です。Package.swift はなく、Linux や Windows ではビルドも実行もできません。GitHub Actions は macos-15 上でコンパイルとスクリプトテストだけを行い、GUI は起動しません。",
        "shot_alt": "macOS 上の CodeBar の設定、使用量ポップオーバー、メニューバーモジュール",
        "features_h": "できること",
        "features": [
            ("複数のプラットフォームを、1 つのメニューバーで", "Alibaba Cloud BaiLian、ZenMux、Xiaomi MiMo、Codex、Gemini、Grok、Antigravity、および OpenAI API の課金。"),
            ("アカウントごとのモジュール", "ZenMux はアカウントごとに独立したモジュールを追加でき、別名、表示、クォータ周期を分けて設定できます。"),
            ("独立または回転のステータス項目", "各モジュールをメニューバーに並べるか、1 つの項目で回転表示できます。ノッチまわりの Island 表示にも切り替えられます。"),
            ("枠が更新されたときの通知", "5 時間、7 日、週、月などの周期を、モジュールごとに通知できます。"),
            ("資格情報はこの Mac に残す", "CodeBar 自身の設定は ~/.code_bar/ に書き込みます。Codex と Gemini は本機 CLI の OAuth を再利用し、トークンを CodeBar の設定へコピーしません。"),
            ("自動更新と jitter", "使用量は 60 秒ごとに更新し、±5 秒のランダムなずれを入れて、リクエストが同時刻に重ならないようにします。"),
        ],
        "preview_h": "プレビュー",
        "cap_modules": "設定、使用量ポップオーバー、メニューバー",
        "cap_codex": "Codex の使用量詳細",
        "cap_notify": "枠の更新通知",
        "platforms_h": "v2.2.10 で対応しているプラットフォーム",
        "platforms": [
            ("Alibaba Cloud BaiLian", "Coding Plan の請求月、5 時間、週の使用量。Cookie、sec_token、リージョンはコンソールから取得します。"),
            ("ZenMux", "5 時間と 7 日の Flow 使用量。Management API Key ごとに独立したモジュールになります。通常の API キーは使えません。"),
            ("Xiaomi MiMo", "月間と累計のトークン使用量。プラットフォーム Cookie の Service Token と User ID を使います。"),
            ("Codex", "ChatGPT にログイン済みの Codex CLI の ~/.codex/auth.json を読み、公式の 5 時間 / 7 日サブスクリプション枠を問い合わせます。"),
            ("Gemini", "Google でログイン済みの Gemini CLI の ~/.gemini/oauth_creds.json を読み、公式の Code Assist クォータを問い合わせます。"),
            ("Grok", "~/.grok/ の本機 OAuth を読み、HTTP で週次サブスクリプション枠を問い合わせ、トークンを自動更新します。完全な CLI は起動しません。"),
            ("OpenAI API", "組織の Admin API Key で、今日と今月の費用を USD で表示し、今月のトークン数とリクエスト数も出します。Codex サブスクリプションとは別で、$0.00 の費用を残高ゼロとはみなしません。"),
            ("Antigravity / AGY", "ログイン済みのデスクトップ Language Server を検出するか、インストール済みの agy CLI を呼びます。詳細ページには、API が実際に返すすべてのモデルプール枠を出します。"),
        ],
        "more_platforms": "ほかのプラットフォームを追加したい場合は、プルリクエストを歓迎します。資格情報の詳しい手順は README にあります。",
        "install_h": "インストール",
        "install_release_h": "GitHub Release から入手する",
        "install_steps": [
            "Releases ページを開き、最新の CodeBar.dmg をダウンロードします（現在の最新タグは v2.2.10 です）。",
            "DMG を開き、CodeBar をアプリケーションにドラッグします。",
            "初回起動時、開発元を検証できない、または破損していると表示されることがあります。DMG は Apple の公証を受けていません。システム設定 → プライバシーとセキュリティで「このまま開く」を選ぶか、次を実行します：xattr -cr /Applications/CodeBar.app",
            "起動後はメニューバーを見てください。Dock アイコンはありません（LSUIElement が設定されています）。",
        ],
        "install_source_h": "ソースからビルドする",
        "install_source": "Mac と、Command Line Tools だけではなく完全な Xcode 15.0 以降が必要です。リポジトリをクローンし、CodeBar.xcodeproj を開き、scheme CodeBar と destination My Mac を選んで Run します。署名なしのコマンドラインビルドと対話型の ./build.sh は README に書いてあります。./build.sh はターミナルで質問するため、CI では停止します。",
        "req_h": "動作環境",
        "req_rows": [
            ("実行 / デプロイ対象", "macOS 13.0+"),
            ("言語", "Swift 5.0"),
            ("ローカル開発", "Xcode 15.0+（完全な Xcode.app）"),
            ("プロジェクト形態", "CodeBar.xcodeproj / scheme CodeBar / CodeBar.app"),
            ("現在のリリース", "2.2.10"),
            ("起動形態", "メニューバーのみ。Dock アイコンなし"),
        ],
        "unreleased_h": "未リリースの作業",
        "unreleased": "草稿プルリクエスト #9 は、Grok サブスクリプション使用量の表示精度とレート制限の扱いを改善します。そのブランチの macOS CI は通っていますが、未マージであり、v2.2.10 には含まれません。",
        "foot": "CodeBar は MIT ライセンスで公開しています。アプリ内の各ベンダーロゴはサービスを識別するためだけに使っており、商標はそれぞれの権利者に属します。CodeBar は Alibaba Cloud、ZenMux、Xiaomi、OpenAI、Google、xAI と提携しておらず、後援や公式な許諾も受けていません。",
        "foot_archive": "更新前の README 全文は docs/archive/README.before-branding.md に保存しています。",
    },
}

TEMPLATE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <meta name="description" content="{description}" />
  <link rel="canonical" href="{canonical}" />
  <link rel="alternate" hreflang="en" href="{canon_en}" />
  <link rel="alternate" hreflang="zh-CN" href="{canon_zh}" />
  <link rel="alternate" hreflang="ja" href="{canon_ja}" />
  <link rel="icon" type="image/png" sizes="32x32" href="{base}assets/favicon-32.png" />
  <link rel="icon" type="image/png" sizes="64x64" href="{base}assets/favicon-64.png" />
  <link rel="icon" type="image/svg+xml" href="{base}assets/codebar-mark.svg" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="{base}assets/styles.css" />
</head>
<body>
  <header class="bar">
    <a class="brand" href="{self_path}"><img src="{base}assets/codebar-mark.svg" alt="" width="28" height="28" />{brand}</a>
    <nav class="nav-links" aria-label="section">
      <a href="#features">{nav_features}</a>
      <a href="#install">{nav_install}</a>
      <a href="#requirements">{nav_requirements}</a>
      <a href="https://github.com/wayyoungboy/code_bar">{nav_github}</a>
    </nav>
    <nav class="langs" aria-label="Language">
      {lang_switch}
    </nav>
  </header>

  <main>
    <section class="hero">
      <img src="{base}assets/codebar-mark.svg" alt="CodeBar" width="88" height="88" />
      <h1>{hero_title}</h1>
      <p class="lede">{lede}</p>
      <div class="cta">
        <a class="btn primary" href="https://github.com/wayyoungboy/code_bar/releases/latest">{cta_release}</a>
        <a class="btn" href="https://github.com/wayyoungboy/code_bar">{cta_source}</a>
        <a class="btn" href="{readme_url}">{cta_readme}</a>
      </div>
      <p class="meta">{meta}</p>
      <p class="callout">{mac_only}</p>
    </section>

    <figure class="shot">
      <img src="{base}assets/screenshot-modules.png" alt="{shot_alt}" />
    </figure>

    <section class="wrap" id="features">
      <h2>{features_h}</h2>
      <div class="grid">
        {feature_cards}
      </div>
    </section>

    <section class="wrap" id="preview">
      <h2>{preview_h}</h2>
      <div class="gallery">
        <figure>
          <img src="{base}assets/screenshot-modules.png" alt="{cap_modules}" />
          <figcaption>{cap_modules}</figcaption>
        </figure>
        <div>
          <figure>
            <img src="{base}assets/screenshot-codex.png" alt="{cap_codex}" />
            <figcaption>{cap_codex}</figcaption>
          </figure>
          <figure style="margin-top:14px">
            <img src="{base}assets/screenshot-notify.png" alt="{cap_notify}" />
            <figcaption>{cap_notify}</figcaption>
          </figure>
        </div>
      </div>
    </section>

    <section class="wrap" id="platforms">
      <h2>{platforms_h}</h2>
      <div class="grid">
        {platform_cards}
      </div>
      <p class="prose" style="margin-top:16px">{more_platforms}</p>
    </section>

    <section class="wrap" id="install">
      <h2>{install_h}</h2>
      <h3>{install_release_h}</h3>
      <ol class="setup">{install_items}</ol>
      <h3>{install_source_h}</h3>
      <p class="prose">{install_source}</p>
      <pre><code>git clone https://github.com/wayyoungboy/code_bar.git
cd code_bar
open CodeBar.xcodeproj</code></pre>
    </section>

    <section class="wrap" id="requirements">
      <h2>{req_h}</h2>
      <table>
        <tbody>
          {req_rows}
        </tbody>
      </table>
    </section>

    <section class="wrap">
      <h2>{unreleased_h}</h2>
      <p class="prose">{unreleased} <a href="https://github.com/wayyoungboy/code_bar/pull/9">PR #9</a></p>
    </section>
  </main>

  <footer class="foot">
    <div class="wrap">
      <p>{foot}</p>
      <p>{foot_archive}</p>
    </div>
  </footer>
</body>
</html>
"""

README_URL = {
    "en": "https://github.com/wayyoungboy/code_bar/blob/main/README.md",
    "zh": "https://github.com/wayyoungboy/code_bar/blob/main/README.zh-CN.md",
    "ja": "https://github.com/wayyoungboy/code_bar/blob/main/README.ja.md",
}


def esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def maybe_html(s: str) -> str:
    # meta line already contains <strong>
    return s


def cards(items) -> str:
    out = []
    for title, body in items:
        out.append(f"<article class=\"card\"><h3>{esc(title)}</h3><p>{esc(body)}</p></article>")
    return "\n        ".join(out)


def language_switch(key: str, t: dict, page: dict) -> str:
    items = [
        ("en", t["lang_en"], page["to_en"]),
        ("zh", t["lang_zh"], page["to_zh"]),
        ("ja", t["lang_ja"], page["to_ja"]),
    ]
    bits = []
    for k, label, href in items:
        if k == key:
            bits.append(f'<span class="current" aria-current="page">{esc(label)}</span>')
        else:
            bits.append(f'<a href="{href}">{esc(label)}</a>')
    return "\n      ".join(bits)


def render(key: str, base: str, site_origin: str) -> str:
    t = T[key]
    page = PAGES[key]
    # trailing-slash site URLs
    canon = {
        "en": f"{site_origin}{base}",
        "zh": f"{site_origin}{base}zh/",
        "ja": f"{site_origin}{base}ja/",
    }
    req_rows = "\n          ".join(
        f"<tr><th>{esc(a)}</th><td>{esc(b)}</td></tr>" for a, b in t["req_rows"]
    )
    install_items = "\n".join(f"<li>{esc(s)}</li>" for s in t["install_steps"])
    return TEMPLATE.format(
        lang=page["lang"],
        title=esc(t["title"]),
        description=esc(t["description"]),
        canonical=canon[key],
        canon_en=canon["en"],
        canon_zh=canon["zh"],
        canon_ja=canon["ja"],
        base=base,
        self_path=page["path"] if page["path"] != "./" else base or "./",
        brand=esc(t["brand"]),
        nav_features=esc(t["nav_features"]),
        nav_install=esc(t["nav_install"]),
        nav_requirements=esc(t["nav_requirements"]),
        nav_github=esc(t["nav_github"]),
        lang_switch=language_switch(key, t, page),
        hero_title=esc(t["hero_title"]),
        lede=esc(t["lede"]),
        cta_release=esc(t["cta_release"]),
        cta_source=esc(t["cta_source"]),
        cta_readme=esc(t["cta_readme"]),
        readme_url=README_URL[key],
        meta=t["meta"],
        mac_only=esc(t["mac_only"]),
        shot_alt=esc(t["shot_alt"]),
        features_h=esc(t["features_h"]),
        feature_cards=cards(t["features"]),
        preview_h=esc(t["preview_h"]),
        cap_modules=esc(t["cap_modules"]),
        cap_codex=esc(t["cap_codex"]),
        cap_notify=esc(t["cap_notify"]),
        platforms_h=esc(t["platforms_h"]),
        platform_cards=cards(t["platforms"]),
        more_platforms=esc(t["more_platforms"]),
        install_h=esc(t["install_h"]),
        install_release_h=esc(t["install_release_h"]),
        install_items=install_items,
        install_source_h=esc(t["install_source_h"]),
        install_source=esc(t["install_source"]),
        req_h=esc(t["req_h"]),
        req_rows=req_rows,
        unreleased_h=esc(t["unreleased_h"]),
        unreleased=esc(t["unreleased"]),
        foot=esc(t["foot"]),
        foot_archive=esc(t["foot_archive"]),
    )


def normalize_base(base: str) -> str:
    if not base or base == "/":
        return "/"
    if not base.startswith("/"):
        base = "/" + base
    if not base.endswith("/"):
        base += "/"
    return base


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="/code_bar/", help="GitHub Pages base path, e.g. /code_bar/")
    parser.add_argument(
        "--origin",
        default="https://wayyoungboy.github.io",
        help="Origin used only in canonical / hreflang URLs, not claimed as live",
    )
    args = parser.parse_args()
    base = normalize_base(args.base)

    if DIST.exists():
        shutil.rmtree(DIST)
    (DIST / "assets").mkdir(parents=True)

    for src, dest in COPY_ASSETS:
        target = DIST / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        if not src.exists():
            raise SystemExit(f"missing asset: {src}")
        shutil.copy2(src, target)

    for key, page in PAGES.items():
        html = render(key, base, args.origin.rstrip("/"))
        out_dir = DIST / page["dir"] if page["dir"] else DIST
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "index.html").write_text(html, encoding="utf-8")
        print("wrote", out_dir / "index.html")

    # Helpful 404 that points back to the site root (still uses the same base)
    (DIST / "404.html").write_text(
        render("en", base, args.origin.rstrip("/")).replace(
            "<h1>",
            "<h1>Page not found.</h1><p class=\"lede\"><a href=\"" + base + "\">Back to CodeBar</a></p><h1 hidden>",
            1,
        ),
        encoding="utf-8",
    )
    (DIST / ".nojekyll").write_text("", encoding="utf-8")
    print("built", DIST, "base", base)


if __name__ == "__main__":
    main()
