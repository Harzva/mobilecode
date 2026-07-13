#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mobile_agent/tooling/linux_sandbox_android_proof.sh [--serial SERIAL] [--allow-emulator]

Runs the MobileCode Linux Sandbox Android proof instrumentation test and saves
local QA evidence under build/linux-sandbox-proof/<timestamp>/.

By default this script refuses emulator-only runs so physical device proof is
not accidentally confused with emulator proof. Use --allow-emulator only for
emulator repro/debug.
USAGE
}

redact_sensitive() {
  perl -pe 's/(?i)[A-Za-z0-9_]*(token|cookie|secret|password)[A-Za-z0-9_]*=\S+/redacted=<redacted>/g; s/(?i)(bearer\s+)[A-Za-z0-9._-]+/${1}<redacted>/g'
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$MOBILE_AGENT_DIR/android"
ALLOW_EMULATOR=0
REQUESTED_SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      REQUESTED_SERIAL="${2:-}"
      if [[ -z "$REQUESTED_SERIAL" ]]; then
        echo "Missing value for --serial" >&2
        exit 2
      fi
      shift 2
      ;;
    --allow-emulator)
      ALLOW_EMULATOR=1
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

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$MOBILE_AGENT_DIR/build/linux-sandbox-proof/$TIMESTAMP"
mkdir -p "$EVIDENCE_DIR"

adb devices -l > "$EVIDENCE_DIR/adb-devices.txt"

DEVICE_LINES=()
while IFS= read -r line; do
  DEVICE_LINES+=("$line")
done < <(awk 'NR > 1 && $2 == "device" { print $0 }' "$EVIDENCE_DIR/adb-devices.txt")
if [[ ${#DEVICE_LINES[@]} -eq 0 ]]; then
  echo "No online Android device found. Evidence: $EVIDENCE_DIR/adb-devices.txt" >&2
  exit 1
fi

SERIAL=""
if [[ -n "$REQUESTED_SERIAL" ]]; then
  for line in "${DEVICE_LINES[@]}"; do
    if [[ "$line" == "$REQUESTED_SERIAL "* ]]; then
      SERIAL="$REQUESTED_SERIAL"
      break
    fi
  done
  if [[ -z "$SERIAL" ]]; then
    echo "Requested serial is not online: $REQUESTED_SERIAL" >&2
    exit 1
  fi
elif [[ ${#DEVICE_LINES[@]} -eq 1 ]]; then
  SERIAL="$(awk '{ print $1 }' <<<"${DEVICE_LINES[0]}")"
else
  echo "Multiple Android devices are online. Re-run with --serial SERIAL." >&2
  cat "$EVIDENCE_DIR/adb-devices.txt" >&2
  exit 1
fi

DEVICE_LINE="$(printf '%s\n' "${DEVICE_LINES[@]}" | awk -v serial="$SERIAL" '$1 == serial { print }')"
if [[ "$ALLOW_EMULATOR" -ne 1 ]] && { [[ "$SERIAL" == emulator-* ]] || [[ "$DEVICE_LINE" == *"device:emu"* ]]; }; then
  echo "Refusing emulator for physical-device proof: $SERIAL" >&2
  echo "Use --allow-emulator for emulator repro only." >&2
  exit 3
fi

{
  echo "serial=$SERIAL"
  adb -s "$SERIAL" shell getprop ro.product.model
  adb -s "$SERIAL" shell getprop ro.build.version.release
  adb -s "$SERIAL" shell getprop ro.build.version.sdk
  adb -s "$SERIAL" shell getprop ro.product.cpu.abilist
} > "$EVIDENCE_DIR/device-props.txt"

APK_PATH="$MOBILE_AGENT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$APK_PATH" ]]; then
  echo "Debug APK not found; building it first." | tee "$EVIDENCE_DIR/build-apk.log"
  (cd "$MOBILE_AGENT_DIR" && flutter build apk --debug --target lib/main.dart) 2>&1 | tee -a "$EVIDENCE_DIR/build-apk.log"
fi

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$APK_PATH" > "$EVIDENCE_DIR/apk-sha256.txt"
else
  sha256sum "$APK_PATH" > "$EVIDENCE_DIR/apk-sha256.txt"
fi
printf '%s\n' "$APK_PATH" > "$EVIDENCE_DIR/apk-path.txt"

adb -s "$SERIAL" logcat -c

set +e
(
  cd "$ANDROID_DIR"
  ANDROID_SERIAL="$SERIAL" ./gradlew \
    :app:connectedDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.mobilecode.app.LinuxSandboxRunnerInstrumentedTest \
    --rerun-tasks
) 2>&1 | tee "$EVIDENCE_DIR/gradle-connected-test.log"
GRADLE_EXIT=${PIPESTATUS[0]}
set -e

adb -s "$SERIAL" logcat -d | redact_sensitive > "$EVIDENCE_DIR/logcat.txt" || true
rg -n "MobileCodeLinuxProof|LinuxSandboxRunnerInstrumentedTest|apk_version|git_version|node_version|npm_version|package_install" \
  "$EVIDENCE_DIR/logcat.txt" > "$EVIDENCE_DIR/linux-sandbox-proof-lines.txt" || true

if [[ "$GRADLE_EXIT" -ne 0 ]]; then
  echo "Linux Sandbox Android proof failed. Evidence: $EVIDENCE_DIR" >&2
  exit "$GRADLE_EXIT"
fi

echo "Linux Sandbox Android proof passed."
echo "Evidence: $EVIDENCE_DIR"
