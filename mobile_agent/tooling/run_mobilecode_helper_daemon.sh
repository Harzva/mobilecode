#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${MOBILECODE_WORKSPACE_ROOT:-$HOME/mobilecode_projects}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. In Termux run: pkg install -y python" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "warning: git is not installed. Repo Hub will use Remote-linked mode until you run: pkg install -y git" >&2
fi

exec python3 "$SCRIPT_DIR/mobilecode_helper_daemon.py" \
  --host "${MOBILECODE_HELPER_HOST:-127.0.0.1}" \
  --port "${MOBILECODE_HELPER_PORT:-8765}" \
  --workspace-root "$WORKSPACE_ROOT"
