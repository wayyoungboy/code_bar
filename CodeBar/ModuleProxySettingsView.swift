import SwiftUI

struct ModuleProxySettingsView: View {
    @Binding var proxyURL: String
    let platform: PlatformType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("代理（可选）")
                .font(.subheadline)
                .fontWeight(.medium)
            TextField("http://127.0.0.1:7890 或 socks5://127.0.0.1:7890", text: $proxyURL)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("模块代理地址")
            if let message = ModuleProxyConfiguration.validationMessage(for: proxyURL) {
                Text(message).font(.caption).foregroundColor(.orange)
            } else {
                Text(helpText).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var helpText: String {
        switch platform {
        case .grok:
            return "订阅查询和 OAuth 刷新均使用当前模块的代理；留空沿用系统网络设置。"
        case .antigravity:
            return "配置后通过 agy CLI 查询，需已安装并登录 agy；本机通信始终直连。留空优先读取桌面端。"
        default:
            return "仅作用于当前模块；留空沿用 macOS 系统网络设置。"
        }
    }
}
