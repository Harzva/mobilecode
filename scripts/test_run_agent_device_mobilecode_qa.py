import argparse
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_agent_device_mobilecode_qa as qa


class AgentDeviceQaTest(unittest.TestCase):
    def test_plan_uses_platform_specific_device_selector(self) -> None:
        base = {
            "agent_device_bin": "agent-device",
            "app_id": "com.example.app",
            "app_binary": None,
            "session": "qa",
            "approve_artifacts": False,
            "sensitive_flow": False,
        }
        android = argparse.Namespace(**base, platform="android", device="serial-1")
        ios = argparse.Namespace(**base, platform="ios", device="iPhone QA")

        android_plan = dict(qa.build_plan(android, Path("screen.png")))
        ios_plan = dict(qa.build_plan(ios, Path("screen.png")))

        self.assertIn("--serial", android_plan["open"])
        self.assertNotIn("--device", android_plan["open"])
        self.assertIn("--device", ios_plan["open"])
        self.assertNotIn("--serial", ios_plan["open"])

    def test_sensitive_flow_rejects_artifact_capture(self) -> None:
        args = argparse.Namespace(
            sensitive_flow=True,
            approve_artifacts=True,
            approve_video=False,
            platform="android",
            dry_run=True,
            agent_device_bin="agent-device",
            app_binary=None,
        )
        with self.assertRaisesRegex(ValueError, "forbids screenshots"):
            qa._validate_args(args)

    def test_video_requires_explicit_artifact_approval(self) -> None:
        args = argparse.Namespace(
            sensitive_flow=False,
            approve_artifacts=False,
            approve_video=True,
            platform="ios",
            dry_run=True,
            agent_device_bin="agent-device",
            app_binary=None,
        )
        with self.assertRaisesRegex(ValueError, "requires --approve-artifacts"):
            qa._validate_args(args)

    def test_ios_capture_uses_system_volume_staging(self) -> None:
        with tempfile.TemporaryDirectory() as output_dir:
            output_path = Path(output_dir) / "screen.png"
            capture_path, staging = qa._capture_path(
                platform="ios",
                output_path=output_path,
                approved=True,
                sensitive_flow=False,
                dry_run=False,
            )
            self.assertIsNotNone(staging)
            self.assertNotEqual(capture_path.parent, output_path.parent)
            self.assertEqual(capture_path.name, output_path.name)
            assert staging is not None
            staging.cleanup()

    def test_android_capture_keeps_requested_output_path(self) -> None:
        output_path = Path("qa-output/screen.png")
        capture_path, staging = qa._capture_path(
            platform="android",
            output_path=output_path,
            approved=True,
            sensitive_flow=False,
            dry_run=False,
        )
        self.assertEqual(capture_path, output_path)
        self.assertIsNone(staging)

    def test_dry_run_manifest_contains_no_raw_identifier_or_secret(self) -> None:
        script = Path(__file__).with_name("run_agent_device_mobilecode_qa.py")
        with tempfile.TemporaryDirectory() as temp_dir:
            command = [
                sys.executable,
                str(script),
                "--platform",
                "android",
                "--app-id",
                "com.private.example",
                "--device",
                "device-private-123",
                "--output",
                temp_dir,
                "--dry-run",
                "--sensitive-flow",
            ]
            completed = subprocess.run(command, check=False, capture_output=True)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode())
            manifest = (Path(temp_dir) / "action-evidence.json").read_text()
            decoded = json.loads(manifest)

        self.assertNotIn("com.private.example", manifest)
        self.assertNotIn("device-private-123", manifest)
        self.assertFalse(decoded["redaction"]["rawStdoutStored"])
        self.assertFalse(decoded["redaction"]["credentialValuesStored"])
        self.assertEqual(decoded["artifacts"], [])
        self.assertTrue(decoded["steps"])
        for step in decoded["steps"]:
            self.assertTrue(step["evidenceId"].startswith("external-phone-use-"))
            self.assertIn(step["actionName"], {"phoneUseObserve", "phoneUseAct"})
            self.assertFalse(
                step["metadata"]["redaction"]["credentialValueStored"]
            )


if __name__ == "__main__":
    unittest.main()
