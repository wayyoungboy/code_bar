import SwiftUI

/// 独立的设置窗口
struct SettingsWindowView: View {
    @ObservedObject var tracker: UsageTracker
    @State private var showBailianHelp = false
    @State private var showZenMuxHelp = false

    // 百炼配置
    @State private var cookies = ""
    @State private var secToken = ""
    @State private var region = "cn-beijing"

    // ZenMux 配置
    @State private var zenMuxApiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 说明
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("配置平台凭据，选择要展示的用量类型")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)

                // 百炼配置
                VStack(alignment: .leading, spacing: 12) {
                    // 标题和状态
                    HStack {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(.blue)
                        Text("阿里云百炼")
                            .font(.headline)
                        Spacer()
                        if tracker.providers[.bailian]?.isConfigured == true {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已配置")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.gray)
                            Text("未配置")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    // 凭据配置
                    bailianConfigForm

                    // 显示类型选择
                    if tracker.providers[.bailian]?.isConfigured == true {
                        Divider()
                        displayTypeSelection(for: .bailian)
                    }
                }
                .padding(16)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)

                // ZenMux 配置
                VStack(alignment: .leading, spacing: 12) {
                    // 标题和状态
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.purple)
                        Text("ZenMux")
                            .font(.headline)
                        Spacer()
                        if tracker.providers[.zenmux]?.isConfigured == true {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已配置")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.gray)
                            Text("未配置")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    // 凭据配置
                    zenMuxConfigForm

                    // 显示类型选择
                    if tracker.providers[.zenmux]?.isConfigured == true {
                        Divider()
                        displayTypeSelection(for: .zenmux)
                    }
                }
                .padding(16)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(10)

                // 提示
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
        .frame(width: Constants.settingsWindowWidth, height: Constants.settingsWindowHeight)
        .sheet(isPresented: $showBailianHelp) {
            HelpWindowView(platform: .bailian)
        }
        .sheet(isPresented: $showZenMuxHelp) {
            HelpWindowView(platform: .zenmux)
        }
        .onAppear {
            // 加载已保存的配置
            if let config = tracker.loadBailianConfig() {
                cookies = config.cookies
                secToken = config.secToken
                region = config.region
            }
            if let config = tracker.loadZenMuxConfig() {
                zenMuxApiKey = config.apiKey
            }
        }
    }

    // MARK: - 显示类型选择
    @ViewBuilder
    private func displayTypeSelection(for platform: PlatformType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("展示内容")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 12) {
                ForEach(UsageDisplayType.allCases) { type in
                    Toggle(isOn: Binding(
                        get: { tracker.displayTypes[platform]?.contains(type) ?? false },
                        set: { _ in
                            tracker.toggleDisplayType(type, for: platform)
                        }
                    )) {
                        Text(type.rawValue)
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    // MARK: - 百炼配置表单
    private var bailianConfigForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cookie 输入
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

            // Sec Token 和区域
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sec Token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    SecureField("请输入 sec_token", text: $secToken)
                        .textFieldStyle(.roundedBorder)
                }

                // 区域选择
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

            // 操作按钮
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

    // MARK: - ZenMux 配置表单
    private var zenMuxConfigForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // API Key 输入
            VStack(alignment: .leading, spacing: 4) {
                Text("Management API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("请输入 Management API Key", text: $zenMuxApiKey)
                    .textFieldStyle(.roundedBorder)
            }

            Text("⚠️ 仅支持 Management API Key，标准 API Key 无效")
                .font(.caption)
                .foregroundColor(.orange)

            // 操作按钮
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
}

/// 帮助窗口视图
struct HelpWindowView: View {
    @Environment(\.dismiss) var dismiss
    let platform: PlatformType

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(platform == .bailian ? "获取百炼凭据帮助" : "获取 ZenMux API Key 帮助")
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if platform == .bailian {
                        bailianHelpSteps
                    } else {
                        zenMuxHelpSteps
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
            HelpStepView(number: 1, title: "登录 ZenMux", description: "访问 https://zenmux.ai 并使用您的账号登录", icon: "person.circle")
            HelpStepView(number: 2, title: "进入 Settings", description: "点击右上角的 Settings 进入设置页面", icon: "gear")
            HelpStepView(number: 3, title: "找到 API Keys", description: "在设置页面中找到 API Keys 部分", icon: "key")
            HelpStepView(number: 4, title: "复制 Management Key", description: "复制 Management API Key（不是标准 API Key）", icon: "doc.on.clipboard")
            HelpStepView(number: 5, title: "重要提示", description: "⚠️ 必须使用 Management API Key，标准 API Key 不支持此功能", icon: "exclamationmark.triangle")
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