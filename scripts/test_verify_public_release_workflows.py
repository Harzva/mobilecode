#!/usr/bin/env python3

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from verify_public_release_workflows import find_violations, verify


class PublicReleaseWorkflowPolicyTest(unittest.TestCase):
    def test_rejects_secret_reference_and_runtime_key_dart_define(self) -> None:
        content = "\n".join(
            (
                "TOKEN: ${{ secrets.MOBILECODE_MANAGED_API_KEY }}",
                'run: flutter build apk --dart-define=MOBILECODE_MANAGED_API_KEY="$TOKEN"',
            )
        )

        violations = find_violations(Path("release.yml"), content)

        self.assertEqual(2, len(violations))
        self.assertTrue(all("forbidden public-build credential input" in item for item in violations))

    def test_rejects_opaque_dart_define_files(self) -> None:
        content = "run: flutter build apk --dart-define-from-file=release.json"

        violations = find_violations(Path("release.yml"), content)

        self.assertEqual(1, len(violations))
        self.assertIn("--dart-define-from-file", violations[0])

    def test_allows_signing_secrets_and_public_configuration(self) -> None:
        content = "\n".join(
            (
                "KEYSTORE: ${{ secrets.MOBILECODE_RELEASE_KEYSTORE_BASE64 }}",
                "RELAY_URL: ${{ vars.MOBILECODE_MANAGED_RELAY_URL }}",
                "CLIENT_ID: ${{ vars.MOBILECODE_GITHUB_OAUTH_CLIENT_ID }}",
                "REDIRECT_URI: ${{ vars.MOBILECODE_GITHUB_OAUTH_REDIRECT_URI }}",
            )
        )

        self.assertEqual([], find_violations(Path("release.yml"), content))

    def test_missing_workflow_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            violations = verify(Path(temporary_directory), (Path("missing.yml"),))

        self.assertEqual(["missing.yml: required public release workflow is missing"], violations)


if __name__ == "__main__":
    unittest.main()
