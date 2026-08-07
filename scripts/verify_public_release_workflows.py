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

ANDROID_WORKFLOW = Path(".github/workflows/android-apk.yml")
COMBINED_WORKFLOW = Path(".github/workflows/mobile-app-release.yml")
APK_UPLOAD_STEP = "- name: Upload APK to GitHub Release"
MANUAL_ONLY_UPLOAD_CONDITION = (
    "if: ${{ github.event_name == 'workflow_dispatch' && "
    "github.event.inputs.upload_to_release != 'false' }}"
)


def find_violations(path: Path, content: str) -> list[str]:
    violations: list[str] = []
    for line_number, line in enumerate(content.splitlines(), start=1):
        for pattern in FORBIDDEN_PATTERNS:
            if pattern in line:
                violations.append(f"{path}:{line_number}: forbidden public-build credential input: {pattern}")
                break
    return violations


def find_apk_publisher_violations(contents: dict[Path, str]) -> list[str]:
    android = contents.get(ANDROID_WORKFLOW)
    combined = contents.get(COMBINED_WORKFLOW)
    if android is None or combined is None:
        return []

    violations: list[str] = []
    if APK_UPLOAD_STEP not in android:
        violations.append(
            f"{ANDROID_WORKFLOW}: dedicated tagged APK publisher is missing"
        )

    upload_start = combined.find(APK_UPLOAD_STEP)
    upload_end = combined.find("\n      - name:", upload_start + 1)
    upload_block = combined[upload_start:upload_end if upload_end >= 0 else None]
    if upload_start < 0 or MANUAL_ONLY_UPLOAD_CONDITION not in upload_block:
        violations.append(
            f"{COMBINED_WORKFLOW}: APK Release upload must be manual-only; "
            f"tagged APKs are published by {ANDROID_WORKFLOW}"
        )
    return violations


def verify(root: Path, workflow_paths: tuple[Path, ...]) -> list[str]:
    violations: list[str] = []
    contents: dict[Path, str] = {}
    for relative_path in workflow_paths:
        path = root / relative_path
        if not path.is_file():
            violations.append(f"{relative_path}: required public release workflow is missing")
            continue
        content = path.read_text(encoding="utf-8")
        contents[relative_path] = content
        violations.extend(find_violations(relative_path, content))
    violations.extend(find_apk_publisher_violations(contents))
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
