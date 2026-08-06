#!/usr/bin/env python3
"""Fail when public mobile release workflows embed runtime credentials."""

from __future__ import annotations

import argparse
from pathlib import Path


PUBLIC_WORKFLOWS = (
    Path(".github/workflows/android-apk.yml"),
    Path(".github/workflows/mobile-app-release.yml"),
    Path(".github/workflows/ios-archive.yml"),
    Path(".github/workflows/ios-simulator.yml"),
)

FORBIDDEN_PATTERNS = (
    "MOBILECODE_MANAGED_API_KEY",
    "MOBILECODE_MANAGED_DEEPSEEK_API_KEY",
    "DEEPSEEK_API_KEY",
    "MOBILECODE_MANAGED_RELAY_TOKEN",
    "MOBILECODE_GITHUB_OAUTH_CLIENT_SECRET",
    "--dart-define-from-file",
)


def find_violations(path: Path, content: str) -> list[str]:
    violations: list[str] = []
    for line_number, line in enumerate(content.splitlines(), start=1):
        for pattern in FORBIDDEN_PATTERNS:
            if pattern in line:
                violations.append(f"{path}:{line_number}: forbidden public-build credential input: {pattern}")
                break
    return violations


def verify(root: Path, workflow_paths: tuple[Path, ...]) -> list[str]:
    violations: list[str] = []
    for relative_path in workflow_paths:
        path = root / relative_path
        if not path.is_file():
            violations.append(f"{relative_path}: required public release workflow is missing")
            continue
        violations.extend(find_violations(relative_path, path.read_text(encoding="utf-8")))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    workflow_paths = tuple(args.paths) if args.paths else PUBLIC_WORKFLOWS
    violations = verify(args.root.resolve(), workflow_paths)
    if violations:
        for violation in violations:
            print(violation)
        return 1
    print(f"public release workflow credential policy: OK ({len(workflow_paths)} workflows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
