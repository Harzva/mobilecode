#!/usr/bin/env python3
"""Verify an iOS app bundle and reject known launch-crash signatures."""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path


VERSION_SOURCE = Path(__file__).resolve().parents[1] / 'lib/core/mobilecode_version.dart'
REQUIRED_USAGE_DESCRIPTIONS = (
    'NSMicrophoneUsageDescription',
    'NSSpeechRecognitionUsageDescription',
)
CRASH_PATTERN = re.compile(
    r'(?:'
    r'Terminating app due to uncaught exception|'
    r'Fatal error|'
    r'EXC_CRASH|'
    r'SIGABRT|'
    r'This app has crashed because it attempted to access privacy-sensitive data|'
    r'privacy-sensitive data without a usage description|'
    r'Info\.plist must contain an NS(?:Microphone|SpeechRecognition)UsageDescription'
    r')',
    re.IGNORECASE,
)


def _read_version() -> tuple[str, str]:
    source = VERSION_SOURCE.read_text(encoding='utf-8')
    semantic_match = re.search(
        r"static const String semantic = '([^']+)';",
        source,
    )
    build_match = re.search(
        r'static const int buildNumber = ([0-9]+);',
        source,
    )
    if semantic_match is None or build_match is None:
        raise ValueError('Could not read MobileCode version source.')
    return semantic_match.group(1), build_match.group(1)


def verify(app: Path, expected_tag: str | None, log: Path | None) -> None:
    plist_path = app / 'Info.plist'
    document = plistlib.loads(plist_path.read_bytes())
    if not isinstance(document, dict):
        raise ValueError(f'Expected a dictionary at the root of {plist_path}.')

    semantic, build = _read_version()
    tag = f'v{semantic}'
    if expected_tag is not None and expected_tag != tag:
        raise ValueError(f'Release tag {expected_tag!r} does not match {tag!r}.')

    short_version = str(document.get('CFBundleShortVersionString', ''))
    build_version = str(document.get('CFBundleVersion', ''))
    if (short_version, build_version) != (semantic, build):
        raise ValueError(
            'iOS bundle version does not match the MobileCode version source: '
            f'{short_version}+{build_version} != {semantic}+{build}.'
        )

    for key in REQUIRED_USAGE_DESCRIPTIONS:
        value = document.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f'iOS bundle is missing top-level {key}.')

    if log is not None:
        log_text = log.read_text(encoding='utf-8', errors='replace')
        match = CRASH_PATTERN.search(log_text)
        if match is not None:
            raise ValueError(
                f'iOS launch log contains crash signature: {match.group(0)}.'
            )

    print(
        'MobileCode iOS app verified: '
        f'tag={tag} bundle={short_version}+{build_version} app={app}'
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--expected-tag')
    parser.add_argument('--log', type=Path)
    args = parser.parse_args()
    try:
        verify(args.app.resolve(), args.expected_tag, args.log)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f'iOS app verification failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
