#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/post-commit scripts/capture_devlog_screenshot.sh

echo "MobileCode git hooks enabled: core.hooksPath=.githooks"
