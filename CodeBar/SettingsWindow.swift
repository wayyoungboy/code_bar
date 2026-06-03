import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var tracker: UsageTracker
    @State private var showBailianHelp = false
    @State private var showZenMuxHelp = false
    @State private var showMimoHelp = false
    @State private var showCodexHelp = false

    // Bailian config
    @State private var cookies = ""
    @State private var secToken = ""
    @State private var region = "cn-beijing"

    // ZenMux config
    @State private var zenMuxApiKey = ""

    // Mimo config
    @State private var mimoServiceToken = ""
    @State private var mimoUserId = ""

    // Codex network config
    @State private var codexProxyURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("手动配置平台凭据以查看 AI 编程工具用量")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)

                // Bailian config
                manualConfigSection(
                    platform: .bailian,
                    icon: "cloud.fill",
                    color: .blue
                ) {
                    bailianConfigForm
                }

                // ZenMux config
                manualConfigSection(
                    platform: .zenmux,
                    icon: "bolt.fill",
                    color: .purple
                ) {
                    zenMuxConfigForm
                }

                // Mimo config
                manualConfigSection(
                    platform: .mimo,
                    icon: "m.circle.fill",
                    color: .orange
                ) {
                    mimoConfigForm
                }

                // Codex config
                manualConfigSection(
                    platform: .codex,
                    icon: "terminal.fill",
                    color: .green
                ) {
                    codexConfigForm
                }

                // ZenMux notification settings
                if tracker.providers[.zenmux]?.isConfigured == true {
                    notificationSettingsView
                        .padding(16)
                        .background(Color.purple.opacity(0.06))
                        .cornerRadius(10)
                }

                // 版本更新提醒
                HStack {
                    Image(systemName: "arrow.up.circle")
                        .foregroundColor(.orange)
                    Text("版本更新提醒")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { UpdateChecker.shared.isEnabled },
                        set: { UpdateChecker.shared.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .padding(12)
                .background(Color.orange.opacity(0.06))
                .cornerRadius(8)

                if tracker.configuredPlatforms.count > 1 {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundColor(.orange)
                        Text("多个平台已配置，菜单栏将每 5 秒轮播显示")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showBailianHelp) {
            HelpWindowView(platform: .bailian)
        }
        .sheet(isPresented: $showZenMuxHelp) {
            HelpWindowView(platform: .zenmux)
        }
        .sheet(isPresented: $showMimoHelp) {
            HelpWindowView(platform: .mimo)
        }
        .sheet(isPresented: $showCodexHelp) {
            HelpWindowView(platform: .codex)
        }
        .onAppear {
            if let config = tracker.loadBailianConfig() {
                cookies = config.cookies
                secToken = config.secToken
                region = config.region
            }
            if let config = tracker.loadZenMuxConfig() {
                zenMuxApiKey = config.apiKey
            }
            if let config = tracker.loadMimoConfig() {
                mimoServiceToken = config.serviceToken
                mimoUserId = config.userId
            }
            if let config = tracker.loadCodexConfig() {
                codexProxyURL = config.proxyURL ?? ""
            }
            tracker.checkNotificationPermission()
        }
    }

    // MARK: - Manual config section

    @ViewBuilder
    private func manualConfigSection<Content: View>(
        platform: PlatformType,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(platform.rawValue)
                    .font(.headline)
                Spacer()
                if tracker.providers[platform]?.isConfigured == true {
                    Toggle("启用", isOn: Binding(
                        get: { tracker.isPlatformEnabled(platform) },
                        set: { tracker.enabledPlatforms[platform] = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                } else {
                    Text("未配置")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            content()

            if tracker.providers[platform]?.isConfigured == true {
                Divider()
                displayTypeSelection(for: platform)
            }
        }
        .padding(16)
        .background(color.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Display type selection

    @ViewBuilder
    private func displayTypeSelection(for platform: PlatformType) -> some View {
        let items = tracker.platforms[platform]?.items ?? []

        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                HStack(spacing: 12) {
                    ForEach(items, id: \.key) { item in
                        Toggle(isOn: Binding(
                            get: { tracker.displayKeys(for: platform).contains(item.key) },
                            set: { _ in tracker.toggleDisplayType(item.key, for: platform) }
                        )) {
                            Text(item.label)
                                .font(.caption)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                HStack(spacing: 12) {
                    ForEach(items, id: \.key) { item in
                        Toggle(isOn: Binding(
                            get: { tracker.isResetTimeEnabled(item.key, for: platform) },
                            set: { _ in tracker.toggleResetTime(item.key, for: platform) }
                        )) {
                            Text("\(item.label)重置")
                                .font(.caption)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    // MARK: - Notification settings

    private var notificationSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bell.badge")
                    .foregroundColor(.orange)
                Text("额度刷新通知")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { tracker.isZenMuxNoticeEnabled },
                    set: { tracker.isZenMuxNoticeEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Image(systemName: tracker.notificationPermissionGranted ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .foregroundColor(tracker.notificationPermissionGranted ? .green : .red)
                    .font(.caption)
                Text(tracker.notificationPermissionGranted ? "通知权限已授权" : "通知权限未授权")
                    .font(.caption)
                    .foregroundColor(tracker.notificationPermissionGranted ? .green : .red)

                if !tracker.notificationPermissionGranted {
                    Button("请求权限") {
                        tracker.requestNotificationPermission()
                    }
                    .font(.caption)
                }

                Spacer()

                Button("发送测试通知") {
                    tracker.sendTestNotice()
                }
                .font(.caption)
                .disabled(!tracker.notificationPermissionGranted)
            }
        }
    }

    // MARK: - Bailian config form

    private var bailianConfigForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookie")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextEditor(text: $cookies)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 70)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sec Token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    SecureField("请输入 sec_token", text: $secToken)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("区域")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker("区域", selection: $region) {
                        Text("北京").tag("cn-beijing")
                        Text("上海").tag("cn-shanghai")
                        Text("深圳").tag("cn-shenzhen")
                        Text("杭州").tag("cn-hangzhou")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }

            HStack {
                Button(action: { showBailianHelp = true }) {
                    Image(systemName: "questionmark.circle")
                    Text("帮助")
                }
                Spacer()
                Button("保存") {
                    tracker.saveBailianConfig(cookies: cookies, secToken: secToken, region: region)
                }
                .disabled(cookies.isEmpty || secToken.isEmpty)
            }
        }
    }

    // MARK: - ZenMux config form

    private var zenMuxConfigForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Management API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("请输入 Management API Key", text: $zenMuxApiKey)
                    .textFieldStyle(.roundedBorder)
            }

            Text("仅支持 Management API Key，标准 API Key 无效")
                .font(.caption)
                .foregroundColor(.orange)

            HStack {
                Button(action: { showZenMuxHelp = true }) {
                    Image(systemName: "questionmark.circle")
                    Text("帮助")
                }
                Spacer()
                Button("保存") {
                    tracker.saveZenMuxConfig(apiKey: zenMuxApiKey)
                }
                .disabled(zenMuxApiKey.isEmpty)
            }
        }
    }

    // MARK: - Mimo config form

    private var mimoConfigForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Service Token")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("请输入 api-platform_serviceToken", text: $mimoServiceToken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("User ID")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("请输入 userId", text: $mimoUserId)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("数据准实时更新（5 分钟内延迟），每日数据次日 7:00 UTC 完成校对")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Button(action: { showMimoHelp = true }) {
                    Image(systemName: "questionmark.circle")
                    Text("帮助")
                }
                Spacer()
                Button("保存") {
                    tracker.saveMimoConfig(serviceToken: mimoServiceToken, userId: mimoUserId)
                }
                .disabled(mimoServiceToken.isEmpty || mimoUserId.isEmpty)
            }
        }
    }

    // MARK: - Codex config form

    private var codexConfigForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("自动读取 Codex CLI 的 ChatGPT OAuth 凭据，查询官方 5小时 / 7天订阅额度")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("代理地址（可选）")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:7890", text: $codexProxyURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(action: { showCodexHelp = true }) {
                    Image(systemName: "questionmark.circle")
                    Text("帮助")
                }
                Spacer()
                Button("保存代理") {
                    tracker.saveCodexProxyURL(codexProxyURL)
                }
            }
        }
    }
}

