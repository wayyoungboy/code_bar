#!/bin/sh
set -eu

if [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
  exit 0
fi

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TEST_BINARY="${DERIVED_FILE_DIR:-/tmp}/codebar-module-behavior-tests"

swiftc \
  -D CODEBAR_BEHAVIOR_TESTS \
  "$SRCROOT/CodeBar/Constants.swift" \
  "$SRCROOT/CodeBar/Logger.swift" \
  "$SRCROOT/CodeBar/KeychainHelper.swift" \
  "$SRCROOT/CodeBar/UsageTracker.swift" \
  "$SRCROOT/CodeBar/MenuBarView.swift" \
  "$SRCROOT/CodeBar/SettingsWindow.swift" \
  "$SRCROOT/CodeBar/UpdateChecker.swift" \
  "$SRCROOT/CodeBar/Providers/PlatformProvider.swift" \
  "$SRCROOT/CodeBar/Providers/BailianProvider.swift" \
  "$SRCROOT/CodeBar/Providers/ZenMuxProvider.swift" \
  "$SRCROOT/CodeBar/Providers/MimoProvider.swift" \
  "$SRCROOT/CodeBar/Providers/CodexProvider.swift" \
  "$SRCROOT/CodeBar/Providers/GeminiProvider.swift" \
  "$SRCROOT/CodeBarTests/TestNotifications.swift" \
  "$SRCROOT/CodeBarTests/ModuleBehaviorTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

if [ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]; then
  : > "$SCRIPT_OUTPUT_FILE_0"
fi
