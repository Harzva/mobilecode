#!/usr/bin/env python3
"""Reject a MobileCode APK when package, UI, and published versions drift."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_SOURCE = ROOT / "mobile_agent/lib/core/mobilecode_version.dart"
PUBSPEC = ROOT / "mobile_agent/pubspec.yaml"
UPDATE_FEED = ROOT / "docs/mobilecode-update.json"
README = ROOT / "README.md"


def _match(pattern: str, value: str, label: str) -> str:
    result = re.search(pattern, value, re.MULTILINE)
    if result is None:
        raise ValueError(f"Could not read {label}.")
    return result.group(1)


def _version_tuple(path: Path) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"[0-9]+", path.parent.name))


def _find_aapt() -> Path:
    roots = [
        os.environ.get("ANDROID_HOME"),
        os.environ.get("ANDROID_SDK_ROOT"),
        str(Path.home() / "Library/Android/sdk"),
    ]
    candidates: list[Path] = []
    for root in roots:
        if not root:
            continue
        candidates.extend(Path(root).glob("build-tools/*/aapt"))
    if not candidates:
        raise ValueError("Android aapt was not found.")
    return max(candidates, key=_version_tuple)


def verify(apk: Path, expected_tag: str | None) -> None:
    version_source = VERSION_SOURCE.read_text(encoding="utf-8")
    semantic = _match(
        r"static const String semantic = '([^']+)';",
        version_source,
        "MobileCode semantic version",
    )
    build_number = int(
        _match(
            r"static const int buildNumber = ([0-9]+);",
            version_source,
            "MobileCode build number",
        )
    )
    tag = f"v{semantic}"
    release_url = f"https://github.com/Harzva/mobilecode/releases/tag/{tag}"

    if expected_tag is not None and expected_tag != tag:
        raise ValueError(f"Release tag {expected_tag!r} does not match {tag!r}.")

    pubspec = PUBSPEC.read_text(encoding="utf-8")
    package_version = _match(
        r"^version:\s*([^\s]+)$",
        pubspec,
        "pubspec version",
    )
    if package_version != f"{semantic}+{build_number}":
        raise ValueError(
            f"pubspec version {package_version!r} does not match "
            f"{semantic}+{build_number}."
        )

    feed = json.loads(UPDATE_FEED.read_text(encoding="utf-8"))
    expected_feed = {
        "latestVersion": tag,
        "latestBuildNumber": build_number,
        "releaseUrl": release_url,
        "downloadUrl": (
            "https://github.com/Harzva/mobilecode/releases/download/"
            f"{tag}/mobilecode-{tag}.apk"
        ),
    }
    for key, expected in expected_feed.items():
        if feed.get(key) != expected:
            raise ValueError(
                f"Update feed {key}={feed.get(key)!r} does not match {expected!r}."
            )

    readme = README.read_text(encoding="utf-8")
    expected_candidate_line = (
        f"Current candidate: `{tag}` (`{semantic}+{build_number}`)."
    )
    if expected_candidate_line not in readme:
        raise ValueError("README current candidate does not match the release version.")

    badging = subprocess.run(
        [str(_find_aapt()), "dump", "badging", str(apk)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    apk_version_name = _match(
        r"versionName='([^']+)'",
        badging,
        "APK versionName",
    )
    apk_version_code = int(
        _match(
            r"versionCode='([0-9]+)'",
            badging,
            "APK versionCode",
        )
    )
    if apk_version_name != semantic or apk_version_code != build_number:
        raise ValueError(
            "APK metadata does not match the MobileCode version source: "
            f"{apk_version_name}+{apk_version_code} != {semantic}+{build_number}."
        )

    with zipfile.ZipFile(apk) as archive:
        aot_entries = [
            name for name in archive.namelist() if name.endswith("/libapp.so")
        ]
        if not aot_entries:
            raise ValueError("APK does not contain a Flutter AOT libapp.so.")
        if not any(
            release_url.encode("utf-8") in archive.read(name)
            for name in aot_entries
        ):
            raise ValueError(
                "APK AOT payload does not contain the expected release URL; "
                "the Flutter build cache may be stale."
            )

    print(
        "MobileCode release version verified: "
        f"tag={tag} package={semantic}+{build_number} apk={apk}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--expected-tag")
    args = parser.parse_args()
    try:
        verify(args.apk.resolve(), args.expected_tag)
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Release version verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
