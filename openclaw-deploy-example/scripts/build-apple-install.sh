#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_IOS=1
RUN_MAC=1
DRY_RUN=0

IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-}"
IOS_SCHEME="${IOS_SCHEME:-OpenClaw}"
IOS_CONFIGURATION="${IOS_CONFIGURATION:-Debug}"
IOS_DERIVED_DATA="${IOS_DERIVED_DATA:-/tmp/openclaw-ios-derived}"
SKIP_IOS_SIGNING=0

MAC_BUILD_CONFIG="${MAC_BUILD_CONFIG:-release}"
MAC_INSTALL_PATH="${MAC_INSTALL_PATH:-/Applications/OpenClaw.app}"
MAC_SKIP_TSC="${MAC_SKIP_TSC:-1}"
ALLOW_ADHOC_SIGNING_FOR_MAC="${ALLOW_ADHOC_SIGNING_FOR_MAC:-0}"
FORCE_BUNDLE_ID_MISMATCH=0

usage() {
  cat <<'EOF'
Usage:
  scripts/build-apple-install.sh [options]

Default behavior:
  - Build + install iOS app to connected real iPhone
  - Build + overwrite-install macOS app to /Applications/OpenClaw.app

Options:
  --dry-run                     Print planned commands without executing.
  --ios-only                    Run only iOS build/install.
  --mac-only                    Run only macOS package/overwrite install.
  --ios-device-udid <udid>      Target iPhone UDID (auto-detect if omitted).
  --ios-scheme <name>           Xcode scheme (default: OpenClaw).
  --ios-configuration <name>    Build config (default: Debug).
  --ios-derived-data <path>     DerivedData path (default: /tmp/openclaw-ios-derived).
  --skip-ios-signing            Skip scripts/ios-configure-signing.sh.
  --mac-build-config <name>     macOS build config for package script (default: release).
  --mac-install-path <path>     macOS install destination (default: /Applications/OpenClaw.app).
  --mac-skip-tsc <0|1>          Pass SKIP_TSC to package script (default: 1).
  --allow-adhoc-signing         Set ALLOW_ADHOC_SIGNING=1 for macOS packaging.
  --force-bundle-id-mismatch    Allow overwrite even if bundle IDs differ.
  -h, --help                    Show this help.
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

read_plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "$plist" 2>/dev/null || true
}

detect_ios_udid() {
  local udid
  udid="$(
    xcrun xctrace list devices 2>/dev/null \
      | grep -i 'iphone' \
      | grep -vi 'simulator' \
      | sed -nE 's/.*\(([0-9A-Fa-f-]{8,})\)[[:space:]]*$/\1/p' \
      | head -n1
  )"
  if [[ -n "$udid" ]]; then
    printf '%s\n' "$udid"
    return 0
  fi

  udid="$(
    xcrun devicectl list devices 2>/dev/null \
      | grep -i 'iphone' \
      | grep -i 'connected' \
      | sed -nE 's/.*\b([0-9A-Fa-f-]{8,})\b.*/\1/p' \
      | head -n1
  )"
  printf '%s\n' "$udid"
}

run_ios_flow() {
  log "==> iOS: build and install to real device"
  require_cmd xcrun
  require_cmd xcodebuild
  require_cmd xcodegen

  if [[ "$SKIP_IOS_SIGNING" != "1" ]]; then
    run_cmd "$ROOT_DIR/scripts/ios-configure-signing.sh"
  else
    log "Skipping iOS signing config (--skip-ios-signing)"
  fi

  run_cmd bash -lc "cd '$ROOT_DIR/apps/ios' && xcodegen generate"

  if [[ -z "$IOS_DEVICE_UDID" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      IOS_DEVICE_UDID="<auto-detected-udid>"
    else
      IOS_DEVICE_UDID="$(detect_ios_udid)"
      [[ -n "$IOS_DEVICE_UDID" ]] || fail "No connected iPhone detected. Pass --ios-device-udid <udid>."
    fi
  fi
  log "iOS target UDID: $IOS_DEVICE_UDID"

  run_cmd xcodebuild \
    -project "$ROOT_DIR/apps/ios/OpenClaw.xcodeproj" \
    -scheme "$IOS_SCHEME" \
    -configuration "$IOS_CONFIGURATION" \
    -destination "id=$IOS_DEVICE_UDID" \
    -derivedDataPath "$IOS_DERIVED_DATA" \
    -allowProvisioningUpdates \
    build

  local ios_app
  ios_app="$IOS_DERIVED_DATA/Build/Products/${IOS_CONFIGURATION}-iphoneos/OpenClaw.app"
  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -d "$ios_app" ]] || fail "Built iOS app not found: $ios_app"
  fi

  run_cmd xcrun devicectl device install app --device "$IOS_DEVICE_UDID" "$ios_app"

  if [[ "$DRY_RUN" != "1" ]]; then
    local bundle_id
    bundle_id="$(read_plist_value "$ios_app/Info.plist" "CFBundleIdentifier")"
    log "iOS install done: bundleID=${bundle_id:-unknown}"
  fi
}

