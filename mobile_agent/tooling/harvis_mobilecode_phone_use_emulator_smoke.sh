#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mobile_agent/tooling/harvis_mobilecode_phone_use_emulator_smoke.sh [options]

Options:
  --serial SERIAL        adb serial. Required when multiple emulators are online.
  --apk PATH             APK to install. Default: build/app/outputs/flutter-apk/app-debug.apk
  --package PACKAGE      Android package. Default: com.mobilecode.app
  --activity ACTIVITY    Launch activity. Default: .MainActivity
  --output DIR           Evidence directory. Default: qa-output/harvis-mobilecode-phone-use-<timestamp>
  --text TEXT            Text to type. Default: HarvisP5PhoneUse<timestamp>
  --tap-x X --tap-y Y    Explicit tap coordinates. If omitted, first EditText center is used.
  --skip-install         Do not install the APK before launch.
  --build-debug          Build the default debug APK if it is missing.
  -h, --help             Show this help.

P5 scope:
  Android Emulator only. The primitive is observe screenshot -> tap -> type ->
  assert UI -> evidence. It refuses physical devices by default and does not
  call Harvis, send Lark, publish GitHub, or claim real-device phone-use.
USAGE
}

redact_sensitive() {
  perl -pe 's/(?i)(bearer\s+)[A-Za-z0-9._-]+/${1}<redacted>/g; s/(?i)[A-Za-z0-9_]*(token|cookie|secret|password)[A-Za-z0-9_]*=\S+/redacted=<redacted>/g; s#/(Users|Volumes|private|var/folders)/[^[:space:]]+#/[local-path]#g'
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mobile_agent_dir="$(cd "$script_dir/.." && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"

serial=""
apk_path="$mobile_agent_dir/build/app/outputs/flutter-apk/app-debug.apk"
package_name="com.mobilecode.app"
activity_name=".MainActivity"
output_dir="$mobile_agent_dir/qa-output/harvis-mobilecode-phone-use-$timestamp"
input_text="HarvisP5PhoneUse${timestamp//-/}"
tap_x=""
tap_y=""
skip_install=0
build_debug=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) serial="${2:-}"; shift 2 ;;
    --apk) apk_path="${2:-}"; shift 2 ;;
    --package) package_name="${2:-}"; shift 2 ;;
    --activity) activity_name="${2:-}"; shift 2 ;;
    --output) output_dir="${2:-}"; shift 2 ;;
    --text) input_text="${2:-}"; shift 2 ;;
    --tap-x) tap_x="${2:-}"; shift 2 ;;
    --tap-y) tap_y="${2:-}"; shift 2 ;;
    --skip-install) skip_install=1; shift ;;
    --build-debug) build_debug=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$input_text" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "--text must be adb-input safe: A-Z a-z 0-9 . _ -" >&2
  exit 2
fi

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
  echo "P5 phone-use primitive must run on Android Emulator before real-device proof: $serial" >&2
  exit 3
fi

adb_base=(adb -s "$serial")
adb_cmd() {
  "${adb_base[@]}" "$@"
}

if [[ "$skip_install" -eq 0 ]]; then
  if [[ ! -f "$apk_path" ]]; then
    if [[ "$build_debug" -eq 1 && "$apk_path" == "$mobile_agent_dir/build/app/outputs/flutter-apk/app-debug.apk" ]]; then
      (cd "$mobile_agent_dir" && flutter build apk --debug) 2>&1 | redact_sensitive > "$output_dir/build-debug-apk.txt"
    else
      echo "APK not found: $apk_path" >&2
      echo "Build it first or pass --build-debug for the default debug APK." >&2
      exit 66
    fi
  fi
fi

