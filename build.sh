#!/bin/bash
# build.sh — Compile Docket into a macOS .app bundle
# Usage: ./build.sh
# Requires: Xcode Command Line Tools (swiftc)
#
# Note: this self-build defines DOCKET_SELFBUILD and omits the Tip Jar
# (StoreKit in-app purchases only work in a Mac App Store-distributed build).
# The Tip Jar ships in the App Store build produced by the Xcode project.
set -euo pipefail

APP_NAME="Polaris"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${POLARIS_BUILD_DIR:-$SCRIPT_DIR/build}"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SRC_DIR="$SCRIPT_DIR/Docket"
BUILD_ARCH="$(uname -m)"
case "${POLARIS_BUILD_MODE:-release}" in
    release) COMPILER_FLAGS=(-Osize -whole-module-optimization) ;;
    debug) COMPILER_FLAGS=(-Onone -g) ;;
    *) echo "POLARIS_BUILD_MODE must be release or debug" >&2; exit 2 ;;
esac

echo "🔨 Building $APP_NAME..."

# Keep other products, test binaries and the preview cache in this directory.
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# Compile all Swift source files
swiftc \
    -target "$BUILD_ARCH-apple-macos14.0" \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework AppKit \
    -framework SwiftUI \
    -framework UserNotifications \
    -framework ServiceManagement \
    -framework Carbon \
    -framework EventKit \
    "${COMPILER_FLAGS[@]}" \
    -parse-as-library \
    -suppress-warnings \
    -D DOCKET_SELFBUILD \
    "$SRC_DIR/Models/PolarisAppearance.swift" \
    "$SRC_DIR/Services/GoalDateParser.swift" \
    "$SRC_DIR/Services/GoalImportPlan.swift" \
    "$SRC_DIR/Views/PolarisSearchField.swift" \
    "$SRC_DIR/Views/PolarisSettingsView.swift" \
    "$SRC_DIR/Views/PolarisChrome.swift" \
    "$SRC_DIR/Views/PolarisActivityView.swift" \
    "$SRC_DIR/Services/PolarisMenuActivity.swift" \
    "$SRC_DIR/Models/ReminderOffset.swift" \
    "$SRC_DIR/Models/NavDestination.swift" \
    "$SRC_DIR/Models/GoalPeriod.swift" \
    "$SRC_DIR/Services/GoalBoardRules.swift" \
    "$SRC_DIR/Services/PolarisSymbol.swift" \
    "$SRC_DIR/Models/TodoItem.swift" \
    "$SRC_DIR/Models/TaskList.swift" \
    "$SRC_DIR/Models/TaskLabel.swift" \
    "$SRC_DIR/Models/ColorPalette.swift" \
    "$SRC_DIR/Models/IconPalette.swift" \
    "$SRC_DIR/Models/Recurrence.swift" \
    "$SRC_DIR/Models/Quadrant.swift" \
    "$SRC_DIR/Models/MatrixLayout.swift" \
    "$SRC_DIR/Models/AppTheme.swift" \
    "$SRC_DIR/Models/HotkeyMapping.swift" \
    "$SRC_DIR/Models/SortMode.swift" \
    "$SRC_DIR/Models/Strings.swift" \
    "$SRC_DIR/Services/NotificationManager.swift" \
    "$SRC_DIR/Services/Store.swift" \
    "$SRC_DIR/Services/DateParser.swift" \
    "$SRC_DIR/Services/DueDateFormatter.swift" \
    "$SRC_DIR/Services/RemindersSync.swift" \
    "$SRC_DIR/Views/TaskRowView.swift" \
    "$SRC_DIR/Views/SwipeableTaskRow.swift" \
    "$SRC_DIR/Views/CalendarPickerView.swift" \
    "$SRC_DIR/Views/TimePickerView.swift" \
    "$SRC_DIR/Views/ReminderPickerView.swift" \
    "$SRC_DIR/Views/RecurrencePickerView.swift" \
    "$SRC_DIR/Views/PriorityPickerView.swift" \
    "$SRC_DIR/Views/LabelPickerView.swift" \
    "$SRC_DIR/Views/ColorPickerGrid.swift" \
    "$SRC_DIR/Views/ColorSwatchButton.swift" \
    "$SRC_DIR/Views/IconPickerGrid.swift" \
    "$SRC_DIR/Views/IconPickerButton.swift" \
    "$SRC_DIR/Views/PressableScaleStyle.swift" \
    "$SRC_DIR/Views/RowActionButton.swift" \
    "$SRC_DIR/Views/QuadrantPickerView.swift" \
    "$SRC_DIR/Views/MatrixView.swift" \
    "$SRC_DIR/Views/ThemedToggle.swift" \
    "$SRC_DIR/Views/ConfettiView.swift" \
    "$SRC_DIR/Views/OnboardingView.swift" \
    "$SRC_DIR/Views/UndoToast.swift" \
    "$SRC_DIR/Views/VScroll.swift" \
    "$SRC_DIR/Views/TaskListView.swift" \
    "$SRC_DIR/Views/GoalScheduleView.swift" \
    "$SRC_DIR/Views/GoalEditorView.swift" \
    "$SRC_DIR/Views/GoalEditorControls.swift" \
    "$SRC_DIR/Views/GoalChecklistView.swift" \
    "$SRC_DIR/Views/GoalEditorOptionsView.swift" \
    "$SRC_DIR/Views/ShortcutRecorderView.swift" \
    "$SRC_DIR/Views/CreateTaskView.swift" \
    "$SRC_DIR/Views/TaskDetailView.swift" \
    "$SRC_DIR/Views/CompletedTasksView.swift" \
    "$SRC_DIR/Views/SettingsView.swift" \
    "$SRC_DIR/Views/ContentView.swift" \
    "$SRC_DIR/DocketApp.swift"

