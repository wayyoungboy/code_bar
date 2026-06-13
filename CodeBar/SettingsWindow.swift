import SwiftUI

struct ModuleEditorSession: Identifiable {
    let id: String
    let module: MonitorModule?

    static func adding() -> ModuleEditorSession {
        ModuleEditorSession(id: "add", module: nil)
    }

    static func editing(_ module: MonitorModule) -> ModuleEditorSession {
        ModuleEditorSession(id: "edit-\(module.id)", module: module)
    }
}

struct SettingsWindowView: View {
    @ObservedObject var tracker: UsageTracker
    @State private var moduleEditorSession: ModuleEditorSession?
    @State private var showBailianHelp = false
    @State private var showZenMuxHelp = false
    @State private var showMimoHelp = false
    @State private var showCodexHelp = false
    @State private var showGeminiHelp = false

    // Bailian config
    @State private var cookies = ""
    @State private var secToken = ""
    @State private var region = "cn-beijing"

    // ZenMux config
    @State private var zenMuxAccounts: [ZenMuxAccountConfig] = []
    @State private var editingZenMuxAccount: ZenMuxAccountConfig?
    @State private var showZenMuxAccountEditor = false
    @State private var testingZenMuxAccountID: String?
    @State private var zenMuxAccountTestMessages: [String: String] = [:]

    // Mimo config
    @State private var mimoServiceToken = ""
    @State private var mimoUserId = ""

    // Codex network config
    @State private var codexProxyURL = ""

    // Gemini network config
    @State private var geminiProxyURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                moduleManagementSection

                systemSettingsSection

