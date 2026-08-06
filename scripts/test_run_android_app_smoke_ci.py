#!/usr/bin/env python3

from pathlib import Path
import re
import unittest


SCRIPT = Path(__file__).with_name("run_android_app_smoke_ci.sh")
WORKFLOW = SCRIPT.parents[1] / ".github/workflows/android-app-test.yml"


class AndroidAppSmokeContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = SCRIPT.read_text(encoding="utf-8")
        cls.workflow_source = WORKFLOW.read_text(encoding="utf-8")

    def test_workflow_requires_read_write_kvm_access(self) -> None:
        self.assertIn("test -e /dev/kvm", self.workflow_source)
        self.assertIn("sudo chmod 0666 /dev/kvm", self.workflow_source)
        self.assertIn("test -r /dev/kvm", self.workflow_source)
        self.assertIn("test -w /dev/kvm", self.workflow_source)

    def test_system_ui_anr_is_diagnostic_only(self) -> None:
        block = re.search(
            r'if grep -q "System UI isn\'t responding".*?\n\s*fi',
            self.source,
            re.DOTALL,
        )

        self.assertIsNotNone(block)
        assert block is not None
        self.assertNotIn("exit 1", block.group(0))
        self.assertIn("non-blocking CI infrastructure evidence", block.group(0))

    def test_permission_controller_overlay_still_fails_closed(self) -> None:
        block = re.search(
            r"if grep -q 'package=\"com\.android\.permissioncontroller\"'.*?\n\s*fi",
            self.source,
            re.DOTALL,
        )

        self.assertIsNotNone(block)
        assert block is not None
        self.assertIn("exit 1", block.group(0))


if __name__ == "__main__":
    unittest.main()