# Copy icons
cp "$SRC_DIR/PolarisLogo.png" "$APP_BUNDLE/Contents/Resources/"
# Apple Icon Composer compiles Light/Dark variants plus an older-macOS fallback.
xcrun actool "$SRC_DIR/PolarisAB.icon" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --target-device mac --standalone-icon-behavior all \
    --app-icon PolarisAB --output-partial-info-plist "$BUILD_DIR/icon-info.plist" \
    --output-format human-readable-text
cp "$SRC_DIR/menubar-icon.png" "$APP_BUNDLE/Contents/Resources/"
cp "$SRC_DIR/menubar-icon@2x.png" "$APP_BUNDLE/Contents/Resources/"

# Copy localizations (en + it)
cp -R "$SRC_DIR/en.lproj" "$APP_BUNDLE/Contents/Resources/"
cp -R "$SRC_DIR/it.lproj" "$APP_BUNDLE/Contents/Resources/"
cp -R "$SRC_DIR/zh-Hans.lproj" "$APP_BUNDLE/Contents/Resources/"

# Generate Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Polaris</string>
    <key>CFBundleDisplayName</key>
    <string>Polaris</string>
    <key>CFBundleIdentifier</key>
    <string>com.bingowu.polaris</string>
    <key>CFBundleVersion</key>
    <string>22</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleExecutable</key>
    <string>Polaris</string>
    <key>CFBundleIconFile</key>
    <string>PolarisAB</string>
    <key>CFBundleIconName</key>
    <string>PolarisAB</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Polaris 可将你选择的目标集与 Apple 提醒事项双向同步。</string>
    <key>NSRemindersUsageDescription</key>
    <string>Polaris 可将目标同步到 Apple 提醒事项，以便通过 iCloud、Siri 和 Apple Watch 查看。</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>it</string>
        <string>zh-Hans</string>
    </array>
</dict>
</plist>
PLIST

echo "✅ Built: $APP_BUNDLE"

# Sign the app so notifications and other system features work
codesign --force --sign - --identifier com.bingowu.polaris "$APP_BUNDLE"

echo ""
echo "To run:     open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
