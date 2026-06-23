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

        expect(UsagePercentDisplayMode.used.value(for: fiveHour) == 1, "Used mode should show the consumed value")
        expect(Int(UsagePercentDisplayMode.used.percent(for: fiveHour).rounded()) == 10, "Used mode should show consumed percent")
        expect(UsagePercentDisplayMode.remaining.value(for: fiveHour) == 9, "Remaining mode should show the remaining value")
        expect(Int(UsagePercentDisplayMode.remaining.percent(for: fiveHour).rounded()) == 90, "Remaining mode should show remaining percent")

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

        let editSession = ModuleEditorSession.editing(legacyModule)
        expect(editSession.id == "edit-\(legacyModule.id)", "Editing an existing module should use a module-specific sheet identity")
        expect(editSession.module?.id == legacyModule.id, "Editing session should carry the existing module into the editor")
        expect(editSession.module?.editorAlias == "legacy alias", "Editing session should preserve previously saved module configuration")

        let addSession = ModuleEditorSession.adding()
        expect(addSession.id == "add", "Adding a module should use a separate sheet identity from editing")
        expect(addSession.module?.id == nil, "Adding session should not carry an existing module")

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

        let geminiConfig = GeminiConfig(proxyURL: " socks5://127.0.0.1:7890 ")
        let geminiModule = MonitorModule(
            alias: "gemini",
            config: .gemini(geminiConfig),
            displayKeys: [],
            resetTimeKeys: [],
            sortOrder: 0
        )

        expect(geminiModule.platform == .gemini, "Gemini module should report Gemini platform")
        expect(geminiModule.isValid, "Gemini module should be valid without storing OAuth token")
        expect(ModuleEditorView.defaultDisplayKeys(for: .gemini) == ["gemini_pro", "gemini_flash", "gemini_flash_lite"], "Gemini should default to all model quota categories")

        let encodedGemini = try! JSONEncoder().encode(geminiModule.config)
        let decodedGemini = try! JSONDecoder().decode(MonitorModuleConfig.self, from: encodedGemini)
        if case .gemini(let decodedConfig) = decodedGemini {
            expect(decodedConfig.proxyURL == " socks5://127.0.0.1:7890 ", "Gemini config should preserve proxy URL through Codable")
        } else {
            fatalError("Decoded config should be Gemini")
        }

        let legacyModuleJSON = """
        {
          "id": "legacy-gemini",
          "alias": "legacy",
          "config": {
            "type": "Gemini",
            "gemini": {}
          },
          "isMonitoringEnabled": true,
          "showInMenuBar": true,
          "showInDetail": true,
          "isNotificationEnabled": true,
          "displayKeys": [],
          "resetTimeKeys": [],
          "sortOrder": 0
        }
        """
        let decodedLegacyModule = try! JSONDecoder().decode(MonitorModule.self, from: Data(legacyModuleJSON.utf8))
        expect(decodedLegacyModule.isCollapsed == false, "Legacy module JSON should default to expanded cards")
        expect(decodedLegacyModule.percentDisplayMode == .used, "Legacy module JSON should default to used percent display")

        let exhaustedCodexJSON = """
        {
          "plan_type": "pro",
          "rate_limit_reached_type": "primary",
          "rate_limit": {
            "primary_window": {
              "remaining_percent": "0",
              "limit_window_seconds": "18000",
              "reset_at": "2027-01-15T00:00:00Z"
            },
            "secondary_window": {
              "used_percent": "100%",
              "limit_window_seconds": 604800,
              "reset_after_seconds": "3600"
            }
          },
          "additional_rate_limits": { "unexpected": true },
          "credits": {
            "has_credits": "false",
            "unlimited": false,
            "overage_limit_reached": "true",
            "balance": 0,
            "approx_local_messages": "unexpected"
          },
          "spend_control": {
            "reached": "true",
            "individual_limit": "10.5"
          },
          "rate_limit_reset_credits": {
            "available_count": "0"
          }
        }
        """
        let exhaustedCodexItems = try! CodexProvider.testUsageItems(from: exhaustedCodexJSON)
        expect(exhaustedCodexItems.map(\.key) == ["5hour", "7day"], "Codex exhausted response should still expose primary quota windows")
        expect(exhaustedCodexItems.allSatisfy { $0.used == 100 }, "Codex exhausted response should show fully used quota windows")

        print("ModuleBehaviorTests passed")
    }
}
