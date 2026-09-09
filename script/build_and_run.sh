#!/usr/bin/env bash
# Develop with an isolated preview identity and data directory.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify|--demo) ;; *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify|--demo]" >&2; exit 2;; esac
PREVIEW_DIR="$ROOT_DIR/build/preview"
DATA_DIR="$ROOT_DIR/.local/preview-data"
PREVIEW_NAME="Polaris Preview"
PREVIEW_ID="com.bingowu.polaris.preview"
if [[ "$MODE" == "--demo" ]]; then
    PREVIEW_DIR="$ROOT_DIR/build/demo"
    DATA_DIR="$ROOT_DIR/.local/demo-data"
    PREVIEW_NAME="Polaris Demo"
    PREVIEW_ID="com.bingowu.polaris.demo.preview"
fi
APP_BUNDLE="$PREVIEW_DIR/$PREVIEW_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Polaris"
# Stop only this checkout's preview executable, never the installed app.
while IFS= read -r app_pid; do
    [[ -n "$app_pid" ]] && kill "$app_pid"
done < <(ps -axo pid=,comm= | awk -v app="$APP_BINARY" '{pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == app) print pid}')
mkdir -p "$DATA_DIR" "$PREVIEW_DIR"
if [[ "$MODE" == "--demo" && ! -f "$DATA_DIR/tasks.json" ]]; then
    python3 "$ROOT_DIR/script/make_demo_data.py" "$DATA_DIR"
    defaults write "$PREVIEW_ID" polarisSurface -string mist
    defaults write "$PREVIEW_ID" polarisAccent -string lime
fi
FINGERPRINT=$( {
    find "$ROOT_DIR/Docket" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
    shasum -a 256 "$ROOT_DIR/build.sh" "$ROOT_DIR/script/build_and_run.sh"
    xcode-select -p
    swiftc --version
} | shasum -a 256 | awk '{print $1}')
if [[ -f "$PREVIEW_DIR/source.sha256" && "$(cat "$PREVIEW_DIR/source.sha256")" == "$FINGERPRINT" ]] &&
   codesign --verify --strict "$APP_BUNDLE" 2>/dev/null; then
    echo "Source unchanged; using the verified preview build."
else
    POLARIS_BUILD_DIR="$PREVIEW_DIR/native" POLARIS_BUILD_MODE=debug "$ROOT_DIR/build.sh"
    ditto "$PREVIEW_DIR/native/Polaris.app" "$APP_BUNDLE"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PREVIEW_ID" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $PREVIEW_NAME" "$APP_BUNDLE/Contents/Info.plist"
    codesign --force --sign - --identifier "$PREVIEW_ID" "$APP_BUNDLE"
    printf '%s\n' "$FINGERPRINT" > "$PREVIEW_DIR/source.sha256"
fi
case "$MODE" in
  --debug) exec lldb -- "$APP_BINARY" --preview-data "$DATA_DIR" ;;
  *) /usr/bin/open -n "$APP_BUNDLE" --args --preview-data "$DATA_DIR" ;;
esac
case "$MODE" in
  --logs|--telemetry) exec /usr/bin/log stream --level info --style compact --predicate 'process == "Polaris"' ;;
  --verify)
    for attempt in {1..20}; do
      if ps -axo comm= | /usr/bin/grep -Fx "$APP_BINARY" >/dev/null; then
        echo "Preview process running. UI and behavior still require verification."
        exit 0
      fi
      sleep 0.25
    done
    echo "Preview process did not start" >&2; exit 1 ;;
esac
