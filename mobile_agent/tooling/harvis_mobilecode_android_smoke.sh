#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mobile_agent/tooling/harvis_mobilecode_android_smoke.sh [options]

Options:
  --serial SERIAL              adb serial. Required when multiple devices are online.
  --apk PATH                   APK to install. Default: build/app/outputs/flutter-apk/app-debug.apk
  --package PACKAGE            Android package. Default: com.mobilecode.app
  --activity ACTIVITY          Launch activity. Default: .MainActivity
  --output DIR                 Evidence directory. Default: qa-output/harvis-mobilecode-android-smoke-<timestamp>
  --handoff-fixture PATH       Handoff fixture to copy into evidence.
  --build-debug                Build the default debug APK if it is missing.
  -h, --help                   Show this help.

P3 scope:
  This is an Android Emulator smoke evidence collector for the Harvis/MobileCode
  bridge lane. It installs and launches MobileCode, captures screenshot/UI XML/
  focus/logcat/APK hash, and copies the handoff fixture. It does not send Lark
  messages, call Harvis, publish GitHub, or control a physical phone.
USAGE
}

redact_sensitive() {
  perl -pe 's/(?i)(bearer\s+)[A-Za-z0-9._-]+/${1}<redacted>/g; s/(?i)[A-Za-z0-9_]*(token|cookie|secret|password)[A-Za-z0-9_]*=\S+/redacted=<redacted>/g; s#/(Users|Volumes|private|var/folders)/[^[:space:]]+#/[local-path]#g'
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mobile_agent_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$mobile_agent_dir/.." && pwd)"

timestamp="$(date +%Y%m%d-%H%M%S)"
serial=""
apk_path="$mobile_agent_dir/build/app/outputs/flutter-apk/app-debug.apk"
package_name="com.mobilecode.app"
activity_name=".MainActivity"
output_dir="$mobile_agent_dir/qa-output/harvis-mobilecode-android-smoke-$timestamp"
handoff_fixture="$mobile_agent_dir/test/fixtures/harvis_mobilecode_handoff.project_check.json"
build_debug=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      serial="${2:-}"
      [[ -n "$serial" ]] || { echo "Missing value for --serial" >&2; exit 2; }
      shift 2
      ;;
    --apk)
      apk_path="${2:-}"
      [[ -n "$apk_path" ]] || { echo "Missing value for --apk" >&2; exit 2; }
      shift 2
      ;;
    --package)
      package_name="${2:-}"
      [[ -n "$package_name" ]] || { echo "Missing value for --package" >&2; exit 2; }
      shift 2
      ;;
    --activity)
      activity_name="${2:-}"
      [[ -n "$activity_name" ]] || { echo "Missing value for --activity" >&2; exit 2; }
      shift 2
      ;;
    --output)
      output_dir="${2:-}"
      [[ -n "$output_dir" ]] || { echo "Missing value for --output" >&2; exit 2; }
      shift 2
      ;;
    --handoff-fixture)
      handoff_fixture="${2:-}"
      [[ -n "$handoff_fixture" ]] || { echo "Missing value for --handoff-fixture" >&2; exit 2; }
      shift 2
      ;;
    --build-debug)
      build_debug=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required but was not found on PATH." >&2
  exit 127
fi

mkdir -p "$output_dir"
adb devices -l > "$output_dir/adb-devices.txt"

device_lines=()
while IFS= read -r line; do
  device_lines+=("$line")
done < <(awk 'NR > 1 && $2 == "device" { print $0 }' "$output_dir/adb-devices.txt")

