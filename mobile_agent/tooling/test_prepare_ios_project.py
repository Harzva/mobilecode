from __future__ import annotations

import plistlib
import tempfile
import unittest
from pathlib import Path

from prepare_ios_project import (
    MICROPHONE_USAGE,
    SPEECH_RECOGNITION_USAGE,
    prepare,
)


class PrepareIosProjectTest(unittest.TestCase):
    def test_usage_descriptions_are_written_to_root_dictionary(self) -> None:
        source = {
            'CFBundleURLTypes': [
                {
                    'CFBundleURLName': 'com.mobilecode.app',
                    'CFBundleURLSchemes': ['mobilecode'],
                    # A nested collision must not satisfy the top-level TCC contract.
                    'NSSpeechRecognitionUsageDescription': 'nested-invalid-value',
                },
            ],
            'CFBundleVersion': '63',
        }

        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / 'Info.plist'
            plist.write_bytes(
                plistlib.dumps(source, fmt=plistlib.FMT_XML, sort_keys=False)
            )

            prepare(plist)
            prepared = plistlib.loads(plist.read_bytes())

        self.assertEqual(prepared['NSMicrophoneUsageDescription'], MICROPHONE_USAGE)
        self.assertEqual(
            prepared['NSSpeechRecognitionUsageDescription'],
            SPEECH_RECOGNITION_USAGE,
        )
        self.assertEqual(
            prepared['CFBundleURLTypes'][0]['NSSpeechRecognitionUsageDescription'],
            'nested-invalid-value',
        )

    def test_prepare_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / 'Info.plist'
            plist.write_bytes(plistlib.dumps({'CFBundleName': 'MobileCode'}))

            prepare(plist)
            first = plist.read_bytes()
            prepare(plist)

            self.assertEqual(plist.read_bytes(), first)


if __name__ == '__main__':
    unittest.main()
