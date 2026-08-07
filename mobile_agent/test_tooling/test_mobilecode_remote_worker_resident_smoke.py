import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MOBILE_AGENT = Path(__file__).resolve().parents[1]
REPO_ROOT = MOBILE_AGENT.parent
SMOKE = MOBILE_AGENT / "tooling" / "mobilecode_remote_worker_resident_smoke.py"


class MobileCodeRemoteWorkerResidentSmokeTest(unittest.TestCase):
    def test_resident_smoke_processes_two_handoffs_in_one_worker_loop(self):
        with tempfile.TemporaryDirectory(prefix="mobilecode-resident-smoke-") as raw:
            output = Path(raw) / "evidence"

            completed = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE),
                    "--workspace-root",
                    str(REPO_ROOT),
                    "--output",
                    str(output),
                    "--timeout",
                    "10",
                    "--poll-interval",
                    "0.1",
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
            self.assertTrue(summary["ok"])
            checks = summary["checks"]
            self.assertTrue(checks["worker_started"])
            self.assertTrue(checks["worker_continued_after_first_handoff"])
            self.assertTrue(checks["project_check_verified"])
            self.assertTrue(checks["validate_verified"])
            self.assertTrue(checks["two_evidence_payloads"])
            self.assertTrue(checks["no_duplicate_action_evidence"])
            self.assertTrue(checks["two_processed_files"])
            self.assertTrue(checks["failed_dir_empty"])


if __name__ == "__main__":
    unittest.main()
