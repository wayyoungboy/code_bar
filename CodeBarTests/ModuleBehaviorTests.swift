import AppKit
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
        expect(UsageStatusFormatting.compactPercentText(for: fiveHour, displayMode: .used) == "10%", "Used compact text should omit text prefixes")
        expect(UsageStatusFormatting.compactPercentText(for: fiveHour, displayMode: .remaining) == "90%", "Remaining compact text should omit text prefixes")

        var statusUsageRotation = StatusBarUsageRotation()
        statusUsageRotation.registerRefresh()
        expect(statusUsageRotation.index == 0, "First refresh should retain the first quota")
        statusUsageRotation.registerRefresh()
        expect(statusUsageRotation.index == 1, "Second refresh should select the second quota")
        statusUsageRotation.registerRefresh()
        expect(statusUsageRotation.index == 0, "Third refresh should cycle back to the first quota")

        let firstStatusUsage = StatusBarUsagePresentation.make(
            lines: ["5h 45%", "7d 11%"],
            rotationIndex: 0,
            fallback: "Codex"
        )
        expect(firstStatusUsage.title == "5h 45%", "First cycle should show one usage line")
        expect(firstStatusUsage.tooltip == "5h 45% / 7d 11%", "Status tooltip should retain both quotas")
        let secondStatusUsage = StatusBarUsagePresentation.make(
            lines: ["5h 45%", "7d 11%"],
            rotationIndex: 1,
            fallback: "Codex"
        )
        expect(secondStatusUsage.title == "7d 11%", "Second cycle should show the next usage line")
        expect(
            StatusBarUsagePresentation.make(lines: ["5h 45%"], rotationIndex: 1, fallback: "Codex").title == "5h 45%",
            "Single quota should remain visible across refreshes"
        )
        expect(
            StatusBarUsagePresentation.make(lines: [], rotationIndex: 0, fallback: "Codex").title == "Codex",
            "Empty quotas should use the platform fallback"
        )

        let oversizedIcon = NSImage(size: NSSize(width: 196, height: 196))
        let statusIcon = StatusBarIconRenderer.render(
            oversizedIcon,
            pointSize: Constants.statusBarIconSize,
            scale: 2,
            isTemplate: false
        )
        expect(statusIcon.size == NSSize(width: Constants.statusBarIconSize, height: Constants.statusBarIconSize), "Status bar renderer should expose a compact point size")
        let renderedRep = statusIcon.representations.first as? NSBitmapImageRep
        expect(renderedRep?.pixelsWide == Int(Constants.statusBarIconSize * 2), "Status bar renderer should rasterize oversized icons to the requested pixel width")
        expect(renderedRep?.pixelsHigh == Int(Constants.statusBarIconSize * 2), "Status bar renderer should rasterize oversized icons to the requested pixel height")

        let depletedSoon = UsageItem(
            key: "depleted",
            label: "快耗尽",
            used: 95,
            total: 100,
            unit: "%",
            resetDate: fiveHourReset
        )
        let safeQuota = UsageItem(
            key: "safe",
            label: "安全",
            used: 20,
            total: 100,
            unit: "%",
            resetDate: sevenDayReset
        )
        let islandUsage = PlatformUsageData(
            platformName: "Gemini",
            planType: "CLI",
            items: [safeQuota, depletedSoon]
        )
        let islandModule = MonitorModule(
            alias: "work",
            config: .gemini(GeminiConfig()),
            percentDisplayMode: .remaining,
            sortOrder: 0
        )
        let compactStatus = CodeBarIslandCompactStatusBuilder.status(
            modules: [islandModule],
            usages: [islandModule.id: islandUsage],
            errors: [:]
        )
        expect(compactStatus.title == "Gemini", "Island compact status should use the module platform short name")
        expect(compactStatus.detail == "5%", "Island compact status should omit percentage text prefixes")
        expect(compactStatus.tone == .warning, "Island compact status should warn for near-limit quota")

        let errorStatus = CodeBarIslandCompactStatusBuilder.status(
            modules: [islandModule],
            usages: [islandModule.id: islandUsage],
            errors: [islandModule.id: "network failed"]
        )
        expect(errorStatus.tone == .error, "Island compact status should surface module errors")
        expect(errorStatus.detail == "刷新异常", "Island compact status should use compact error text")
        expect(CodeBarPresentationMode.default == .statusBar, "CodeBar should default to the classic status bar presentation")
        let presentationDefaultsName = "codebar-presentation-mode-\(UUID().uuidString)"
        let presentationDefaults = UserDefaults(suiteName: presentationDefaultsName)!
        defer { presentationDefaults.removePersistentDomain(forName: presentationDefaultsName) }
        expect(CodeBarPresentationMode.current(in: presentationDefaults) == .statusBar, "Missing panel selection should use status bar mode")
        CodeBarPresentationMode.save(.island, in: presentationDefaults)
        expect(CodeBarPresentationMode.current(in: presentationDefaults) == .island, "Saved panel selection should be loaded from UserDefaults")
        presentationDefaults.set("unknown-mode", forKey: Constants.presentationModeKey)
        expect(CodeBarPresentationMode.current(in: presentationDefaults) == .statusBar, "Unknown panel selection should fall back to status bar mode")

        let hiddenIslandModule = MonitorModule(
            alias: "hidden",
            config: .gemini(GeminiConfig()),
            isMonitoringEnabled: true,
            showInMenuBar: false,
            showInDetail: true,
            percentDisplayMode: .remaining,
            sortOrder: 0
        )
        let hiddenStatus = CodeBarIslandCompactStatusBuilder.status(
            modules: [hiddenIslandModule],
            usages: [hiddenIslandModule.id: islandUsage],
            errors: [:]
        )
        expect(hiddenStatus.title == "CodeBar", "Island compact status should ignore modules hidden from the menu bar")
        expect(hiddenStatus.detail == "未配置", "Island compact status should show empty status when no menu-bar modules remain")

        let pausedIslandModule = MonitorModule(
            alias: "paused",
            config: .gemini(GeminiConfig()),
            isMonitoringEnabled: false,
            showInMenuBar: true,
            percentDisplayMode: .remaining,
            sortOrder: 0
        )
        let pausedStatus = CodeBarIslandCompactStatusBuilder.status(
            modules: [pausedIslandModule],
            usages: [pausedIslandModule.id: islandUsage],
            errors: [:]
        )
        expect(pausedStatus.title == "CodeBar", "Island compact status should ignore paused modules")

        let closedFrame = CodeBarIslandLayout.frame(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            size: CGSize(width: 200, height: 36)
        )
        expect(Int(closedFrame.origin.x) == 620, "Island closed frame should be horizontally centered")
        expect(Int(closedFrame.origin.y) == 864, "Island closed frame should be pinned to the top edge")
        let notchedGeometry = CodeBarIslandDisplayGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32)
        )
        expect(notchedGeometry.hasNotch, "MacBook auxiliary areas should enable notch wings")
        expect(notchedGeometry.notchGapWidth == 185, "Notch gap should match the auxiliary-area separation")
        expect(notchedGeometry.closedSize == CGSize(width: 345, height: 36), "Collapsed notch should add one 160-point left extension")
        expect(notchedGeometry.closedFrame.minX == 503, "Collapsed panel should begin 160 points before the hardware notch")
        expect(notchedGeometry.closedFrame.maxX == 848, "Collapsed panel should end at the hardware notch right edge")
        expect(notchedGeometry.closedFrame.maxY == 982, "Collapsed panel should remain attached to the screen top")
        expect(
            notchedGeometry.closedLeftExtensionFrame.maxX == notchedGeometry.closedNotchGapFrame.minX,
            "Left content should stop before the hardware notch"
        )
        let notchedOpenedFrame = notchedGeometry.openedFrame(contentHeight: 40)
        expect(notchedOpenedFrame.midX == 755.5, "Expanded panel should stay centered on the hardware notch")
        expect(notchedOpenedFrame.height == 40, "Expanded panel should not add a second notch-height header")

        let externalGeometry = CodeBarIslandDisplayGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        expect(!externalGeometry.hasNotch, "Display without auxiliary areas should use fallback layout")
        expect(externalGeometry.closedSize == CGSize(width: 210, height: 36), "Fallback compact pill should keep its existing size")

        let malformedGeometry = CodeBarIslandDisplayGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 900, height: 32),
            auxiliaryTopRightArea: CGRect(x: 800, y: 950, width: 712, height: 32)
        )
        expect(!malformedGeometry.hasNotch, "Overlapping auxiliary areas should use fallback layout")
        let smallScreenVisibleFrame = CGRect(x: 0, y: 24, width: 1440, height: 280)
        let cappedOpenedFrame = CodeBarIslandLayout.openedFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 304),
            visibleFrame: smallScreenVisibleFrame,
            contentHeight: 1_000
        )
        expect(cappedOpenedFrame.height == smallScreenVisibleFrame.height, "Island opened frame should cap to visible screen height")
        expect(cappedOpenedFrame.minY >= smallScreenVisibleFrame.minY, "Island opened frame should stay inside the visible screen")
        expect(Constants.islandClosedWidth > 0, "Island closed width should be configured")
        expect(Constants.islandOpenedWidth >= Constants.popoverWidth, "Island opened width should fit existing usage content")
        expect(Constants.islandClosedHeight < Constants.islandOpenedMaximumHeight, "Island closed height should be smaller than opened maximum height")
        expect(Constants.statusBarIconSize == 13, "Status bar platform icons should stay compact")

        let tempStoreRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codebar-file-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempStoreRoot) }
        let fileStore = CodeBarFileStore(rootDirectory: tempStoreRoot)
        let storedPayload = Data(#"{"modules":[]}"#.utf8)
        try! fileStore.save(storedPayload, for: Constants.monitorModulesKey)
        let storedPayloadURL = tempStoreRoot.appendingPathComponent("\(Constants.monitorModulesKey).json")
        expect(FileManager.default.fileExists(atPath: storedPayloadURL.path), "CodeBar data should be written under the configured file-store directory")
        expect((try? fileStore.read(for: Constants.monitorModulesKey)) == storedPayload, "CodeBar file store should read back saved data")
        try! fileStore.delete(Constants.monitorModulesKey)
        expect(!FileManager.default.fileExists(atPath: storedPayloadURL.path), "CodeBar file store should delete persisted data files")

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

        let lenientModuleJSON = """
        {
          "id": "lenient-gemini",
          "alias": "lenient",
          "config": {
            "type": "Gemini",
            "gemini": {}
          },
          "isCollapsed": "true",
          "percentDisplayMode": "future-mode",
          "sortOrder": 0
        }
        """
        let decodedLenientModule = try! JSONDecoder().decode(MonitorModule.self, from: Data(lenientModuleJSON.utf8))
        expect(decodedLenientModule.isCollapsed, "Module JSON should accept string booleans for new UI-only fields")
        expect(decodedLenientModule.percentDisplayMode == .used, "Unknown percent display mode should fall back to used mode")

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
        let expectedCodexReset = ISO8601DateFormatter().date(from: "2027-01-15T00:00:00Z")!
        expect(exhaustedCodexItems.first?.resetDate == expectedCodexReset, "Codex ISO reset_at should decode into the quota reset date")

        let missingWindowSecondsCodexJSON = """
        {
          "rate_limit": {
            "primary_window": {
              "remaining_percent": 10,
              "reset_after_seconds": 60
            },
            "secondary_window": {
              "used_percent": 25,
              "reset_after_seconds": 120
            }
          },
          "additional_rate_limits": [
            {
              "limit_name": "Mystery",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 10,
                  "reset_after_seconds": 30
                }
              }
            }
          ]
        }
        """
        let missingWindowItems = try! CodexProvider.testUsageItems(from: missingWindowSecondsCodexJSON)
        expect(missingWindowItems.map(\.key) == ["5hour", "7day"], "Codex primary and secondary windows should keep stable keys when limit_window_seconds is missing")
        expect(missingWindowItems.map(\.used) == [90, 25], "Codex missing-window fallback should preserve used and remaining percent semantics")

        let resetCreditsJSON = """
        {
          "available_count": "2",
          "credits": [
            {
              "status": "available",
              "title": "Rate limit reset",
              "granted_at": "2026-07-10T12:00:00Z",
              "expires_at": "2026-07-17T12:00:00Z"
            }
          ]
        }
        """
        let resetCreditInfo = try! CodexProvider.testResetCreditsExtraInfo(
            from: resetCreditsJSON,
            timeZone: TimeZone(secondsFromGMT: 8 * 3_600)!
        )
        expect(resetCreditInfo.count == 2, "Codex reset credit info should include count and one credit summary")
        expect(resetCreditInfo[0].label == "可用重置次数", "Codex reset credit info should label available_count")
        expect(resetCreditInfo[0].value == "2", "Codex reset credit info should preserve available_count")
        expect(resetCreditInfo[1].label == "重置卡 1", "Codex reset credit info should label individual reset cards")
        expect(
            resetCreditInfo[1].value == "Rate limit reset · available · 发放 2026-07-10 20:00 · 过期 2026-07-17 20:00",
            "Codex reset credit info should convert granted_at and expires_at from UTC to local time"
        )

    }
}