{
  echo "serial=$serial"
  echo "package=$package_name"
  echo "activity=$activity_name"
  echo "input_text=$input_text"
  echo "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_dir/run-context.txt"

{
  echo "model=$(adb_cmd shell getprop ro.product.model | tr -d '\r')"
  echo "manufacturer=$(adb_cmd shell getprop ro.product.manufacturer | tr -d '\r')"
  echo "android_release=$(adb_cmd shell getprop ro.build.version.release | tr -d '\r')"
  echo "android_sdk=$(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r')"
} > "$output_dir/device-props.txt"

if [[ "$skip_install" -eq 0 ]]; then
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$apk_path" > "$output_dir/apk-sha256.txt"
  else
    sha256sum "$apk_path" > "$output_dir/apk-sha256.txt"
  fi
  printf '%s\n' "$apk_path" | redact_sensitive > "$output_dir/apk-path.txt"
fi

adb_cmd logcat -c || true

set +e
if [[ "$skip_install" -eq 0 ]]; then
  adb_cmd install -r -d "$apk_path" > "$output_dir/install.txt" 2>&1
  install_exit=$?
else
  echo "skip-install=true" > "$output_dir/install.txt"
  install_exit=0
fi
adb_cmd shell am start -W -n "$package_name/$activity_name" > "$output_dir/launch.txt" 2>&1
launch_exit=$?
set -e

sleep 2
adb_cmd exec-out screencap -p > "$output_dir/observe-before.png" || true
adb_cmd shell uiautomator dump /sdcard/harvis-mobilecode-phone-before.xml > "$output_dir/uiautomator-before.txt" 2>&1 || true
adb_cmd pull /sdcard/harvis-mobilecode-phone-before.xml "$output_dir/window-before.xml" > "$output_dir/uiautomator-before-pull.txt" 2>&1 || true

if [[ -z "$tap_x" || -z "$tap_y" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for automatic tap target extraction." >&2
    exit 127
  fi
  python3 - "$output_dir/window-before.xml" "$output_dir/tap-target.json" <<'PY'
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

xml_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
root = ET.parse(xml_path).getroot()
target = None
for node in root.iter("node"):
    klass = node.attrib.get("class", "")
    if "EditText" not in klass:
        continue
    bounds = node.attrib.get("bounds", "")
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if match:
        x1, y1, x2, y2 = map(int, match.groups())
        target = {
            "strategy": "first_edit_text",
            "class": klass,
            "bounds": bounds,
            "x": (x1 + x2) // 2,
            "y": (y1 + y2) // 2,
        }
        break
if not target:
    raise SystemExit("No EditText node found in UI hierarchy.")
out_path.write_text(json.dumps(target, indent=2) + "\n", encoding="utf-8")
print(f"{target['x']} {target['y']}")
PY
  read -r tap_x tap_y < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["x"], d["y"])' "$output_dir/tap-target.json")
else
  cat > "$output_dir/tap-target.json" <<EOF
{"strategy":"explicit_coordinates","x":$tap_x,"y":$tap_y}
EOF
fi

set +e
adb_cmd shell input tap "$tap_x" "$tap_y" > "$output_dir/tap.txt" 2>&1
tap_exit=$?
sleep 1
adb_cmd shell input text "$input_text" > "$output_dir/type.txt" 2>&1
type_exit=$?
set -e

sleep 1
adb_cmd exec-out screencap -p > "$output_dir/observe-after.png" || true
adb_cmd shell uiautomator dump /sdcard/harvis-mobilecode-phone-after.xml > "$output_dir/uiautomator-after.txt" 2>&1 || true
adb_cmd pull /sdcard/harvis-mobilecode-phone-after.xml "$output_dir/window-after.xml" > "$output_dir/uiautomator-after-pull.txt" 2>&1 || true
adb_cmd shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp|topResumedActivity" > "$output_dir/window-focus.txt" 2>&1 || true
adb_cmd logcat -d -t 1500 | redact_sensitive > "$output_dir/logcat.txt" || true
rg -n "FATAL EXCEPTION|E/flutter|ANR|MissingPluginException|SIGSEGV" "$output_dir/logcat.txt" > "$output_dir/logcat-fatal-scan.txt" || true
rg -n "$input_text|MobileCode|任务派发|No messages yet|Phone Use|Run action probe" "$output_dir/window-after.xml" > "$output_dir/assert-ui-scan.txt" || true

install_ok=false
launch_ok=false
observe_before_ok=false
tap_ok=false
type_ok=false
assert_ui_ok=false
logcat_clean=false

grep -q "Success\\|skip-install=true" "$output_dir/install.txt" && install_ok=true
grep -q "Status: ok" "$output_dir/launch.txt" && launch_ok=true
[[ -s "$output_dir/observe-before.png" && -s "$output_dir/window-before.xml" ]] && observe_before_ok=true
[[ "$tap_exit" -eq 0 ]] && tap_ok=true
[[ "$type_exit" -eq 0 ]] && type_ok=true
rg -q "$input_text" "$output_dir/window-after.xml" && assert_ui_ok=true
[[ ! -s "$output_dir/logcat-fatal-scan.txt" ]] && logcat_clean=true

python3 - "$output_dir" "$serial" "$package_name" "$input_text" "$install_exit" "$launch_exit" "$tap_exit" "$type_exit" "$install_ok" "$launch_ok" "$observe_before_ok" "$tap_ok" "$type_ok" "$assert_ui_ok" "$logcat_clean" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
summary = {
    "schema": "harvis_mobilecode_phone_use_emulator_smoke.v1",
    "serial": sys.argv[2],
    "package": sys.argv[3],
    "input_text": sys.argv[4],
    "install_exit": int(sys.argv[5]),
    "launch_exit": int(sys.argv[6]),
    "tap_exit": int(sys.argv[7]),
    "type_exit": int(sys.argv[8]),
    "checks": {
        "install_ok": sys.argv[9] == "true",
        "launch_ok": sys.argv[10] == "true",
        "observe_before_ok": sys.argv[11] == "true",
        "tap_ok": sys.argv[12] == "true",
        "type_ok": sys.argv[13] == "true",
        "assert_ui_ok": sys.argv[14] == "true",
        "logcat_clean": sys.argv[15] == "true",
    },
    "evidence": {
        "observe_before": "observe-before.png",
        "window_before": "window-before.xml",
        "tap_target": "tap-target.json",
        "tap": "tap.txt",
        "type": "type.txt",
        "observe_after": "observe-after.png",
        "window_after": "window-after.xml",
        "assert_ui_scan": "assert-ui-scan.txt",
        "focus": "window-focus.txt",
        "logcat": "logcat.txt",
    },
    "boundary": "Android Emulator only; not real-device phone-use.",
}
summary["ok"] = all(summary["checks"].values())
(out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
PY

cat > "$output_dir/README.md" <<EOF
# Harvis MobileCode Phone-Use Emulator Smoke

Scope: P5 minimal Android Emulator phone-use primitive.

Flow:
- observe screenshot/UI XML
- tap target
- type text
- assert UI contains typed text
- capture evidence

Boundary: emulator only; no Lark send, no Harvis call, no GitHub publish, no physical-phone proof.
EOF

cat "$output_dir/summary.json"
if [[ "$install_ok" != true || "$launch_ok" != true || "$observe_before_ok" != true || "$tap_ok" != true || "$type_ok" != true || "$assert_ui_ok" != true || "$logcat_clean" != true ]]; then
  echo "Phone-use emulator primitive failed. Evidence: $output_dir" >&2
  exit 4
fi

echo "Evidence: $output_dir"