                footerSection
            }
            .padding(20)
        }
        .sheet(item: $moduleEditorSession) { session in
            ModuleEditorView(module: session.module, existingModules: tracker.modules) { module in
                if session.module == nil {
                    tracker.addModule(module)
                } else {
                    tracker.updateModule(module)
                }
                moduleEditorSession = nil
            }
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
        .sheet(isPresented: $showGeminiHelp) {
            HelpWindowView(platform: .gemini)
        }
        .sheet(isPresented: $showZenMuxAccountEditor) {
            ZenMuxAccountEditorView(account: editingZenMuxAccount) { account in
                saveZenMuxAccount(account)
            }
        }
        .onAppear {
            tracker.checkNotificationPermission()
        }
    }

    private var moduleManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("监控模块")
                    .font(.headline)
                Spacer()
                Button {
                    moduleEditorSession = .adding()
                } label: {
                    Image(systemName: "plus.circle")
                    Text("添加模块")
                }
            }

            Text("一个模块对应一组供应商凭据。可拖动模块调整顺序，详情页和菜单栏会按该顺序展示。")
                .font(.caption)
                .foregroundColor(.secondary)

            if tracker.modules.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundColor(.secondary)
                    Text("还没有监控模块")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
            } else {
                List {
                    ForEach(tracker.sortedModules) { module in
                        moduleRow(module)
                    }
                    .onMove { source, destination in
                        tracker.moveModules(from: source, to: destination)
                    }
                }
                .frame(minHeight: CGFloat(max(1, tracker.modules.count)) * 88 + 12)
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func moduleRow(_ module: MonitorModule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PlatformLogoView(platform: module.platform)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.platform.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let alias = module.aliasDisplayName {
                        Text(alias)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    moduleEditorSession = .editing(module)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("编辑模块")

                Button(role: .destructive) {
                    tracker.deleteModule(module)
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除模块")
            }

            HStack(spacing: 14) {
                moduleBoolToggle(module, title: "监控", keyPath: \.isMonitoringEnabled)
                moduleBoolToggle(module, title: "bar栏", keyPath: \.showInMenuBar)
                moduleBoolToggle(module, title: "详情页", keyPath: \.showInDetail)
                moduleBoolToggle(module, title: "通知", keyPath: \.isNotificationEnabled)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func moduleBoolToggle(_ module: MonitorModule, title: String, keyPath: WritableKeyPath<MonitorModule, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { tracker.modules.first(where: { $0.id == module.id })?[keyPath: keyPath] ?? false },
            set: { enabled in
                tracker.updateModule(id: module.id) { draft in
                    draft[keyPath: keyPath] = enabled
                }
            }
        )) {
            Text(title)
                .font(.caption)
        }
        .toggleStyle(.checkbox)
    }

    private var systemSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统配置")
                .font(.headline)

            notificationSettingsView

            HStack {
                Image(systemName: "menubar.rectangle")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("bar 栏展示形式")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(tracker.menuBarDisplayMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("bar 栏展示形式", selection: $tracker.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()
            }

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
        }
        .padding(16)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(10)
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 12) {
                Label("作者：wayyoungboy", systemImage: "person.circle")

                Spacer()

                Link(destination: URL(string: "https://github.com/wayyoungboy/code_bar")!) {
                    Label("GitHub 主页", systemImage: "link")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
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
                PlatformLogoView(platform: platform)
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

            if tracker.providers[platform]?.isConfigured == true, platform != .zenmux {
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
                    get: { tracker.isQuotaRefreshNoticeEnabled },
                    set: { tracker.isQuotaRefreshNoticeEnabled = $0 }
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
            HStack {
                Button(action: { showZenMuxHelp = true }) {
                    Image(systemName: "questionmark.circle")
                    Text("帮助")
                }
                Spacer()
                Button {
                    editingZenMuxAccount = nil
                    showZenMuxAccountEditor = true
                } label: {
                    Image(systemName: "plus.circle")
                    Text("添加账号")
                }
            }

            Text("每个 ZenMux 账号独立保存别名、Management API Key、显示项和重置时间。菜单栏显示所有启用项的聚合用量。")
                .font(.caption)
                .foregroundColor(.secondary)

            if zenMuxAccounts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "key")
                        .foregroundColor(.secondary)
                    Text("还没有 ZenMux 账号")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(zenMuxAccounts) { account in
                        zenMuxAccountRow(account)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func zenMuxAccountRow(_ account: ZenMuxAccountConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(maskedKey(account.apiKey))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    testZenMuxAccount(account)
                } label: {
                    if testingZenMuxAccountID == account.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal")
                    }
                }
                .help("测试账号")
                .disabled(testingZenMuxAccountID != nil)

                Button {
                    editingZenMuxAccount = account
                    showZenMuxAccountEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("编辑账号")

                Button(role: .destructive) {
                    deleteZenMuxAccount(account)
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除账号")
            }

            HStack(spacing: 14) {
                Text("显示")
                    .font(.caption)
                    .foregroundColor(.secondary)
                zenMuxAccountToggle(account: account, key: "5hour", title: "5小时", kind: .display)
                zenMuxAccountToggle(account: account, key: "7day", title: "7天", kind: .display)
                Spacer()
            }

            HStack(spacing: 14) {
                Text("重置")
                    .font(.caption)
                    .foregroundColor(.secondary)
                zenMuxAccountToggle(account: account, key: "5hour", title: "5小时", kind: .reset)
                zenMuxAccountToggle(account: account, key: "7day", title: "7天", kind: .reset)
                Spacer()
            }

            if let message = zenMuxAccountTestMessages[account.id] {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.hasPrefix("成功") ? .green : .red)
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(8)
    }

    private enum ZenMuxToggleKind {
        case display
        case reset
    }

    @ViewBuilder
    private func zenMuxAccountToggle(account: ZenMuxAccountConfig, key: String, title: String, kind: ZenMuxToggleKind) -> some View {
        Toggle(isOn: Binding(
            get: {
                switch kind {
                case .display:
                    return account.displayKeys.contains(key)
                case .reset:
                    return account.resetTimeKeys.contains(key)
                }
            },
            set: { enabled in
                updateZenMuxAccount(account.id) { draft in
                    switch kind {
                    case .display:
                        if enabled {
                            if !draft.displayKeys.contains(key) {
                                draft.displayKeys.append(key)
                            }
                        } else {
                            draft.displayKeys.removeAll { $0 == key }
                            draft.resetTimeKeys.removeAll { $0 == key }
                        }
                    case .reset:
                        guard draft.displayKeys.contains(key) else { return }
                        if enabled {
                            if !draft.resetTimeKeys.contains(key) {
                                draft.resetTimeKeys.append(key)
                            }
                        } else {
                            draft.resetTimeKeys.removeAll { $0 == key }
                        }
                    }
                }
            }
        )) {
            Text(title)
                .font(.caption)
        }
        .toggleStyle(.checkbox)
        .disabled(kind == .reset && !account.displayKeys.contains(key))
    }

    private func saveZenMuxAccount(_ account: ZenMuxAccountConfig) {
        if let index = zenMuxAccounts.firstIndex(where: { $0.id == account.id }) {
            zenMuxAccounts[index] = account
        } else {
            zenMuxAccounts.append(account)
        }
        persistZenMuxAccounts()
    }

    private func deleteZenMuxAccount(_ account: ZenMuxAccountConfig) {
        zenMuxAccounts.removeAll { $0.id == account.id }
        zenMuxAccountTestMessages[account.id] = nil
        persistZenMuxAccounts()
    }

    private func updateZenMuxAccount(_ id: String, mutate: (inout ZenMuxAccountConfig) -> Void) {
        guard let index = zenMuxAccounts.firstIndex(where: { $0.id == id }) else { return }
        mutate(&zenMuxAccounts[index])
        persistZenMuxAccounts()
    }

    private func persistZenMuxAccounts() {
        tracker.saveZenMuxConfig(ZenMuxConfig(accounts: zenMuxAccounts))
    }

    private func testZenMuxAccount(_ account: ZenMuxAccountConfig) {
        testingZenMuxAccountID = account.id
        zenMuxAccountTestMessages[account.id] = nil
        Task {
            do {
                let provider = ZenMuxProvider(config: ZenMuxConfig(accounts: [account]))
                let usage = try await provider.fetchUsage()
                let summary = usage.items.map { "\($0.label) \(String(format: "%.0f%%", $0.percent))" }.joined(separator: " / ")
                await MainActor.run {
                    zenMuxAccountTestMessages[account.id] = summary.isEmpty ? "成功：账号可用" : "成功：\(summary)"
                    testingZenMuxAccountID = nil
                }
            } catch {
                let message = (error as? PlatformError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    zenMuxAccountTestMessages[account.id] = "失败：\(message)"
                    testingZenMuxAccountID = nil
                }
            }
        }
    }

    private func maskedKey(_ key: String) -> String {
        if key.isEmpty {
            return "未填写 API Key"
        }
        guard key.count > 10 else { return "API Key 过短" }
        return "\(key.prefix(6))...\(key.suffix(4))"
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

struct ZenMuxAccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alias: String
    @State private var apiKey: String

    private let originalAccount: ZenMuxAccountConfig?
    let onSave: (ZenMuxAccountConfig) -> Void

    init(account: ZenMuxAccountConfig?, onSave: @escaping (ZenMuxAccountConfig) -> Void) {
        self.originalAccount = account
        self.onSave = onSave
        _alias = State(initialValue: account?.alias ?? "")
        _apiKey = State(initialValue: account?.apiKey ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(originalAccount == nil ? "添加 ZenMux 账号" : "编辑 ZenMux 账号")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("账号别名")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("例如 项目 A / 团队账号", text: $alias)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Management API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("请输入 Management API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("仅支持 Management API Key，标准 API Key 无效")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    var account = originalAccount ?? ZenMuxAccountConfig()
                    account.alias = alias
                    account.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(account)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct ModuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let module: MonitorModule?
    let existingModules: [MonitorModule]
    let onSave: (MonitorModule) -> Void

    @State private var provider: PlatformType
    @State private var alias: String
    @State private var cookies: String
    @State private var secToken: String
    @State private var region: String
    @State private var zenMuxApiKey: String
    @State private var mimoServiceToken: String
    @State private var mimoUserId: String
    @State private var codexProxyURL: String
    @State private var geminiProxyURL: String
    @State private var displayKeys: Set<String>
    @State private var resetTimeKeys: Set<String>
    @State private var isMonitoringEnabled: Bool
    @State private var showInMenuBar: Bool
    @State private var showInDetail: Bool
    @State private var isNotificationEnabled: Bool

    init(module: MonitorModule?, existingModules: [MonitorModule] = [], onSave: @escaping (MonitorModule) -> Void) {
        self.module = module
        self.existingModules = existingModules
        self.onSave = onSave

        let initialProvider = module?.platform ?? .zenmux
        _provider = State(initialValue: initialProvider)
        _alias = State(initialValue: module?.editorAlias ?? "")
        let initialDisplayKeys = module?.editorDisplayKeys ?? ModuleEditorView.defaultDisplayKeys(for: initialProvider)
        _displayKeys = State(initialValue: Set(initialDisplayKeys.isEmpty ? ModuleEditorView.defaultDisplayKeys(for: initialProvider) : initialDisplayKeys))
        _resetTimeKeys = State(initialValue: Set(module?.editorResetTimeKeys ?? []))
        _isMonitoringEnabled = State(initialValue: module?.isMonitoringEnabled ?? true)
        _showInMenuBar = State(initialValue: module?.showInMenuBar ?? true)
        _showInDetail = State(initialValue: module?.showInDetail ?? true)
        _isNotificationEnabled = State(initialValue: module?.isNotificationEnabled ?? true)

        var initialCookies = ""
        var initialSecToken = ""
        var initialRegion = "cn-beijing"
        var initialZenMuxApiKey = ""
        var initialMimoServiceToken = ""
        var initialMimoUserId = ""
        var initialCodexProxyURL = ""
        var initialGeminiProxyURL = ""

        if let module {
            switch module.config {
            case .bailian(let config):
                initialCookies = config.cookies
                initialSecToken = config.secToken
                initialRegion = config.region
            case .zenmux(let account):
                initialZenMuxApiKey = account.apiKey
            case .mimo(let config):
                initialMimoServiceToken = config.serviceToken
                initialMimoUserId = config.userId
            case .codex(let config):
                initialCodexProxyURL = config.proxyURL ?? ""
            case .gemini(let config):
                initialGeminiProxyURL = config.proxyURL ?? ""
            }
        }

        _cookies = State(initialValue: initialCookies)
        _secToken = State(initialValue: initialSecToken)
        _region = State(initialValue: initialRegion)
        _zenMuxApiKey = State(initialValue: initialZenMuxApiKey)
        _mimoServiceToken = State(initialValue: initialMimoServiceToken)
        _mimoUserId = State(initialValue: initialMimoUserId)
        _codexProxyURL = State(initialValue: initialCodexProxyURL)
        _geminiProxyURL = State(initialValue: initialGeminiProxyURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(module == nil ? "添加监控模块" : "编辑监控模块")
                .font(.title3)
                .fontWeight(.semibold)

            HStack {
                Text("供应商")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("供应商", selection: Binding(
                    get: { provider },
                    set: { newValue in
                        provider = newValue
                        displayKeys = Set(Self.defaultDisplayKeys(for: newValue))
                        resetTimeKeys = []
                    }
                )) {
                    ForEach(PlatformType.allCases) { platform in
                        Text(providerTitle(for: platform))
                            .tag(platform)
                            .disabled(!canSelectProvider(platform))
                    }
                }
                .pickerStyle(.menu)
                .disabled(module != nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("模块别名")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField(defaultAlias, text: $alias)
                    .textFieldStyle(.roundedBorder)
            }

            providerForm

            moduleOptions

            if !quotaOptions.isEmpty {
                quotaSelection
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    onSave(makeModule())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private var providerForm: some View {
        switch provider {
        case .bailian:
            VStack(alignment: .leading, spacing: 8) {
                Text("Cookie")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextEditor(text: $cookies)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 70)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                HStack {
                    SecureField("sec_token", text: $secToken)
                        .textFieldStyle(.roundedBorder)
                    Picker("区域", selection: $region) {
                        Text("北京").tag("cn-beijing")
                        Text("上海").tag("cn-shanghai")
                        Text("深圳").tag("cn-shenzhen")
                        Text("杭州").tag("cn-hangzhou")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                }
            }
        case .zenmux:
            VStack(alignment: .leading, spacing: 6) {
                Text("Management API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("请输入 Management API Key", text: $zenMuxApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("仅支持 Management API Key，标准 API Key 无效")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .mimo:
            VStack(alignment: .leading, spacing: 8) {
                SecureField("api-platform_serviceToken", text: $mimoServiceToken)
                    .textFieldStyle(.roundedBorder)
                TextField("userId", text: $mimoUserId)
                    .textFieldStyle(.roundedBorder)
            }
        case .codex:
            VStack(alignment: .leading, spacing: 6) {
                Text("Codex 会自动读取本机 OAuth，代理可选")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:7890", text: $codexProxyURL)
                    .textFieldStyle(.roundedBorder)
            }
        case .gemini:
            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini 会自动读取本机 Gemini CLI OAuth，代理可选")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:7890", text: $geminiProxyURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var moduleOptions: some View {
        HStack(spacing: 14) {
            Toggle("监控", isOn: $isMonitoringEnabled)
            Toggle("bar栏展示", isOn: $showInMenuBar)
            Toggle("详情页展示", isOn: $showInDetail)
            Toggle("通知", isOn: $isNotificationEnabled)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private var quotaSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("展示项")
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 14) {
                ForEach(quotaOptions, id: \.key) { option in
                    Toggle(option.label, isOn: Binding(
                        get: { displayKeys.contains(option.key) },
                        set: { enabled in
                            if enabled {
                                displayKeys.insert(option.key)
                            } else {
                                displayKeys.remove(option.key)
                                resetTimeKeys.remove(option.key)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            HStack(spacing: 14) {
                ForEach(quotaOptions, id: \.key) { option in
                    Toggle("\(option.label)重置", isOn: Binding(
                        get: { resetTimeKeys.contains(option.key) },
                        set: { enabled in
                            if enabled {
                                resetTimeKeys.insert(option.key)
                                displayKeys.insert(option.key)
                            } else {
                                resetTimeKeys.remove(option.key)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
        .font(.caption)
    }

    private var quotaOptions: [(key: String, label: String)] {
        switch provider {
        case .bailian:
            return [("billMonth", "账单月"), ("5hour", "5小时"), ("week", "周")]
        case .zenmux:
            return [("5hour", "5小时"), ("7day", "7天")]
        case .gemini:
            return [("gemini_pro", "Pro"), ("gemini_flash", "Flash"), ("gemini_flash_lite", "Flash Lite")]
        case .mimo, .codex:
            return []
        }
    }

    private var canSave: Bool {
        guard canSelectProvider(provider) else {
            return false
        }

        switch provider {
        case .bailian:
            return !cookies.isEmpty && !secToken.isEmpty
        case .zenmux:
            return !zenMuxApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .mimo:
            return !mimoServiceToken.isEmpty && !mimoUserId.isEmpty
        case .codex, .gemini:
            return true
        }
    }

    private var defaultAlias: String {
        module?.aliasDisplayName ?? ""
    }

    private func providerTitle(for platform: PlatformType) -> String {
        if canSelectProvider(platform) {
            return platform.rawValue
        }
        return "\(platform.rawValue)（已添加）"
    }

    private func canSelectProvider(_ platform: PlatformType) -> Bool {
        if platform == .zenmux {
            return true
        }
        return !existingModules.contains { existingModule in
            existingModule.id != module?.id && existingModule.platform == platform
        }
    }

    private func makeModule() -> MonitorModule {
        let config: MonitorModuleConfig
        switch provider {
        case .bailian:
            config = .bailian(BailianConfig(cookies: cookies, secToken: secToken, region: region))
        case .zenmux:
            config = ModuleEditorConfigFactory.zenMuxConfig(
                alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: zenMuxApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                displayKeys: Array(displayKeys),
                resetTimeKeys: Array(resetTimeKeys)
            )
        case .mimo:
            config = .mimo(MimoConfig(serviceToken: mimoServiceToken, userId: mimoUserId))
        case .codex:
            let trimmed = codexProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            config = .codex(CodexConfig(proxyURL: trimmed.isEmpty ? nil : trimmed))
        case .gemini:
            let trimmed = geminiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            config = .gemini(GeminiConfig(proxyURL: trimmed.isEmpty ? nil : trimmed))
        }

        return MonitorModule(
            id: module?.id ?? UUID().uuidString,
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            config: config,
            isMonitoringEnabled: isMonitoringEnabled,
            showInMenuBar: showInMenuBar,
            showInDetail: showInDetail,
            isNotificationEnabled: isNotificationEnabled,
            displayKeys: Array(displayKeys),
            resetTimeKeys: Array(resetTimeKeys),
            sortOrder: module?.sortOrder ?? 0
        )
    }

    static func defaultDisplayKeys(for provider: PlatformType) -> [String] {
        switch provider {
        case .bailian:
            return ["billMonth", "5hour", "week"]
        case .zenmux:
            return ZenMuxAccountConfig.defaultDisplayKeys
        case .gemini:
            return ["gemini_pro", "gemini_flash", "gemini_flash_lite"]
        case .mimo, .codex:
            return []
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
                    case .gemini:
                        geminiHelpSteps
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
        case .gemini: return "获取 Gemini 用量凭据帮助"
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

    private var geminiHelpSteps: some View {
        Group {
            HelpStepView(number: 1, title: "安装 Gemini CLI", description: "安装并打开 Google Gemini CLI", icon: "terminal")
            HelpStepView(number: 2, title: "使用 Google 登录", description: "通过 Gemini CLI 登录 Google 账号，使 Keychain 或 ~/.gemini/oauth_creds.json 中生成 OAuth 凭据", icon: "person.circle")
            HelpStepView(number: 3, title: "自动检测", description: "CodeBar 会自动读取 gemini-cli-oauth 或 ~/.gemini/oauth_creds.json，不需要手动填写凭据", icon: "key")
            HelpStepView(number: 4, title: "代理可选", description: "无法直连 Google Code Assist 接口时，可填写 http 或 socks5 代理地址", icon: "network")
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
