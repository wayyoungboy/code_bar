import SwiftUI

struct PlatformLogoView: View {
    let platform: PlatformType
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let assetName = platform.logoAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(platform.usesOriginalLogoColor ? .original : .template)
                    .scaledToFit()
            } else {
                Image(systemName: platform.icon)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundColor(platform.usesOriginalLogoColor ? nil : Color(hex: platform.brandColor))
    }
}

struct MenuBarView: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var updateChecker: UpdateChecker
    @State private var hasLoadedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text("CodeBar 用量")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)

            // 用量显示 - 显示所有详情页模块
            if tracker.hasAnyModule {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(tracker.detailModules) { module in
                        moduleUsageCard(
                            module: module,
                            usage: tracker.moduleUsages[module.id],
                            error: tracker.moduleErrors[module.id]
                        )
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
            if !tracker.moduleErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tracker.detailModules) { module in
                        if let message = tracker.moduleErrors[module.id] {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("\(module.displayName): \(message)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }

            // 更新提示
            if updateChecker.isEnabled, updateChecker.hasUpdate, let version = updateChecker.latestVersion {
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
                PlatformLogoView(platform: platform)
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
                    item: item,
                    displayMode: .used,
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

            if !usage.accountBreakdowns.isEmpty {
                Divider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(usage.accountBreakdowns) { account in
                            accountUsageView(account)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("账号明细")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            // 低用量警告
            if visibleItems.contains(where: { UsagePercentDisplayMode.used.isNearLimit($0) }) {
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
        .background(Color(hex: platform.brandColor).opacity(0.12))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func accountUsageView(_ account: AccountUsageData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.alias)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(account.planType)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if let errorMessage = account.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            } else if account.items.isEmpty {
                Text("未选择显示项")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                ForEach(account.items, id: \.key) { item in
                    usageRow(
                        item: item,
                        displayMode: .used,
                        resetDate: account.resetTimeKeys.contains(item.key) ? item.resetDate : nil
                    )
                }

                if !account.extraInfo.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(account.extraInfo.enumerated()), id: \.offset) { _, info in
                            HStack {
                                Text(info.label)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(info.value)
                                    .font(.system(size: 9))
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func usageRow(
        item: UsageItem,
        displayMode: UsagePercentDisplayMode,
        resetDate: Date? = nil,
        compact: Bool = false
    ) -> some View {
        let displayValue = displayMode.value(for: item)
        let displayPercent = displayMode.percent(for: item)

        VStack(alignment: .leading, spacing: 4) {
            if !compact {
                HStack {
                    Text(item.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(displayMode.title) \(formatNumber(displayValue)) / \(formatNumber(item.total)) \(item.unit)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor(for: displayPercent, mode: displayMode))
                        .frame(width: geometry.size.width * CGFloat(displayPercent / 100))
                }
            }
            .frame(height: 6)

            if let resetDate = resetDate, !compact {
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
            Text("请打开「设置」添加监控模块")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - 辅助方法

    @ViewBuilder
    private func moduleUsageCard(module: MonitorModule, usage: PlatformUsageData?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PlatformLogoView(platform: module.platform)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.platform.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let alias = module.aliasDisplayName {
                        Text(alias)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let usage {
                    Text(usage.planType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    tracker.updateModuleDisplayState(id: module.id) { module in
                        module.isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: module.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(module.isCollapsed ? "展开" : "折叠")
            }

            if !module.isMonitoringEnabled {
                Text("监控已暂停")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let usage {
                let visibleItems = DetailUsagePresentation.items(from: usage, module: module)
                ForEach(visibleItems, id: \.key) { item in
                    usageRow(
                        item: item,
                        displayMode: module.percentDisplayMode,
                        resetDate: DetailUsagePresentation.resetDate(for: item, module: module),
                        compact: module.isCollapsed
                    )
                }

                if !module.isCollapsed, !usage.extraInfo.isEmpty {
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

                if !module.isCollapsed, visibleItems.contains(where: { module.percentDisplayMode.isNearLimit($0) }) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("用量即将耗尽！")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
            } else {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(error ?? "等待刷新")
                        .font(.caption)
                        .foregroundColor(error == nil ? .secondary : .orange)
                }
            }

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(Color(hex: module.platform.brandColor).opacity(0.12))
        .cornerRadius(8)
    }

    private func progressColor(for percent: Double, mode: UsagePercentDisplayMode) -> Color {
        switch mode {
        case .used:
            if percent > 90 {
                return .red
            } else if percent > 70 {
                return .orange
            }
            return .green
        case .remaining:
            if percent < 10 {
                return .red
            } else if percent < 30 {
                return .orange
            }
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

#if !CODEBAR_BEHAVIOR_TESTS
#Preview {
    MenuBarView(tracker: UsageTracker.shared, updateChecker: UpdateChecker.shared)
}
#endif