// MARK: - Help Window

struct HelpWindowView: View {
    @Environment(\.dismiss) var dismiss
    let platform: PlatformType

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(helpTitle)
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch platform {
                    case .bailian:
                        bailianHelpSteps
                    case .zenmux:
                        zenMuxHelpSteps
                    case .mimo:
                        mimoHelpSteps
                    case .codex:
                        codexHelpSteps
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: Constants.helpWindowWidth, height: Constants.helpWindowHeight)
    }

    private var helpTitle: String {
        switch platform {
        case .bailian: return "获取百炼凭据帮助"
        case .zenmux: return "获取 ZenMux API Key 帮助"
        case .mimo: return "获取小米 MiMo 凭据帮助"
        case .codex: return "获取 Codex 用量凭据帮助"
        }
    }

    private var bailianHelpSteps: some View {
        Group {
            HelpStepView(number: 1, title: "登录百炼控制台", description: "访问 https://bailian.console.aliyun.com/ 并使用阿里云账号登录", icon: "person.circle")
            HelpStepView(number: 2, title: "打开开发者工具", description: "在浏览器中按 F12 或右键点击页面选择「检查」", icon: "gear")
            HelpStepView(number: 3, title: "切换到 Network 标签", description: "在开发者工具中点击 Network（网络）标签", icon: "network")
            HelpStepView(number: 4, title: "访问 Coding Plan 页面", description: "在百炼控制台中进入 Coding Plan 页面", icon: "doc")
            HelpStepView(number: 5, title: "找到 api.json 请求", description: "在 Network 列表中找到名为 api.json 的请求", icon: "magnifyingglass")
            HelpStepView(number: 6, title: "复制凭据信息", description: "在请求头中复制 Cookie，在请求参数中复制 sec_token", icon: "doc.on.clipboard")
        }
    }

    private var zenMuxHelpSteps: some View {
        Group {
            HelpStepView(number: 1, title: "打开管理页面", description: "点击下方链接跳转到 ZenMux 平台管理页面", icon: "link")
            Button(action: {
                if let url = URL(string: "https://zenmux.ai/platform/management") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("https://zenmux.ai/platform/management")
                        .underline()
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(.leading, 48)
            HelpStepView(number: 2, title: "登录账号", description: "使用您的 ZenMux 账号登录", icon: "person.circle")
            HelpStepView(number: 3, title: "找到 API Keys", description: "在管理页面中找到 API Keys 部分", icon: "key")
            HelpStepView(number: 4, title: "复制 Management Key", description: "复制 Management API Key（不是标准 API Key）", icon: "doc.on.clipboard")
            HelpStepView(number: 5, title: "重要提示", description: "必须使用 Management API Key，标准 API Key 不支持此功能", icon: "exclamationmark.triangle")
        }
    }

    private var mimoHelpSteps: some View {
        Group {
            HelpStepView(number: 1, title: "打开 MiMo 平台", description: "访问 https://platform.xiaomimimo.com/ 并使用小米账号登录", icon: "person.circle")
            HelpStepView(number: 2, title: "打开开发者工具", description: "在浏览器中按 F12 或右键点击页面选择「检查」", icon: "gear")
            HelpStepView(number: 3, title: "切换到 Application 标签", description: "在开发者工具中点击 Application（应用）标签", icon: "network")
            HelpStepView(number: 4, title: "找到 Cookies", description: "在左侧 Cookies 中找到 https://platform.xiaomimimo.com", icon: "doc")
            HelpStepView(number: 5, title: "复制凭据", description: "复制 api-platform_serviceToken 和 userId 的值", icon: "doc.on.clipboard")
        }
    }

    private var codexHelpSteps: some View {
        Group {
            HelpStepView(number: 1, title: "安装 Codex CLI", description: "安装并打开 OpenAI Codex CLI", icon: "terminal")
            HelpStepView(number: 2, title: "使用 ChatGPT 登录", description: "通过 Codex CLI 登录 ChatGPT 账号，使 ~/.codex/auth.json 或 Keychain 中生成 OAuth 凭据", icon: "person.circle")
            HelpStepView(number: 3, title: "自动检测", description: "CodeBar 会自动读取 Codex Auth 或 ~/.codex/auth.json，不需要手动填写凭据", icon: "key")
            HelpStepView(number: 4, title: "代理可选", description: "无法直连 chatgpt.com 时，可填写 http 或 socks5 代理地址", icon: "network")
        }
    }
}

struct HelpStepView: View {
    let number: Int
    let title: String
    let description: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
