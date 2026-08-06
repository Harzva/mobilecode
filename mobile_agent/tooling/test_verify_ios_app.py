from __future__ import annotations

import plistlib
import tempfile
import unittest
from pathlib import Path

from verify_ios_app import verify


class VerifyIosAppTest(unittest.TestCase):
    def _app(self, directory: Path) -> Path:
        app = directory / 'Runner.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(
            plistlib.dumps(
                {
                    'CFBundleShortVersionString': '0.1.73',
                    'CFBundleVersion': '63',
                    'NSMicrophoneUsageDescription': 'Microphone prompt',
                    'NSSpeechRecognitionUsageDescription': 'Speech prompt',
                }
            )
        )
        return app

    def test_valid_bundle_and_clean_log_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            app = self._app(directory)
            log = directory / 'runner.log'
            log.write_text('Runner launched normally.', encoding='utf-8')

            verify(app, 'v0.1.73', log)

    def test_nested_usage_description_does_not_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            app = self._app(directory)
            document = plistlib.loads((app / 'Info.plist').read_bytes())
            del document['NSSpeechRecognitionUsageDescription']
            document['CFBundleURLTypes'] = [
                {'NSSpeechRecognitionUsageDescription': 'nested-invalid-value'}
            ]
            (app / 'Info.plist').write_bytes(plistlib.dumps(document))

            with self.assertRaisesRegex(ValueError, 'top-level'):
                verify(app, 'v0.1.73', None)

    def test_privacy_crash_signature_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            app = self._app(directory)
            log = directory / 'runner.log'
            log.write_text(
                'This app has crashed because it attempted to access '
                'privacy-sensitive data without a usage description.',
                encoding='utf-8',
            )

            with self.assertRaisesRegex(ValueError, 'crash signature'):
                verify(app, 'v0.1.73', log)


if __name__ == '__main__':
    unittest.main()
