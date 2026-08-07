import argparse
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_mobilecore_dual_app_qa as qa


class MobileCoreDualAppQaTest(unittest.TestCase):
    def test_strict_physical_lane_requires_every_counted_gate(self) -> None:
        args = argparse.Namespace(
            require_physical_device=True,
            require_model_switch=False,
            require_background_recovery=False,
            require_thermal=False,
            thermal_duration_seconds=1,
        )

        errors = qa.physical_acceptance_errors(args)

        self.assertIn(
            "--require-physical-device requires --require-model-switch",
            errors,
        )
        self.assertIn(
            "--require-physical-device requires --require-background-recovery",
            errors,
        )
        self.assertIn(
            "--require-physical-device requires --require-thermal",
            errors,
        )
        self.assertIn(
            "--require-physical-device requires --thermal-duration-seconds >= 900",
            errors,
        )

        args.require_model_switch = True
        args.require_background_recovery = True
        args.require_thermal = True
        args.thermal_duration_seconds = 900
        self.assertEqual(qa.physical_acceptance_errors(args), [])

    def test_airplane_mode_must_be_observed_and_restored(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=False,
                require_physical_device=True,
                require_background_recovery=False,
                adb="adb",
                serial="private-device-id",
            )
            runner = qa.QaRunner(args)
            state = b"0"

            def adb(_name, *arguments, **_kwargs):
                nonlocal state
                if "airplane-mode" in arguments:
                    state = b"1" if arguments[-1] == "enable" else b"0"
                return subprocess.CompletedProcess([], 0, state + b"\n", b"")

            runner.adb = adb
            runner.set_airplane_mode(True, phase="controlled_tasks")
            runner.set_airplane_mode(False, phase="controlled_tasks")

        self.assertEqual(runner.offline_isolation_summary["status"], "passed")
        phase = runner.offline_isolation_summary["phases"]["controlled_tasks"]
        self.assertTrue(phase["enabledObserved"])
        self.assertTrue(phase["restoredObserved"])
        self.assertTrue(
            qa.offline_phase_passed(
                runner.offline_isolation_summary,
                "controlled_tasks",
            )
        )

    def test_airplane_mode_rejects_a_state_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=False,
                require_physical_device=True,
                require_background_recovery=False,
                adb="adb",
                serial="private-device-id",
            )
            runner = qa.QaRunner(args)
            runner.adb = lambda *_args, **_kwargs: subprocess.CompletedProcess(
                [], 0, b"0\n", b""
            )

            with self.assertRaisesRegex(RuntimeError, "airplane mode"):
                runner.set_airplane_mode(True, phase="controlled_tasks")

        self.assertEqual(runner.offline_isolation_summary["status"], "failed")
        self.assertFalse(
            qa.offline_phase_passed(
                runner.offline_isolation_summary,
                "controlled_tasks",
            )
        )

    def test_environment_classification_uses_android_properties(self) -> None:
        self.assertEqual(
            qa.classify_android_environment(
                serial="usb-device-1",
                kernel_qemu="1",
                boot_qemu="",
                hardware="ranchu",
                model="sdk_gphone64_arm64",
            ),
            "emulator",
        )
        self.assertEqual(
            qa.classify_android_environment(
                serial="R58-private",
                kernel_qemu="",
                boot_qemu="",
                hardware="qcom",
                model="Physical phone",
            ),
            "physical_device",
        )

    def test_recursive_evidence_sanitizer_omits_payloads_and_paths(self) -> None:
        sanitized = qa.sanitize_evidence_value(
            {
                "capabilities": {"image_input": True, "audio_input": False},
                "nested": {
                    "messages": [{"content": "private prompt"}],
                    "token": "secret",
                    "access_token": "secret-2",
                    "file_name": "private-model.gguf",
                    "summary": "loaded=/Users/private/model.gguf",
                },
            }
        )

        self.assertEqual(
            sanitized["capabilities"],
            {"image_input": True, "audio_input": False},
        )
        self.assertNotIn("messages", sanitized["nested"])
        self.assertNotIn("token", sanitized["nested"])
        self.assertNotIn("access_token", sanitized["nested"])
        self.assertNotIn("file_name", sanitized["nested"])
        self.assertNotIn("/Users/private", sanitized["nested"]["summary"])
        self.assertIn("<local-path-omitted>", sanitized["nested"]["summary"])

    def test_pressure_parsers_return_safe_numeric_telemetry(self) -> None:
        thermal = """
Thermal Status: 2
Temperature{mValue=39.5, mType=2, mName=battery, mStatus=1}
Temperature{mValue=42.25, mType=3, mName=skin, mStatus=2}
"""
        battery = """
  level: 70
  temperature: 387
"""

        self.assertEqual(qa.parse_battery_temperature_c(battery), 38.7)
        self.assertEqual(qa.parse_thermal_service(thermal), (2, 42.25, 2))

    def test_app_op_parser_returns_only_public_mode(self) -> None:
        raw = """
RUN_IN_BACKGROUND: allow; time=+10s ago
RUN_ANY_IN_BACKGROUND: ignore
"""
        self.assertEqual(
            qa.parse_app_op_mode(raw, "RUN_IN_BACKGROUND"),
            "allow",
        )
        self.assertEqual(
            qa.parse_app_op_mode(raw, "RUN_ANY_IN_BACKGROUND"),
            "ignore",
        )
        self.assertIsNone(qa.parse_app_op_mode("No operations.", "RUN_IN_BACKGROUND"))

    def test_apksigner_parser_normalizes_public_certificate_fingerprint(self) -> None:
        fingerprint = "ab" * 32
        raw = f"Signer #1 certificate SHA-256 digest: {fingerprint}\n"
        self.assertEqual(
            qa.parse_apksigner_certificate_sha256(raw),
            fingerprint,
        )
        self.assertEqual(
            qa.normalize_certificate_sha256(":".join(["ab"] * 32)),
            fingerprint,
        )
        with self.assertRaises(ValueError):
            qa.normalize_certificate_sha256("too-short")

    def test_instrumentation_result_parser_rejects_junit_failure_with_zero_exit(self) -> None:
        failed = b"""
INSTRUMENTATION_STATUS_CODE: -2
FAILURES!!!
Tests run: 1, Failures: 1
INSTRUMENTATION_CODE: -1
"""
        passed = b"""
Time: 0.2

OK (1 test)

INSTRUMENTATION_CODE: -1
"""

        self.assertFalse(
            qa.instrumentation_succeeded(returncode=0, stdout=failed, stderr=b"")
        )
        self.assertTrue(
            qa.instrumentation_succeeded(returncode=0, stdout=passed, stderr=b"")
        )
        self.assertFalse(
            qa.instrumentation_succeeded(returncode=1, stdout=passed, stderr=b"")
        )
        self.assertFalse(
            qa.instrumentation_succeeded(
                returncode=0,
                stdout=b"OK (0 tests)\nINSTRUMENTATION_CODE: -1\n",
                stderr=b"",
            )
        )

    def test_multimodal_lane_runs_every_advertised_cross_app_capability(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=False,
                require_image_multimodal=False,
                require_audio_multimodal=False,
                require_verified_omni=False,
                task_timeout=30,
            )
            runner = qa.QaRunner(args)
            health = {
                "capabilities": {
                    "image_input": True,
                    "audio_input": True,
                },
                "audio_sample_rate_hz": 16_000,
                "artifacts": {
                    "main": {"verified": True},
                    "mmproj": {"verified": True},
                },
            }
            runner.wait_for_health = lambda **_kwargs: health
            calls = []

            def instrumentation(name, test_name, **_kwargs):
                calls.append((name, test_name))
                return subprocess.CompletedProcess([], 0, b"", b"")

            runner.instrumentation = instrumentation
            runner.exercise_multimodal_cross_app_tasks()
            raw = (Path(directory) / "multimodal_summary.json").read_text()

        self.assertEqual(runner.multimodal_summary["status"], "passed")
        self.assertEqual(runner.multimodal_summary["image"], "passed")
        self.assertEqual(runner.multimodal_summary["audio"], "passed")
        self.assertEqual(len(calls), 2)
        self.assertEqual(qa.CROSS_APP_IMAGE_TEST, calls[0][1])
        self.assertEqual(qa.CROSS_APP_AUDIO_TEST, calls[1][1])
        self.assertNotIn("messages", raw)
        self.assertNotIn("input_audio", raw)
        self.assertNotIn("data:image", raw)

    def test_verified_omni_gate_rejects_unverified_artifacts_before_media(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=False,
                require_image_multimodal=False,
                require_audio_multimodal=False,
                require_verified_omni=True,
                task_timeout=30,
            )
            runner = qa.QaRunner(args)
            health = {
                "capabilities": {
                    "image_input": True,
                    "audio_input": True,
                },
                "audio_sample_rate_hz": 16_000,
                "artifacts": {
                    "main": {"verified": False},
                    "mmproj": {"verified": False},
                },
            }
            runner.wait_for_health = lambda **_kwargs: health
            runner.instrumentation = lambda *_args, **_kwargs: self.fail(
                "instrumentation must not run before artifact verification"
            )

            with self.assertRaisesRegex(RuntimeError, "Verified Omni artifacts"):
                runner.exercise_multimodal_cross_app_tasks()

        self.assertEqual(runner.multimodal_summary["status"], "failed")
        self.assertFalse(
            runner.multimodal_summary["artifactVerification"]["pairVerified"]
        )

    def test_v2_manifest_hashes_identifiers_and_omits_model_filename(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk_paths = []
            for name in ("mobilecore.apk", "mobilecode.apk", "mobilecode-test.apk"):
                path = root / name
                path.write_bytes(name.encode("utf-8"))
                apk_paths.append(path)
            model = root / "private-client-model-name.gguf"
            model.write_bytes(b"model")
            output = root / "evidence"
            args = argparse.Namespace(
                output_dir=output,
                forward_port=18080,
                require_thermal=True,
                require_physical_device=True,
                require_model_switch=True,
                serial="private-physical-serial",
                mobilecore_apk=apk_paths[0],
                mobilecode_apk=apk_paths[1],
                mobilecode_test_apk=apk_paths[2],
                model_file=model,
            )
            runner = qa.QaRunner(args)
            runner.environment = "physical_device"
            runner.device_model = b"private physical model"
            runner.thermal_summary = {
                "status": "passed",
                "required": True,
            }
            runner.write_manifest(status="passed")
            raw = (output / "manifest.json").read_text()
            manifest = json.loads(raw)

        self.assertEqual(manifest["schema"], "mobilecore-dual-app-qa/v2")
        self.assertEqual(manifest["environment"], "physical_device")
        self.assertTrue(manifest["physical_device_required"])
        self.assertNotIn("private-physical-serial", raw)
        self.assertNotIn("private physical model", raw)
        self.assertNotIn("private-client-model-name.gguf", raw)
        self.assertIn("artifact_sha256", manifest["model"])

    def test_thermal_lane_runs_continuous_local_requests_without_payload_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=True,
                thermal_duration_seconds=0.02,
                thermal_sample_seconds=1,
                thermal_max_tokens=8,
                thermal_request_timeout=5,
            )
            runner = qa.QaRunner(args)
            runner.environment = "physical_device"
            request_count = 0

            runner.wait_for_health = lambda **_: {"active_model": "model-public-id"}
            runner.adb = lambda *_, **__: subprocess.CompletedProcess([], 0, b"", b"")
            runner.set_airplane_mode = lambda *_args, **_kwargs: None
            runner._capture_pressure_sample = lambda elapsed: {
                "elapsedSeconds": elapsed,
                "batteryTemperatureC": 35.0,
                "maxReportedSensorTemperatureC": 36.0,
                "thermalStatus": 0,
                "maxSensorStatus": 0,
            }

            def api(*_args, **_kwargs):
                nonlocal request_count
                request_count += 1
                return {"choices": [{"message": {"content": "OK"}}]}

            runner.api = api
            runner.exercise_thermal_workload()
            raw = (Path(directory) / "thermal_workload_summary.json").read_text()

        self.assertGreater(request_count, 1)
        self.assertEqual(runner.thermal_summary["status"], "passed")
        self.assertEqual(runner.thermal_summary["workloadFailures"], 0)
        self.assertEqual(
            runner.thermal_summary["workloadAttempts"],
            runner.thermal_summary["workloadRequests"],
        )
        self.assertNotIn("Controlled sustained local QA", raw)
        self.assertNotIn("model-public-id", raw)

    def test_required_low_memory_lane_rejects_an_unaccepted_trim(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=False,
                require_physical_device=True,
                require_background_recovery=False,
            )
            runner = qa.QaRunner(args)
            runner.adb = lambda *_args, **_kwargs: subprocess.CompletedProcess(
                [], 1, b"", b"rejected"
            )
            runner.wait_for_health = lambda **_: {"model_loaded": True}

            with self.assertRaisesRegex(RuntimeError, "RUNNING_LOW"):
                runner.exercise_low_memory_pressure()
            raw = (Path(directory) / "low_memory_summary.json").read_text()

        self.assertEqual(runner.low_memory_summary["status"], "failed")
        self.assertFalse(runner.low_memory_summary["commandAccepted"])
        self.assertTrue(runner.low_memory_summary["modelReadyAfterTrim"])
        self.assertNotIn("com.mobilecore.app", raw)

    def test_background_recovery_restores_app_ops_and_requires_visible_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(
                output_dir=Path(directory),
                forward_port=18080,
                require_thermal=False,
                require_background_recovery=True,
                ready_timeout=30,
            )
            runner = qa.QaRunner(args)
            modes = {operation: "allow" for operation in qa.BACKGROUND_APP_OPS}
            calls: list[str] = []

            def adb(name, *arguments, **_kwargs):
                calls.append(name)
                if "appops" in arguments and "get" in arguments:
                    operation = arguments[-1]
                    stdout = f"{operation}: {modes[operation]}\n".encode()
                    return subprocess.CompletedProcess([], 0, stdout, b"")
                if "appops" in arguments and "set" in arguments:
                    operation = arguments[-2]
                    modes[operation] = arguments[-1]
                return subprocess.CompletedProcess([], 0, b"", b"")

            runner.adb = adb
            runner.wait_for_health_unavailable = lambda **_: True
            runner.tap_mobilecore_load = lambda: calls.append(
                "visible_mobilecore_foreground_start"
            )
            runner.wait_for_health = lambda **_: {"model_loaded": True}

            runner.exercise_background_recovery()
            raw = (Path(directory) / "background_recovery_summary.json").read_text()

        self.assertEqual(runner.background_recovery_summary["status"], "passed")
        self.assertTrue(runner.background_recovery_summary["appOpsRestored"])
        self.assertTrue(runner.background_recovery_summary["modelReadyAfterRecovery"])
        self.assertEqual(
            modes,
            {operation: "allow" for operation in qa.BACKGROUND_APP_OPS},
        )
        self.assertIn("visible_mobilecore_foreground_start", calls)
        self.assertNotIn("com.mobilecore.app", raw)

    def test_apk_signature_gate_pins_every_physical_qa_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apks = []
            for name in ("core.apk", "code.apk", "code-test.apk"):
                path = root / name
                path.write_bytes(name.encode())
                apks.append(path)
            fingerprint = "12" * 32
            args = argparse.Namespace(
                output_dir=root / "evidence",
                forward_port=18080,
                require_thermal=False,
                require_physical_device=True,
                require_background_recovery=True,
                mobilecore_apk=apks[0],
                mobilecode_apk=apks[1],
                mobilecode_test_apk=apks[2],
                expected_mobilecore_cert_sha256=fingerprint,
                expected_mobilecode_cert_sha256=fingerprint,
                expected_mobilecode_test_cert_sha256=fingerprint,
                apksigner="apksigner",
            )
            runner = qa.QaRunner(args)

            def run(*_args, **_kwargs):
                output = (
                    f"Signer #1 certificate SHA-256 digest: {fingerprint}\n"
                ).encode()
                return subprocess.CompletedProcess([], 0, output, b"")

            runner.run = run
            runner.inspect_apk_signatures()
            raw = (root / "evidence/apk_signing_summary.json").read_text()

        self.assertEqual(runner.apk_signing_summary["status"], "passed")
        self.assertTrue(runner.apk_signing_summary["required"])
        self.assertEqual(len(runner.apk_signing_summary["artifacts"]), 3)
        self.assertNotIn("core.apk", raw)


if __name__ == "__main__":
    unittest.main()
