import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MOBILE_AGENT = Path(__file__).resolve().parents[1]
REPO_ROOT = MOBILE_AGENT.parent
WORKER = MOBILE_AGENT / "tooling" / "mobilecode_remote_worker.py"
FIXTURE = MOBILE_AGENT / "test" / "fixtures" / "harvis_mobilecode_handoff.project_check.json"
VALIDATE_FIXTURE = MOBILE_AGENT / "test" / "fixtures" / "harvis_mobilecode_handoff.validate.json"
PHONE_USE_FIXTURE = (
    MOBILE_AGENT / "test" / "fixtures" / "harvis_mobilecode_handoff.phone_use_emulator.json"
)
PHONE_USE_REAL_DEVICE_FIXTURE = (
    MOBILE_AGENT / "test" / "fixtures" / "harvis_mobilecode_handoff.phone_use_real_device.json"
)


class MobileCodeRemoteWorkerTest(unittest.TestCase):
    def test_once_processes_handoff_and_writes_ack_and_evidence_events(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            inbox.mkdir()
            shutil.copy(FIXTURE, inbox / "handoff.json")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertTrue(report["ok"])
            self.assertEqual(report["task_id"], "hm_task_project_check_001")
            self.assertEqual(len(list(processed.iterdir())), 1)
            self.assertEqual(list(failed.iterdir()), [])

            ack_events = sorted(outbox.glob("*.ack-event.json"))
            evidence_events = sorted(outbox.glob("*.action-evidence-event.json"))
            self.assertEqual(len(ack_events), 1)
            self.assertEqual(len(evidence_events), 1)

            ack = json.loads(ack_events[0].read_text(encoding="utf-8"))
            evidence = json.loads(evidence_events[0].read_text(encoding="utf-8"))
            ack_text = json.loads(ack["content"])["text"]
            evidence_text = json.loads(evidence["content"])["text"]

            self.assertIn('"type":"mobilecode.status.v1"', ack_text)
            self.assertIn('"state":"accepted"', ack_text)
            self.assertIn('"type":"mobilecode.action_evidence.v1"', evidence_text)
            self.assertIn('"status":"verified"', evidence_text)
            self.assertNotIn(str(Path.home()), evidence_text)

    def test_once_processes_validate_handoff(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-validate-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            inbox.mkdir()
            shutil.copy(VALIDATE_FIXTURE, inbox / "validate.json")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertTrue(report["ok"])
            self.assertEqual(report["task_id"], "hm_task_validate_001")
            self.assertEqual(report["action"], "validate")

            evidence_events = sorted(outbox.glob("*.action-evidence-event.json"))
            self.assertEqual(len(evidence_events), 1)
            evidence = json.loads(evidence_events[0].read_text(encoding="utf-8"))
            evidence_text = json.loads(evidence["content"])["text"]

            self.assertIn('"action":"validate"', evidence_text)
            self.assertIn('"status":"verified"', evidence_text)
            self.assertIn("valid JSON", evidence_text)

    def test_once_processes_phone_use_emulator_handoff(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-phone-use-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            fake_script = root / "fake_phone_use.py"
            fake_script.write_text(
                """#!/usr/bin/env python3
import json
import pathlib
import sys

args = sys.argv[1:]
output = pathlib.Path(args[args.index("--output") + 1])
text = args[args.index("--text") + 1]
output.mkdir(parents=True, exist_ok=True)
(output / "observe-after.png").write_bytes(b"png")
(output / "window-after.xml").write_text(f"<node text='{text}' />", encoding="utf-8")
(output / "summary.json").write_text(json.dumps({
    "schema": "harvis_mobilecode_phone_use_emulator_smoke.v1",
    "ok": True,
    "input_text": text,
    "checks": {
        "observe_before_ok": True,
        "tap_ok": True,
        "type_ok": True,
        "assert_ui_ok": True,
        "logcat_clean": True
    }
}, indent=2), encoding="utf-8")
""",
                encoding="utf-8",
            )
            fake_script.chmod(0o755)
            inbox.mkdir()
            shutil.copy(PHONE_USE_FIXTURE, inbox / "phone-use.json")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                    "--phone-use-script",
                    str(fake_script),
                    "--phone-use-skip-install",
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertTrue(report["ok"])
            self.assertEqual(report["task_id"], "hm_task_phone_use_emulator_001")
            self.assertEqual(report["action"], "phone_use_emulator")

            evidence_events = sorted(outbox.glob("*.action-evidence-event.json"))
            self.assertEqual(len(evidence_events), 1)
            evidence = json.loads(evidence_events[0].read_text(encoding="utf-8"))
            evidence_text = json.loads(evidence["content"])["text"]

            self.assertIn('"action":"phone_use_emulator"', evidence_text)
            self.assertIn('"status":"verified"', evidence_text)
            self.assertIn("phone_use_check:assert_ui_ok", evidence_text)

    def test_once_processes_phone_use_real_device_handoff(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-phone-use-real-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            fake_script = root / "fake_real_device_phone_use.py"
            fake_script.write_text(
                """#!/usr/bin/env python3
import json
import pathlib
import sys

args = sys.argv[1:]
output = pathlib.Path(args[args.index("--output") + 1])
text = args[args.index("--text") + 1]
output.mkdir(parents=True, exist_ok=True)
if "--allow-real-device" not in args:
    (output / "summary.json").write_text(json.dumps({
        "schema": "harvis_mobilecode_phone_use_real_device_smoke.v1",
        "ok": False,
        "blocked": True,
        "blocked_reason": "missing_allow_real_device"
    }, indent=2), encoding="utf-8")
    raise SystemExit(2)
(output / "observe-after.png").write_bytes(b"png")
(output / "window-after.xml").write_text(f"<node text='{text}' />", encoding="utf-8")
(output / "logcat.txt").write_text("", encoding="utf-8")
(output / "summary.json").write_text(json.dumps({
    "schema": "harvis_mobilecode_phone_use_real_device_smoke.v1",
    "ok": True,
    "input_text": text,
    "checks": {
        "install_ok": True,
        "launch_ok": True,
        "observe_before_ok": True,
        "tap_ok": True,
        "type_ok": True,
        "assert_ui_ok": True,
        "focus_ok": True,
        "logcat_clean": True
    }
}, indent=2), encoding="utf-8")
""",
                encoding="utf-8",
            )
            fake_script.chmod(0o755)
            inbox.mkdir()
            shutil.copy(PHONE_USE_REAL_DEVICE_FIXTURE, inbox / "phone-use-real.json")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                    "--phone-use-real-device-script",
                    str(fake_script),
                    "--phone-use-allow-real-device",
                    "--phone-use-skip-install",
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertTrue(report["ok"])
            self.assertEqual(report["task_id"], "hm_task_phone_use_real_device_001")
            self.assertEqual(report["action"], "phone_use_real_device")

            evidence_events = sorted(outbox.glob("*.action-evidence-event.json"))
            self.assertEqual(len(evidence_events), 1)
            evidence = json.loads(evidence_events[0].read_text(encoding="utf-8"))
            evidence_text = json.loads(evidence["content"])["text"]

            self.assertIn('"action":"phone_use_real_device"', evidence_text)
            self.assertIn('"status":"verified"', evidence_text)
            self.assertIn("phone_use_check:assert_ui_ok", evidence_text)

    def test_phone_use_real_device_handoff_blocks_without_worker_allow(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-phone-use-real-block-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            fake_script = root / "fake_real_device_phone_use_block.py"
            fake_script.write_text(
                """#!/usr/bin/env python3
import json
import pathlib
import sys

args = sys.argv[1:]
output = pathlib.Path(args[args.index("--output") + 1])
output.mkdir(parents=True, exist_ok=True)
(output / "summary.json").write_text(json.dumps({
    "schema": "harvis_mobilecode_phone_use_real_device_smoke.v1",
    "ok": False,
    "blocked": True,
    "blocked_reason": "missing_allow_real_device"
}, indent=2), encoding="utf-8")
raise SystemExit(2)
""",
                encoding="utf-8",
            )
            fake_script.chmod(0o755)
            inbox.mkdir()
            shutil.copy(PHONE_USE_REAL_DEVICE_FIXTURE, inbox / "phone-use-real.json")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                    "--phone-use-real-device-script",
                    str(fake_script),
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 1, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertFalse(report["ok"])
            self.assertEqual(report["action"], "phone_use_real_device")

            evidence_events = sorted(outbox.glob("*.action-evidence-event.json"))
            self.assertEqual(len(evidence_events), 1)
            evidence = json.loads(evidence_events[0].read_text(encoding="utf-8"))
            evidence_text = json.loads(evidence["content"])["text"]

            self.assertIn('"action":"phone_use_real_device"', evidence_text)
            self.assertIn('"status":"failed"', evidence_text)
            self.assertIn("missing_allow_real_device", evidence_text)

    def test_rejects_real_device_handoff_without_explicit_input_allow(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-real-bad-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            inbox.mkdir()
            payload = json.loads(PHONE_USE_REAL_DEVICE_FIXTURE.read_text(encoding="utf-8"))
            payload["task"]["input"].pop("allow_real_device")
            (inbox / "phone-use-real.json").write_text(json.dumps(payload), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertIn("task.input.allow_real_device", completed.stderr)
            self.assertEqual(len(list(failed.iterdir())), 1)
            self.assertFalse(list(outbox.glob("*.action-evidence-event.json")))

    def test_rejects_handoff_without_approval(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-worker-bad-") as raw:
            root = Path(raw)
            inbox = root / "inbox"
            outbox = root / "outbox"
            processed = root / "processed"
            failed = root / "failed"
            inbox.mkdir()
            payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
            payload["approval"].pop("approval_id")
            (inbox / "handoff.json").write_text(json.dumps(payload), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WORKER),
                    "--once",
                    "--inbox",
                    str(inbox),
                    "--outbox",
                    str(outbox),
                    "--processed-dir",
                    str(processed),
                    "--failed-dir",
                    str(failed),
                    "--workspace-root",
                    str(REPO_ROOT),
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertIn("approval.approval_id", completed.stderr)
            self.assertEqual(len(list(failed.iterdir())), 1)
            self.assertFalse(list(outbox.glob("*.action-evidence-event.json")))


if __name__ == "__main__":
    unittest.main()
