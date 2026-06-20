#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/qa_mobilecode_html_real_device.sh <command> [label]

Environment:
  ANDROID_SERIAL   Optional adb serial when more than one device is connected.
  QA_DIR           Output folder. Default: mobile_agent/qa-output/html-open-real-device-<timestamp>

Commands:
  init             Record device/app state and push a sample HTML file to Downloads.
  capture <label> Capture screenshot, UI XML, and logcat with a stable label.
  packages         Record relevant package availability again.

Typical flow:
  QA_DIR=mobile_agent/qa-output/html-open-real-device-$(date +%Y%m%d-%H%M%S) \
    scripts/qa_mobilecode_html_real_device.sh init

  # Perform one manual step on the phone, then capture evidence:
  QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 01-files-resolver
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
qa_dir="${QA_DIR:-$repo_root/mobile_agent/qa-output/html-open-real-device-$timestamp}"
adb_base=(adb)
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  adb_base+=( -s "$ANDROID_SERIAL" )
fi

adb_cmd() {
  "${adb_base[@]}" "$@"
}

ensure_device() {
  local devices
  devices="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    if ! grep -qx "$ANDROID_SERIAL" <<<"$devices"; then
      echo "ANDROID_SERIAL=$ANDROID_SERIAL is not an online adb device." >&2
      exit 2
    fi
    return
  fi
  local count
  count="$(grep -c . <<<"$devices" || true)"
  if [[ "$count" -ne 1 ]]; then
    echo "Expected exactly one adb device, found $count. Set ANDROID_SERIAL." >&2
    adb devices -l >&2
    exit 2
  fi
}

write_packages() {
  mkdir -p "$qa_dir"
  adb_cmd shell pm list packages > "$qa_dir/packages-all.txt"
  {
    echo "# Relevant Android packages"
    echo
    echo "MobileCode:"
    grep -E 'mobilecode|mobile_agent' "$qa_dir/packages-all.txt" || true
    echo
    echo "DocumentsUI / Files:"
    grep -E 'documentsui|file' "$qa_dir/packages-all.txt" || true
    echo
    echo "Chrome / browser:"
    grep -E 'chrome|browser|webview' "$qa_dir/packages-all.txt" || true
    echo
    echo "WeChat / Tencent:"
    grep -E 'tencent|wechat|micromsg|mm' "$qa_dir/packages-all.txt" || true
  } > "$qa_dir/packages-relevant.md"
}

init_run() {
  ensure_device
  mkdir -p "$qa_dir"
  adb devices -l > "$qa_dir/adb-devices.txt"
  adb_cmd shell getprop ro.build.version.sdk > "$qa_dir/device-sdk.txt"
  adb_cmd shell getprop ro.product.model > "$qa_dir/device-model.txt"
  adb_cmd shell getprop ro.product.manufacturer > "$qa_dir/device-manufacturer.txt"
  write_packages

  local tmp_html
  tmp_html="$(mktemp "${TMPDIR:-/tmp}/mobilecode-html-qa.XXXXXX.html")"
  cat > "$tmp_html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>MobileCode Real Device HTML QA</title>
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #0f172a; color: #f8fafc; }
    main { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
    section { max-width: 560px; border: 1px solid #38bdf8; border-radius: 8px; padding: 22px; background: #111827; }
    h1 { margin: 0 0 12px; font-size: 30px; }
    p { line-height: 1.5; color: #cbd5e1; }
    code { color: #86efac; }
  </style>
</head>
<body>
  <main>
    <section>
      <h1>MobileCode HTML Open QA</h1>
      <p>This page verifies third-party Android file/open/share routing into MobileCode.</p>
      <p>Expected marker: <code>mobilecode-real-device-html-open</code></p>
    </section>
  </main>
</body>
</html>
HTML
  adb_cmd push "$tmp_html" /sdcard/Download/mobilecode-real-device-html-open.html > "$qa_dir/push-sample-html.txt"
  rm -f "$tmp_html"
  cat > "$qa_dir/README.md" <<EOF
# MobileCode HTML Real Device QA

Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Sample file:

- /sdcard/Download/mobilecode-real-device-html-open.html

Use docs/mobilecode-third-party-html-qa.md for the manual test sequence.
EOF
  echo "$qa_dir"
}

capture() {
  ensure_device
  local label="${1:-}"
  if [[ -z "$label" ]]; then
    echo "capture requires a label." >&2
    usage >&2
    exit 2
  fi
  mkdir -p "$qa_dir"
  adb_cmd exec-out screencap -p > "$qa_dir/$label.png"
  adb_cmd shell uiautomator dump /sdcard/window.xml > "$qa_dir/$label-uiautomator.txt" 2>&1 || true
  adb_cmd pull /sdcard/window.xml "$qa_dir/$label.xml" > "$qa_dir/$label-pull-window.txt" 2>&1 || true
  adb_cmd logcat -d -t 1000 > "$qa_dir/$label-logcat.txt" 2>&1 || true
  echo "$qa_dir/$label.png"
}

command="${1:-}"
case "$command" in
  init)
    init_run
    ;;
  capture)
    capture "${2:-}"
    ;;
  packages)
    ensure_device
    write_packages
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 2
    ;;
esac
