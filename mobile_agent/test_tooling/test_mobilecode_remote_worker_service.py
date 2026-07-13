import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MOBILE_AGENT = Path(__file__).resolve().parents[1]
REPO_ROOT = MOBILE_AGENT.parent
SERVICE = MOBILE_AGENT / "tooling" / "mobilecode_remote_worker_service.py"


class MobileCodeRemoteWorkerServiceTest(unittest.TestCase):
    def test_render_plist_builds_resident_worker_without_real_device_allow_by_default(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-service-") as raw:
            root = Path(raw)
            plist = root / "worker.plist"

            completed = subprocess.run(
                [
                    sys.executable,
                    str(SERVICE),
                    "render-plist",
                    "--plist-path",
                    str(plist),
                    "--workspace-root",
                    str(REPO_ROOT),
                    "--poll-interval",
                    "1.5",
                    "--route",
                    "--lark-relay-bin",
                    "/tmp/lark-relay",
                    "--relay-config",
                    str(root / "relay.json"),
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertTrue(report["ok"])
            self.assertEqual(report["action"], "render-plist")

            decoded = plistlib.loads(plist.read_bytes())
            program_args = decoded["ProgramArguments"]

            self.assertEqual(decoded["Label"], "com.mobilecode.harvis.remote-worker")
            self.assertTrue(decoded["RunAtLoad"])
            self.assertTrue(decoded["KeepAlive"])
            self.assertEqual(decoded["WorkingDirectory"], str(REPO_ROOT))
            self.assertIn(str(MOBILE_AGENT / "tooling" / "mobilecode_remote_worker.py"), program_args)
            self.assertIn("--route", program_args)
            self.assertIn("--poll-interval", program_args)
            self.assertIn("1.5", program_args)
            self.assertNotIn("--once", program_args)
            self.assertNotIn("--phone-use-allow-real-device", program_args)

    def test_render_plist_only_includes_real_device_allow_when_explicit(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-service-allow-") as raw:
            root = Path(raw)
            plist = root / "worker.plist"

            completed = subprocess.run(
                [
                    sys.executable,
                    str(SERVICE),
                    "render-plist",
                    "--plist-path",
                    str(plist),
                    "--workspace-root",
                    str(REPO_ROOT),
                    "--phone-use-allow-real-device",
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            decoded = plistlib.loads(plist.read_bytes())
            self.assertIn("--phone-use-allow-real-device", decoded["ProgramArguments"])


if __name__ == "__main__":
    unittest.main()
