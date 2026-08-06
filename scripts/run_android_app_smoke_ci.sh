#!/bin/sh

set -eux

ARTIFACTS_DIR="artifacts"
PACKAGE_NAME="com.mobilecode.app"
HELPER_TOKEN="ci-helper-token"
HELPER_URL="http://127.0.0.1:18765"

mkdir -p "$ARTIFACTS_DIR"

collect_evidence() {
  adb shell pidof "$PACKAGE_NAME" > "$ARTIFACTS_DIR/app-pid.txt" 2>/dev/null || true
  adb shell dumpsys window windows > "$ARTIFACTS_DIR/window-focus.txt" 2>/dev/null || true
  adb shell dumpsys activity services "$PACKAGE_NAME" > "$ARTIFACTS_DIR/helper-services.txt" 2>/dev/null || true
  adb exec-out screencap -p > "$ARTIFACTS_DIR/mobilecode-android-smoke.png" 2>/dev/null || true
  adb logcat -d -t 2000 > "$ARTIFACTS_DIR/android-logcat.txt" 2>/dev/null || true
}

trap collect_evidence EXIT

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 || true

installed=0
for _ in 1 2 3; do
  if timeout 120s adb install -r mobile_agent/build/app/outputs/flutter-apk/app-pure-debug.apk; then
    installed=1
    break
  fi
  adb kill-server
  adb start-server
  adb wait-for-device
  sleep 20
done
test "$installed" = 1

adb shell am force-stop "$PACKAGE_NAME"
adb shell pm grant "$PACKAGE_NAME" android.permission.RECORD_AUDIO
adb forward --remove tcp:18765 || true
adb forward tcp:18765 tcp:8765

helper_ready=0
for _ in $(seq 1 12); do
  timeout 5s adb shell am start \
    -n "$PACKAGE_NAME/.MobileCodeHelperLauncherActivity" \
    --es mobilecode_helper_auth_token "$HELPER_TOKEN" \
    > "$ARTIFACTS_DIR/helper-launch.txt" 2>&1 || true
  if curl --connect-timeout 2 --max-time 5 -fsS \
    -H "X-MobileCode-Token: $HELPER_TOKEN" \
    "$HELPER_URL/v1/health" \
    > "$ARTIFACTS_DIR/android-helper-health.json"; then
    helper_ready=1
    break
  fi
  sleep 1
done

if [ "$helper_ready" != 1 ]; then
  cat "$ARTIFACTS_DIR/helper-launch.txt" || true
  collect_evidence
  grep -E 'MobileCodeHelper|AndroidRuntime' "$ARTIFACTS_DIR/android-logcat.txt" | tail -n 200 || true
  exit 1
fi

curl -fsS \
  -H "X-MobileCode-Token: $HELPER_TOKEN" \
  "$HELPER_URL/v1/health" \
  | tee "$ARTIFACTS_DIR/android-helper-health.json"
test "$(curl -sS -o /dev/null -w '%{http_code}' -H 'X-MobileCode-Token: wrong-token' "$HELPER_URL/v1/health")" = 401
curl -fsS \
  -H "X-MobileCode-Token: $HELPER_TOKEN" \
  -H 'Content-Type: application/json' \
  -X POST "$HELPER_URL/v1/execute" \
  -d '{"command":"pwd","timeoutMs":10000}' \
  | tee "$ARTIFACTS_DIR/android-helper-execute.json"
curl -fsS \
  -H "X-MobileCode-Token: $HELPER_TOKEN" \
  "$HELPER_URL/v1/tasks/current" \
  | tee "$ARTIFACTS_DIR/android-helper-task.json"

grep '"name":"MobileCode Helper Service"' "$ARTIFACTS_DIR/android-helper-health.json"
grep '"ready":true' "$ARTIFACTS_DIR/android-helper-health.json"
grep '"authRequired":true' "$ARTIFACTS_DIR/android-helper-health.json"
grep '"backgroundService":true' "$ARTIFACTS_DIR/android-helper-health.json"
grep '"exitCode":0' "$ARTIFACTS_DIR/android-helper-execute.json"
grep '"failureKind":"none"' "$ARTIFACTS_DIR/android-helper-execute.json"

adb logcat -c || true
timeout 30s adb shell am start -W -n "$PACKAGE_NAME/.MainActivity" \
  | tee "$ARTIFACTS_DIR/main-start.txt"

app_drawn=0
for _ in $(seq 1 48); do
  adb shell pidof "$PACKAGE_NAME" > "$ARTIFACTS_DIR/app-pid.txt" || true
  adb shell dumpsys window windows > "$ARTIFACTS_DIR/window-focus.txt" || true
  if awk '/Window #[0-9]+/ { in_app = ($0 ~ /com\.mobilecode\.app\/.*MainActivity/) } in_app && /Surface: shown=true/ { ok=1 } END { exit ok ? 0 : 1 }' "$ARTIFACTS_DIR/window-focus.txt"; then
    app_drawn=1
    break
  fi
  sleep 5
done

printf '%s\n' "$app_drawn" > "$ARTIFACTS_DIR/app-drawn.txt"
test "$app_drawn" = 1
collect_evidence
test -s "$ARTIFACTS_DIR/app-pid.txt"
test -s "$ARTIFACTS_DIR/mobilecode-android-smoke.png"
grep -q "$PACKAGE_NAME" "$ARTIFACTS_DIR/window-focus.txt"
if grep -E "FATAL EXCEPTION|E AndroidRuntime|NoSuchMethodError|MissingPluginException|ANR in $PACKAGE_NAME" "$ARTIFACTS_DIR/android-logcat.txt"; then
  exit 1
fi

# Flutter can draw a healthy surface while uiautomator is unavailable on a
# slow software-emulated API 29 runner. Keep the hierarchy as best-effort
# evidence; the hard gate is drawn surface + live process + screenshot + clean
# fatal log scan above.
timeout 30s adb shell uiautomator dump /sdcard/mobilecode-window.xml >/dev/null 2>&1 || true
adb pull /sdcard/mobilecode-window.xml "$ARTIFACTS_DIR/window-hierarchy.xml" >/dev/null 2>&1 || true
if [ -s "$ARTIFACTS_DIR/window-hierarchy.xml" ]; then
  if grep -q "System UI isn't responding" "$ARTIFACTS_DIR/window-hierarchy.xml"; then
    exit 1
  fi
  if grep -q 'package="com.android.permissioncontroller"' "$ARTIFACTS_DIR/window-hierarchy.xml"; then
    exit 1
  fi
fi
