import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_phone_use_takeout_qa as qa


class PhoneUseTakeoutQaTest(unittest.TestCase):
    def test_generation_qualified_ref(self) -> None:
        snapshot = {
            "refsGeneration": 42,
            "interactiveNodes": [{"ref": "@e3", "label": "Search"}],
        }
        self.assertEqual(qa._ref(snapshot, "Search"), "@e3~s42")

    def test_manifest_redacts_identifiers_and_raw_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "action-evidence.json"
            qa._write_manifest(
                path,
                serial="private-emulator-serial",
                status="passed",
                steps=[],
                assertions=["zero_transaction_commit_attempts"],
                artifacts=[],
                failure_kind=None,
            )
            raw = path.read_text()
            decoded = json.loads(raw)

        self.assertNotIn("private-emulator-serial", raw)
        self.assertNotIn(qa.PACKAGE_NAME, raw)
        self.assertFalse(decoded["redaction"]["rawBridgeOutputStored"])
        self.assertFalse(decoded["redaction"]["typedValuesStored"])
        self.assertFalse(decoded["safety"]["realOrderCommitted"])
        self.assertTrue(decoded["safety"]["finalTransactionRequiresSeparateApproval"])

    def test_finalize_attaches_only_digests_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            qa._write_manifest(
                output / "action-evidence.json",
                serial="serial",
                status="passed",
                steps=[],
                assertions=[],
                artifacts=[],
                failure_kind=None,
            )
            (output / "phoneuse-takeout-sandbox.mp4").write_bytes(
                b"\x00\x00\x00\x18ftypisom" + b"\x00" * 64
            )
            (output / "phoneuse-takeout-sandbox.gesture-telemetry.json").write_text("{}")
            (output / "phoneuse-takeout-logcat.txt").write_text(
                "PhoneUseQaBridge action=tap_ref status=passed rawValues=false\n"
            )
            args = argparse.Namespace(output=str(output), approve_artifacts=True)
            self.assertEqual(qa.finalize_existing_artifacts(args), 0)
            decoded = json.loads((output / "action-evidence.json").read_text())

        self.assertEqual(len(decoded["artifacts"]), 3)
        for artifact in decoded["artifacts"]:
            self.assertIn("sha256", artifact)
            self.assertNotIn("path", artifact)
            self.assertFalse(artifact["shareableWithoutReview"])

    def test_finalize_requires_explicit_approval(self) -> None:
        args = argparse.Namespace(output="unused", approve_artifacts=False)
        with self.assertRaisesRegex(qa.QaFailure, "requires_approval"):
            qa.finalize_existing_artifacts(args)


if __name__ == "__main__":
    unittest.main()
