import Foundation

@main
private struct ModuleBehaviorTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }

    static func main() {
        let fiveHourReset = Date(timeIntervalSince1970: 1_800_000_000)
        let sevenDayReset = Date(timeIntervalSince1970: 1_800_100_000)
        let fiveHour = UsageItem(key: "5hour", label: "5小时", used: 1, total: 10, unit: "flows", resetDate: fiveHourReset)
        let sevenDay = UsageItem(key: "7day", label: "7天", used: 2, total: 20, unit: "flows", resetDate: sevenDayReset)
        let usage = PlatformUsageData(platformName: "ZenMux", planType: "Pro", items: [fiveHour, sevenDay])
        let module = MonitorModule(
            alias: "detail",
            config: .zenmux(ZenMuxAccountConfig(alias: "detail", apiKey: "abcdefghijklmnopqrstuvwxyz")),
            displayKeys: ["5hour"],
            resetTimeKeys: [],
            sortOrder: 0
        )

        let detailItems = DetailUsagePresentation.items(from: usage, module: module)
        expect(detailItems.map(\.key) == ["5hour", "7day"], "Detail page should ignore displayKeys and show all quota items")
        expect(DetailUsagePresentation.resetDate(for: fiveHour, module: module) == fiveHourReset, "Detail page should show 5 hour reset time")
        expect(DetailUsagePresentation.resetDate(for: sevenDay, module: module) == sevenDayReset, "Detail page should show 7 day reset time")

        let storedUsage = ModuleUsageStorage.usageForModuleCache(from: usage, module: module)
        expect(storedUsage.items.map(\.key) == ["5hour", "7day"], "Module usage cache should preserve all quota items for the detail page")

        let providerAccount = ModuleProviderConfiguration.zenMuxAccount(for: module)
        expect(providerAccount.displayKeys == ["5hour", "7day"], "ZenMux provider should receive all quota keys so the detail page can show all items")

        let legacyModule = MonitorModule(
            alias: "",
            config: .zenmux(ZenMuxAccountConfig(
                alias: "legacy alias",
                apiKey: "abcdefghijklmnopqrstuvwxyz",
                displayKeys: ["7day"],
                resetTimeKeys: ["7day"]
            )),
            displayKeys: [],
            resetTimeKeys: [],
            sortOrder: 0
        )

        expect(legacyModule.editorAlias == "legacy alias", "Editor should load alias from existing ZenMux config when module alias is empty")
        expect(legacyModule.editorDisplayKeys == ["7day"], "Editor should load display keys from existing ZenMux config")
        expect(legacyModule.editorResetTimeKeys == ["7day"], "Editor should load reset time keys from existing ZenMux config")

        let savedConfig = ModuleEditorConfigFactory.zenMuxConfig(
            alias: "saved alias",
            apiKey: "abcdefghijklmnopqrstuvwxyz",
            displayKeys: ["5hour", "7day"],
            resetTimeKeys: ["5hour"]
        )

        if case .zenmux(let account) = savedConfig {
            expect(account.alias == "saved alias", "Saved ZenMux config should preserve alias")
            expect(account.displayKeys == ["5hour", "7day"], "Saved ZenMux config should preserve display keys")
            expect(account.resetTimeKeys == ["5hour"], "Saved ZenMux config should preserve reset time keys")
        } else {
            fatalError("Saved config should be ZenMux")
        }

        print("ModuleBehaviorTests passed")
    }
}
