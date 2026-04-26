import Foundation
import AppKit

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String?
    @Published var updateURL: URL?
    @Published var hasUpdate = false

    private let repoAPI = "https://api.github.com/repos/wayyoungboy/code_bar/releases/latest"
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForUpdate()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func checkForUpdate() async {
        guard let url = URL(string: repoAPI) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remote = tagName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "v", with: "")
            latestVersion = tagName
            updateURL = URL(string: htmlURL)
            hasUpdate = isNewer(remote: remote, local: currentVersion)
        } catch {
            AppLogger.logError(error)
        }
    }

    func openUpdatePage() {
        guard let url = updateURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
