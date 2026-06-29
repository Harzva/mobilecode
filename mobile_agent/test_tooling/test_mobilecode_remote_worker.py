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
