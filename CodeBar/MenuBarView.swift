import SwiftUI

struct MenuBarView: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var updateChecker: UpdateChecker
    @State private var hasLoadedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text("Code Plan 用量")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)

            // 用量显示 - 显示所有已配置的平台
            if tracker.hasAnyConfig {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(PlatformType.allCases) { platform in
                        if let provider = tracker.providers[platform], provider.isConfigured,
                           let usage = tracker.platforms[platform] {
                            platformUsageCard(platform: platform, usage: usage, error: tracker.errorMessages[platform])
                        }
                    }
                }
            } else if !hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                emptyStateView
            }

            // 错误信息汇总
            if tracker.hasErrors {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tracker.errorMessages.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { platform in
                        if let message = tracker.errorMessages[platform] {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("\(platform.shortName): \(message)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }

            // 更新提示
            if updateChecker.hasUpdate, let version = updateChecker.latestVersion {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.orange)
                    Text("新版本 \(version) 可用")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("前往更新") {
                        updateChecker.openUpdatePage()
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            Divider()

            // 底部操作
            HStack {
                Text("最后更新：\(tracker.lastRefreshDate, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }) {
                    Image(systemName: "gearshape.fill")
                    Text("设置")
                }
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

            Divider()

            // 退出按钮
            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("退出 CodeBar")
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(20)
        .frame(width: Constants.popoverWidth)
        .onAppear {
            hasLoadedOnce = true
        }
    }

    // MARK: - 辅助方法

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 平台用量卡片

    @ViewBuilder
    private func platformUsageCard(platform: PlatformType, usage: PlatformUsageData, error: String?) -> some View {
        let activeKeys = tracker.displayKeys(for: platform)
        let visibleItems = usage.items.filter { activeKeys.contains($0.key) }

        VStack(alignment: .leading, spacing: 10) {
            // 平台名称
            HStack {
                Image(systemName: platform.icon)
                    .foregroundColor(platform == .bailian ? .blue : .purple)
                Text(usage.platformName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(usage.planType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 根据配置显示对应的用量
            ForEach(visibleItems, id: \.key) { item in
                usageRow(
                    label: item.label,
                    used: item.used,
                    total: item.total,
                    unit: item.unit,
                    percent: item.percent,
                    resetDate: item.resetDate
                )
            }

            // 额外信息
            if !usage.extraInfo.isEmpty {
                Divider()
                ForEach(Array(usage.extraInfo.enumerated()), id: \.offset) { _, info in
                    HStack {
                        Text(info.label)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(info.value)
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                    }
                }
            }

            // 低用量警告
            if visibleItems.contains(where: { $0.percent > 80 }) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("用量即将耗尽！")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                .padding(.top, 4)
            }

            // 单平台错误（如果有）
            if let errorMsg = error {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(platform == .bailian ? NSColor.blue : NSColor.purple).opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func usageRow(label: String, used: Int, total: Int, unit: String, percent: Double, resetDate: Date? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatNumber(used)) / \(formatNumber(total)) \(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor(for: percent))
                        .frame(width: geometry.size.width * CGFloat(percent / 100))
                }
            }
            .frame(height: 6)

            if let resetDate = resetDate {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text("\(resetDate, style: .relative)后重置")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("未配置凭据")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("请打开「设置...」配置平台凭据")
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
}

#Preview {
    MenuBarView(tracker: UsageTracker.shared, updateChecker: UpdateChecker.shared)
}