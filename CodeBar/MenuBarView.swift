import SwiftUI

struct MenuBarView: View {
    @ObservedObject var tracker: UsageTracker
    @State private var showingSettings = false
    @State private var hasLoadedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题和设置按钮
            HStack {
                Text("Code Plan 用量")
                    .font(.headline)
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // 用量显示
            if let usage = tracker.currentUsage {
                // 首次加载完成后，不再显示 loading，直接显示内容
                usageView(for: usage)
            } else if !tracker.isConfigured {
                emptyStateView
            } else if !hasLoadedOnce {
                // 首次加载时显示 loading
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                errorView
            }

            // 错误信息
            if let errorMessage = tracker.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Divider()

            // 底部操作
            HStack {
                Text("最后更新：\(tracker.lastRefreshDate, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    Task { @MainActor in
                        await tracker.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新")
                }
                .disabled(tracker.isLoading)
            }
        }
        .padding(20)
        .frame(width: 320)
        .sheet(isPresented: $showingSettings) {
            SettingsView(tracker: tracker)
        }
        .onAppear {
            hasLoadedOnce = true
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private func usageView(for usage: PlatformUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 平台名称
            HStack {
                Image(systemName: PlatformType.bailian.icon)
                    .foregroundColor(.blue)
                Text(usage.platformName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            // 账单月用量 - 进度条
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("账单月")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(formatNumber(usage.used)) / \(formatNumber(usage.total)) \(usage.unit)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                progressView(used: usage.used, total: usage.total, percent: usage.usagePercent)
            }

            // 5 小时用量 - 进度条
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("5 小时")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(formatNumber(usage.used5Hour)) / \(formatNumber(usage.total5Hour)) \(usage.unit)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                progressView(used: usage.used5Hour, total: usage.total5Hour, percent: usage.used5HourPercent)
            }

            // 周用量 - 进度条
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("周")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(formatNumber(usage.usedWeek)) / \(formatNumber(usage.totalWeek)) \(usage.unit)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                progressView(used: usage.usedWeek, total: usage.totalWeek, percent: usage.usedWeekPercent)
            }

            Divider()

            // 详细信息
            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "计划类型", value: usage.planType)
                InfoRow(label: "账单月重置", value: Self.formatDate(usage.resetDate))
                InfoRow(label: "5 小时重置", value: Self.formatTime(usage.resetDate5Hour))
                InfoRow(label: "周重置", value: Self.formatDate(usage.resetDateWeek))
            }

            // 低用量警告
            if tracker.isLowUsage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("用量即将耗尽！")
                        .foregroundColor(.yellow)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(8)
            }
        }
    }

    // 进度条组件
    private func progressView(used: Int, total: Int, percent: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                    .cornerRadius(4)

                Rectangle()
                    .fill(progressColor(for: percent))
                    .frame(width: geometry.size.width * CGFloat(percent / 100), height: 8)
                    .cornerRadius(4)
            }
        }
        .frame(height: 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("未配置凭据")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("请在设置中配置百炼 Cookie")
                .font(.caption)
                .foregroundColor(.gray)
            Button("前往设置") {
                showingSettings = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            Text("获取用量失败")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("请检查凭据配置或网络连接")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - 辅助方法

private func progressColor(for percent: Double) -> Color {
    if percent > 90 {
        return .red
    } else if percent > 70 {
        return .orange
    } else {
        return .green
    }
}

private func formatNumber(_ number: Int) -> String {
    if number >= 1_000_000 {
        return String(format: "%.1fM", Double(number) / 1_000_000)
    } else if number >= 1_000 {
        return String(format: "%.1fK", Double(number) / 1_000)
    }
    return "\(number)"
}

private static func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private static func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
        .font(.body)
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var tracker: UsageTracker
    @State private var cookies = ""
    @State private var secToken = ""
    @State private var region = "cn-beijing"
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text("百炼凭据配置")
                    .font(.headline)
                Spacer()
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 表单
                    VStack(alignment: .leading, spacing: 12) {
                        // Cookie 输入
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cookie")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextEditor(text: $cookies)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 80)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                        }

                        // Sec Token 输入
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
                            .pickerStyle(.segmented)
                        }
                    }

                    // 已保存提示
                    if !cookies.isEmpty || !secToken.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已加载已保存的配置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // 显示类型选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("显示类型（可多选）")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(UsageTracker.UsageDisplayType.allCases) { type in
                                Toggle(isOn: Binding(
                                    get: { tracker.displayTypes.contains(type) },
                                    set: { isSelected in
                                        if isSelected {
                                            tracker.displayTypes.append(type)
                                        } else {
                                            tracker.displayTypes.removeAll { $0 == type }
                                        }
                                    }
                                )) {
                                    Text(type.rawValue)
                                        .font(.caption)
                                }
                            }
                        }
                        Text("多选时每 5 秒自动滚动显示")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // 说明文字
                    VStack(alignment: .leading, spacing: 4) {
                        Text("如何获取：")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("1. 访问百炼控制台并登录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("2. 打开浏览器开发者工具 (F12)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("3. 进入 Network 标签，访问 Coding Plan 页面")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("4. 复制 api.json 请求中的 Cookie 和 sec_token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.vertical, 8)
            }

            // 按钮
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    tracker.saveBailianConfig(cookies: cookies, secToken: secToken, region: region)
                    dismiss()
                }
                .disabled(cookies.isEmpty || secToken.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 600)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .onAppear {
            // 加载已保存的配置
            if let config = tracker.loadBailianConfig() {
                cookies = config.cookies
                secToken = config.secToken
                region = config.region
            }
        }
    }
}

// MARK: - 帮助视图

struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("如何获取百炼凭据")
                .font(.headline)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    StepView(number: 1, title: "登录百炼控制台", description: "访问 https://bailian.console.aliyun.com/ 并登录")

                    StepView(number: 2, title: "打开开发者工具", description: "按 F12 或右键点击页面选择「检查」")

                    StepView(number: 3, title: "进入 Network 标签", description: "在开发者工具中点击 Network 标签")

                    StepView(number: 4, title: "访问 Coding Plan 页面", description: "在百炼控制台进入 Coding Plan 页面")

                    StepView(number: 5, title: "找到 api.json 请求", description: "在 Network 列表中找到 api.json 请求")

                    StepView(number: 6, title: "复制凭据", description: "在请求头中复制 Cookie 和 sec_token")
                }
                .padding(.vertical, 8)
            }

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 350)
    }
}

struct StepView: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    MenuBarView(tracker: UsageTracker())
}