run_mac_flow() {
  log "==> macOS: package and overwrite-install"
  require_cmd /usr/bin/ditto
  [[ -x "$ROOT_DIR/scripts/package-mac-app.sh" ]] || fail "Missing script: scripts/package-mac-app.sh"

  local -a mac_env
  mac_env=("BUILD_CONFIG=$MAC_BUILD_CONFIG" "SKIP_TSC=$MAC_SKIP_TSC")
  if [[ "$ALLOW_ADHOC_SIGNING_FOR_MAC" == "1" ]]; then
    mac_env+=("ALLOW_ADHOC_SIGNING=1")
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] (cd %q && env ' "$ROOT_DIR"
    printf '%q ' "${mac_env[@]}"
    printf '%q)\n' "scripts/package-mac-app.sh"
  else
    (
      cd "$ROOT_DIR"
      env "${mac_env[@]}" scripts/package-mac-app.sh
    )
  fi

  local built_app
  built_app="$ROOT_DIR/dist/OpenClaw.app"
  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -d "$built_app" ]] || fail "Built macOS app not found: $built_app"
  fi

  if [[ "$DRY_RUN" != "1" && -d "$MAC_INSTALL_PATH" && "$FORCE_BUNDLE_ID_MISMATCH" != "1" ]]; then
    local source_bundle_id target_bundle_id
    source_bundle_id="$(read_plist_value "$built_app/Contents/Info.plist" "CFBundleIdentifier")"
    target_bundle_id="$(read_plist_value "$MAC_INSTALL_PATH/Contents/Info.plist" "CFBundleIdentifier")"
    if [[ -n "$source_bundle_id" && -n "$target_bundle_id" && "$source_bundle_id" != "$target_bundle_id" ]]; then
      fail "Bundle ID mismatch (built=$source_bundle_id, installed=$target_bundle_id). Use --force-bundle-id-mismatch."
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] /usr/bin/ditto '$built_app' '$MAC_INSTALL_PATH'"
    return 0
  fi

  if ! /usr/bin/ditto "$built_app" "$MAC_INSTALL_PATH"; then
    if command -v sudo >/dev/null 2>&1; then
      log "Retrying with sudo for overwrite install..."
      sudo /usr/bin/ditto "$built_app" "$MAC_INSTALL_PATH"
    else
      fail "Overwrite install failed and sudo is unavailable."
    fi
  fi

  local version build bundle_id
  bundle_id="$(read_plist_value "$MAC_INSTALL_PATH/Contents/Info.plist" "CFBundleIdentifier")"
  version="$(read_plist_value "$MAC_INSTALL_PATH/Contents/Info.plist" "CFBundleShortVersionString")"
  build="$(read_plist_value "$MAC_INSTALL_PATH/Contents/Info.plist" "CFBundleVersion")"
  log "macOS install done: bundleID=${bundle_id:-unknown} version=${version:-unknown} build=${build:-unknown}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --ios-only)
      RUN_IOS=1
      RUN_MAC=0
      shift
      ;;
    --mac-only)
      RUN_IOS=0
      RUN_MAC=1
      shift
      ;;
    --ios-device-udid)
      IOS_DEVICE_UDID="${2:-}"
      [[ -n "$IOS_DEVICE_UDID" ]] || fail "--ios-device-udid requires a value"
      shift 2
      ;;
    --ios-scheme)
      IOS_SCHEME="${2:-}"
      [[ -n "$IOS_SCHEME" ]] || fail "--ios-scheme requires a value"
      shift 2
      ;;
    --ios-configuration)
      IOS_CONFIGURATION="${2:-}"
      [[ -n "$IOS_CONFIGURATION" ]] || fail "--ios-configuration requires a value"
      shift 2
      ;;
    --ios-derived-data)
      IOS_DERIVED_DATA="${2:-}"
      [[ -n "$IOS_DERIVED_DATA" ]] || fail "--ios-derived-data requires a value"
      shift 2
      ;;
    --skip-ios-signing)
      SKIP_IOS_SIGNING=1
      shift
      ;;
    --mac-build-config)
      MAC_BUILD_CONFIG="${2:-}"
      [[ -n "$MAC_BUILD_CONFIG" ]] || fail "--mac-build-config requires a value"
      shift 2
      ;;
    --mac-install-path)
      MAC_INSTALL_PATH="${2:-}"
      [[ -n "$MAC_INSTALL_PATH" ]] || fail "--mac-install-path requires a value"
      shift 2
      ;;
    --mac-skip-tsc)
      MAC_SKIP_TSC="${2:-}"
      [[ -n "$MAC_SKIP_TSC" ]] || fail "--mac-skip-tsc requires a value"
      shift 2
      ;;
    --allow-adhoc-signing)
      ALLOW_ADHOC_SIGNING_FOR_MAC=1
      shift
      ;;
    --force-bundle-id-mismatch)
      FORCE_BUNDLE_ID_MISMATCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1 (use --help)"
      ;;
  esac
done

[[ "$RUN_IOS" == "1" || "$RUN_MAC" == "1" ]] || fail "Nothing to do. Use --ios-only or --mac-only."
[[ "$(uname -s)" == "Darwin" ]] || fail "This script requires macOS."

if [[ "$RUN_IOS" == "1" ]]; then
  run_ios_flow
fi

if [[ "$RUN_MAC" == "1" ]]; then
  run_mac_flow
fi

log "All requested flows completed."