if [[ ${#device_lines[@]} -eq 0 ]]; then
  echo "No online Android emulator found. Evidence: $output_dir/adb-devices.txt" >&2
  exit 1
fi

if [[ -n "$serial" ]]; then
  matched=0
  for line in "${device_lines[@]}"; do
    if [[ "$line" == "$serial "* ]]; then
      matched=1
      break
    fi
  done
  [[ "$matched" -eq 1 ]] || { echo "Requested serial is not online: $serial" >&2; exit 1; }
elif [[ ${#device_lines[@]} -eq 1 ]]; then
  serial="$(awk '{ print $1 }' <<<"${device_lines[0]}")"
else
  echo "Multiple Android devices are online. Re-run with --serial SERIAL." >&2
  cat "$output_dir/adb-devices.txt" >&2
  exit 1
fi

device_line="$(printf '%s\n' "${device_lines[@]}" | awk -v serial="$serial" '$1 == serial { print }')"
if [[ "$serial" != emulator-* && "$serial" != 127.0.0.1:* && "$serial" != localhost:* && "$device_line" != *"device:emu"* ]]; then
  echo "P3 Harvis/MobileCode smoke must run on Android Emulator before real-device proof: $serial" >&2
  echo "Use a dedicated real-device lane only after emulator evidence passes." >&2
  exit 3
fi

adb_base=(adb -s "$serial")
adb_cmd() {
  "${adb_base[@]}" "$@"
}

if [[ ! -f "$apk_path" ]]; then
  if [[ "$build_debug" -eq 1 && "$apk_path" == "$mobile_agent_dir/build/app/outputs/flutter-apk/app-debug.apk" ]]; then
    (cd "$mobile_agent_dir" && flutter build apk --debug) 2>&1 | redact_sensitive > "$output_dir/build-debug-apk.txt"
  else
    echo "APK not found: $apk_path" >&2
    echo "Build it first or pass --build-debug for the default debug APK." >&2
    exit 66
  fi
fi

{
  echo "serial=$serial"
  echo "package=$package_name"
  echo "activity=$activity_name"
  echo "apk=$(basename "$apk_path")"
  echo "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_dir/run-context.txt"

{
  echo "model=$(adb_cmd shell getprop ro.product.model | tr -d '\r')"
  echo "manufacturer=$(adb_cmd shell getprop ro.product.manufacturer | tr -d '\r')"
  echo "android_release=$(adb_cmd shell getprop ro.build.version.release | tr -d '\r')"
  echo "android_sdk=$(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r')"
  echo "abi=$(adb_cmd shell getprop ro.product.cpu.abilist | tr -d '\r')"
} > "$output_dir/device-props.txt"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$apk_path" > "$output_dir/apk-sha256.txt"
else
  sha256sum "$apk_path" > "$output_dir/apk-sha256.txt"
fi
printf '%s\n' "$apk_path" | redact_sensitive > "$output_dir/apk-path.txt"

if [[ -f "$handoff_fixture" ]]; then
  cp "$handoff_fixture" "$output_dir/handoff-fixture.json"
else
  echo "Handoff fixture not found: $handoff_fixture" >&2
fi

adb_cmd logcat -c || true

set +e
adb_cmd install -r -d "$apk_path" > "$output_dir/install.txt" 2>&1
install_exit=$?
adb_cmd shell pm grant "$package_name" android.permission.POST_NOTIFICATIONS >> "$output_dir/install.txt" 2>&1 || true
adb_cmd shell pm grant "$package_name" android.permission.RECORD_AUDIO >> "$output_dir/install.txt" 2>&1 || true
adb_cmd shell am start -W -n "$package_name/$activity_name" > "$output_dir/launch.txt" 2>&1
launch_exit=$?
set -e

sleep 2
adb_cmd shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp|topResumedActivity" > "$output_dir/window-focus.txt" 2>&1 || true
adb_cmd exec-out screencap -p > "$output_dir/screenshot-main.png" || true
adb_cmd shell uiautomator dump /sdcard/harvis-mobilecode-window.xml > "$output_dir/uiautomator-dump.txt" 2>&1 || true
adb_cmd pull /sdcard/harvis-mobilecode-window.xml "$output_dir/window-main.xml" > "$output_dir/uiautomator-pull.txt" 2>&1 || true
adb_cmd logcat -d -t 1500 | redact_sensitive > "$output_dir/logcat.txt" || true
rg -n "FATAL EXCEPTION|E/flutter|ANR|MissingPluginException|SIGSEGV" "$output_dir/logcat.txt" > "$output_dir/logcat-fatal-scan.txt" || true

ui_markers="MobileCode|No messages yet|Mimo|Single-shot|任务派发|能力中心|Harvis"
if [[ -f "$output_dir/window-main.xml" ]]; then
  rg -n "$ui_markers" "$output_dir/window-main.xml" > "$output_dir/window-marker-scan.txt" || true
else
  : > "$output_dir/window-marker-scan.txt"
fi

install_ok=false
launch_ok=false
focus_ok=false
ui_marker_ok=false
logcat_clean=false

grep -q "Success" "$output_dir/install.txt" && install_ok=true
grep -q "Status: ok" "$output_dir/launch.txt" && launch_ok=true
grep -q "$package_name" "$output_dir/window-focus.txt" && focus_ok=true
[[ -s "$output_dir/window-marker-scan.txt" ]] && ui_marker_ok=true
[[ ! -s "$output_dir/logcat-fatal-scan.txt" ]] && logcat_clean=true

if command -v python3 >/dev/null 2>&1; then
  python3 - "$output_dir" "$serial" "$package_name" "$install_exit" "$launch_exit" "$install_ok" "$launch_ok" "$focus_ok" "$ui_marker_ok" "$logcat_clean" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
summary = {
    "schema": "harvis_mobilecode_android_smoke.v1",
    "serial": sys.argv[2],
    "package": sys.argv[3],
    "install_exit": int(sys.argv[4]),
    "launch_exit": int(sys.argv[5]),
    "checks": {
        "install_ok": sys.argv[6] == "true",
        "launch_ok": sys.argv[7] == "true",
        "focus_ok": sys.argv[8] == "true",
        "ui_marker_ok": sys.argv[9] == "true",
        "logcat_clean": sys.argv[10] == "true",
    },
    "evidence": {
        "apk_sha256": "apk-sha256.txt",
        "install": "install.txt",
        "launch": "launch.txt",
        "screenshot": "screenshot-main.png",
        "ui_xml": "window-main.xml",
        "focus": "window-focus.txt",
        "logcat": "logcat.txt",
        "handoff_fixture": "handoff-fixture.json",
    },
}
summary["ok"] = all(summary["checks"].values())
(out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
PY
else
  cat > "$output_dir/summary.json" <<EOF
{"schema":"harvis_mobilecode_android_smoke.v1","serial":"$serial","package":"$package_name","ok":false,"note":"python3 missing; inspect evidence files manually"}
EOF
fi

cat > "$output_dir/README.md" <<EOF
# Harvis MobileCode Android Emulator Smoke

Scope: P3 emulator evidence prep for MobileCode as Harvis mobile runtime.

- Does not send Lark messages.
- Does not call Harvis.
- Does not control a physical phone.
- Captures install, launch, screenshot, UI XML, focus, logcat, APK checksum, and handoff fixture.

Inspect summary.json first.
EOF

cat "$output_dir/summary.json"
if [[ "$install_exit" -ne 0 || "$launch_exit" -ne 0 ]]; then
  echo "Android smoke install/launch command failed. Evidence: $output_dir" >&2
  exit 1
fi

if [[ "$install_ok" != true || "$launch_ok" != true || "$focus_ok" != true || "$ui_marker_ok" != true || "$logcat_clean" != true ]]; then
  echo "Android smoke checks failed. Evidence: $output_dir" >&2
  exit 4
fi

echo "Evidence: $output_dir"
