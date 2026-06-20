#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

target="${1:-HEAD}"
short_sha="$(git rev-parse --short "$target" 2>/dev/null || printf '%s' "$target" | cut -c 1-12)"
shot_date="${MOBILECODE_DEVLOG_DATE:-$(date -u +%Y-%m-%d)}"
shot_dir="docs/devlog/screenshots"
shot_path="${shot_dir}/${shot_date}-${short_sha}.png"
shot_rel="${shot_path#docs/devlog/}"
strict="${MOBILECODE_DEVLOG_SCREENSHOT_STRICT:-0}"
skip_build="${MOBILECODE_DEVLOG_SKIP_BUILD:-0}"
port="${MOBILECODE_DEVLOG_PREVIEW_PORT:-}"

skip_or_fail() {
  message="$1"
  if [ "$strict" = "1" ]; then
    echo "$message" >&2
    exit 1
  fi
  echo "Skipping developer log screenshot: $message" >&2
  exit 0
}

find_chrome() {
  command -v google-chrome 2>/dev/null && return 0
  command -v chromium 2>/dev/null && return 0
  command -v chromium-browser 2>/dev/null && return 0
  if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
    printf '%s\n' "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    return 0
  fi
  if [ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]; then
    printf '%s\n' "/Applications/Chromium.app/Contents/MacOS/Chromium"
    return 0
  fi
  return 1
}

chrome_bin="$(find_chrome || true)"
if [ -z "$chrome_bin" ]; then
  skip_or_fail "Chrome/Chromium binary was not found."
fi

if [ -z "$port" ]; then
  port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
fi

if [ "$skip_build" != "1" ]; then
  command -v npm >/dev/null 2>&1 || skip_or_fail "npm is not installed."
  if [ ! -d app/node_modules ]; then
    if [ "${MOBILECODE_DEVLOG_INSTALL_DEPS:-0}" = "1" ]; then
      npm --prefix app ci
    else
      skip_or_fail "app/node_modules is missing. Run npm --prefix app ci or set MOBILECODE_DEVLOG_INSTALL_DEPS=1."
    fi
  fi
  npm --prefix app run build
fi

if [ ! -d app/dist ]; then
  skip_or_fail "app/dist is missing. Build the Pages app before capturing a screenshot."
fi

mkdir -p "$shot_dir" app/dist/devlog
rm -rf app/dist/devlog
mkdir -p app/dist/devlog
if [ -d docs/devlog ]; then
  cp -R docs/devlog/. app/dist/devlog/
fi

sync_devlog_to_dist() {
  MOBILECODE_DEVLOG_CURRENT_SCREENSHOT="$shot_rel" python3 scripts/generate_devlog.py --mode index
  rm -rf app/dist/devlog
  mkdir -p app/dist/devlog
  cp -R docs/devlog/. app/dist/devlog/
}

capture_once() {
  "$chrome_bin" \
    --headless=new \
    --disable-gpu \
    --no-sandbox \
    --window-size=1440,1400 \
    --screenshot="$shot_path" \
    "http://127.0.0.1:${port}/devlog/"
  cp "$shot_path" docs/devlog/screenshots/latest.png
}

python3 -m http.server "$port" --directory app/dist > /tmp/mobilecode-devlog-preview.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${port}/devlog/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "http://127.0.0.1:${port}/devlog/" >/dev/null || skip_or_fail "local devlog preview did not become reachable."

capture_once
sync_devlog_to_dist
capture_once
sync_devlog_to_dist

echo "Captured developer log screenshot: $shot_path"
