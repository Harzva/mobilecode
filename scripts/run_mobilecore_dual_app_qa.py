#!/usr/bin/env python3
"""Run privacy-safe MobileCode ↔ MobileCore Android QA on one device.

The runner is intentionally host-side. It installs both applications, may
provision a caller-supplied GGUF into MobileCore's app-private external model
directory, starts the model through the visible MobileCore UI, runs the native
30-task cross-app instrumentation test, automatically exercises every advertised
image/audio capability, and runs lifecycle and pressure checks. Raw prompts,
media, model outputs, credentials, and local host paths are not written to the
manifest. Run this only on a dedicated QA device with controlled accounts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence


MOBILECORE_PACKAGE = "com.mobilecore.app"
MOBILECORE_ACTIVITY = "com.mobilecore.app/ai.mobilecore.MainActivity"
MOBILECODE_PACKAGE = "com.mobilecode.app"
MOBILECODE_ACTIVITY = "com.mobilecode.app/.MainActivity"
MOBILECODE_TEST_RUNNER = (
    "com.mobilecode.app.test/androidx.test.runner.AndroidJUnitRunner"
)
CROSS_APP_TEST = (
    "com.mobilecode.app.MobileCoreCrossAppQaTest#"
    "thirtyControlledOfflineTextAndStreamTasks"
)
CROSS_APP_IMAGE_TEST = (
    "com.mobilecode.app.MobileCoreCrossAppQaTest#"
    "controlledLocalImageQualityTasks"
)
CROSS_APP_AUDIO_TEST = (
    "com.mobilecode.app.MobileCoreCrossAppQaTest#"
    "controlledLocalAudioQualityTasks"
)

_SENSITIVE_SNAPSHOT_KEYS = {
    "absolute_path",
    "audio",
    "authorization",
    "content",
    "cookie",
    "credential",
    "credential_value",
    "file_path",
    "file_name",
    "host_path",
    "image",
    "local_path",
    "media",
    "media_data",
    "messages",
    "path",
    "prompt",
    "raw_content",
    "raw_media",
    "secret",
    "secret_value",
    "token",
}
_ABSOLUTE_PATH_PATTERN = re.compile(
    r"(?<![A-Za-z0-9])(?:/(?:data|storage|sdcard|Users|Volumes|home|tmp|var)/[^\s,;]+|[A-Za-z]:\\[^\s,;]+)"
)
_THERMAL_STATUS_PATTERN = re.compile(r"Thermal Status:\s*(-?\d+)", re.IGNORECASE)
_THERMAL_TEMPERATURE_PATTERN = re.compile(
    r"Temperature\{[^}]*mValue=(-?\d+(?:\.\d+)?)[^}]*mStatus=(-?\d+)",
    re.IGNORECASE,
)
_BATTERY_TEMPERATURE_PATTERN = re.compile(
    r"^\s*temperature:\s*(-?\d+)\s*$",
    re.IGNORECASE | re.MULTILINE,
)


@dataclass(frozen=True)
class Step:
    name: str
    status: str
    duration_ms: int
    result_digest: str
    failure_kind: str | None = None


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sanitize_evidence_value(value: object) -> object:
    """Recursively remove payloads, credentials, and local absolute paths."""
    if isinstance(value, dict):
        safe: dict[str, object] = {}
        for raw_key, item in value.items():
            key = str(raw_key)
            normalized = re.sub(r"[^a-z0-9]+", "_", key.lower()).strip("_")
            if (
                normalized in _SENSITIVE_SNAPSHOT_KEYS
                or normalized.endswith(
                    ("_path", "_token", "_cookie", "_secret", "_credential")
                )
                or normalized in {"api_key", "authorization_header"}
            ):
                continue
            safe[key] = sanitize_evidence_value(item)
        return safe
    if isinstance(value, list):
        return [sanitize_evidence_value(item) for item in value]
    if isinstance(value, tuple):
        return [sanitize_evidence_value(item) for item in value]
    if isinstance(value, str):
        return _ABSOLUTE_PATH_PATTERN.sub("<local-path-omitted>", value)
    return value


def classify_android_environment(
    *,
    serial: str,
    kernel_qemu: str,
    boot_qemu: str,
    hardware: str,
    model: str,
) -> str:
    """Classify the target from Android properties, with serial as fallback."""
    qemu_values = {kernel_qemu.strip().lower(), boot_qemu.strip().lower()}
    if qemu_values.intersection({"1", "true", "yes"}):
        return "emulator"
    combined = f"{hardware} {model}".lower()
    if any(
        marker in combined
        for marker in ("goldfish", "ranchu", "sdk_gphone", "emulator", "virtual device")
    ):
        return "emulator"
    if serial.startswith("emulator-"):
        return "emulator"
    if any((serial.strip(), hardware.strip(), model.strip())):
        return "physical_device"
    return "unknown"


def parse_battery_temperature_c(raw: str) -> float | None:
    match = _BATTERY_TEMPERATURE_PATTERN.search(raw)
    if match is None:
        return None
    return round(int(match.group(1)) / 10.0, 1)


def parse_thermal_service(raw: str) -> tuple[int | None, float | None, int | None]:
    status_match = _THERMAL_STATUS_PATTERN.search(raw)
    service_status = int(status_match.group(1)) if status_match is not None else None
    temperatures = [
        (float(match.group(1)), int(match.group(2)))
        for match in _THERMAL_TEMPERATURE_PATTERN.finditer(raw)
    ]
    max_temperature = max((item[0] for item in temperatures), default=None)
    max_sensor_status = max((item[1] for item in temperatures), default=None)
    return service_status, max_temperature, max_sensor_status


def instrumentation_succeeded(
    *,
    returncode: int,
    stdout: bytes,
    stderr: bytes,
) -> bool:
    """Judge AndroidJUnitRunner results instead of trusting adb's exit code."""
    if returncode != 0:
        return False
    output = (stdout + b"\n" + stderr).decode("utf-8", "replace")
    if "FAILURES!!!" in output or "INSTRUMENTATION_STATUS_CODE: -2" in output:
        return False
    match = re.search(r"(?m)^OK \((\d+) tests?\)\s*$", output)
    return match is not None and int(match.group(1)) > 0


class QaRunner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.steps: list[Step] = []
        self.output_dir = args.output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.forward_port = args.forward_port
        self.model_switch_status = "not_run"
        self.environment = "unknown"
        self.device_model = b""
        self.multimodal_summary: dict[str, object] = {
            "status": "not_run",
            "localOnly": True,
            "rawMediaPromptsAndOutputsPersisted": False,
        }
        self.thermal_summary: dict[str, object] = {
            "status": "not_run",
            "required": args.require_thermal,
        }

    def run(
        self,
        name: str,
        command: Sequence[str],
        *,
        timeout: int = 120,
        required: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        started = time.monotonic()
        try:
            result = subprocess.run(
                list(command),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                check=False,
            )
            combined = result.stdout + b"\0" + result.stderr
            status = "passed" if result.returncode == 0 else "failed"
            self.steps.append(
                Step(
                    name=name,
                    status=status,
                    duration_ms=round((time.monotonic() - started) * 1000),
                    result_digest=sha256_bytes(combined),
                    failure_kind=None if result.returncode == 0 else "process_failed",
                )
            )
            if required and result.returncode != 0:
                safe_error = result.stderr.decode("utf-8", "replace").strip()[-300:]
                raise RuntimeError(f"{name} failed: {safe_error}")
            return result
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b"") + b"\0" + (error.stderr or b"")
            self.steps.append(
                Step(
                    name=name,
                    status="failed",
                    duration_ms=round((time.monotonic() - started) * 1000),
                    result_digest=sha256_bytes(output),
                    failure_kind="timeout",
                )
            )
            if required:
                raise RuntimeError(f"{name} timed out") from error
            return subprocess.CompletedProcess(command, 124, b"", b"timeout")

    def adb(
        self,
        name: str,
        *arguments: str,
        timeout: int = 120,
        required: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        return self.run(
            name,
            [self.args.adb, "-s", self.args.serial, *arguments],
            timeout=timeout,
            required=required,
        )

    def instrumentation(
        self,
        name: str,
        test_name: str,
        *,
        timeout: int,
    ) -> subprocess.CompletedProcess[bytes]:
        command = [
            self.args.adb,
            "-s",
            self.args.serial,
            "shell",
            "am",
            "instrument",
            "-w",
            "-r",
            "-e",
            "class",
            test_name,
            MOBILECODE_TEST_RUNNER,
        ]
        started = time.monotonic()
        try:
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b"") + b"\0" + (error.stderr or b"")
            self.steps.append(
                Step(
                    name=name,
                    status="failed",
                    duration_ms=round((time.monotonic() - started) * 1000),
                    result_digest=sha256_bytes(output),
                    failure_kind="timeout",
                )
            )
            raise RuntimeError(f"{name} timed out") from error

        combined = result.stdout + b"\0" + result.stderr
        passed = instrumentation_succeeded(
            returncode=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
        )
        self.steps.append(
            Step(
                name=name,
                status="passed" if passed else "failed",
                duration_ms=round((time.monotonic() - started) * 1000),
                result_digest=sha256_bytes(combined),
                failure_kind=None if passed else "instrumentation_failed",
            )
        )
        if not passed:
            raise RuntimeError(f"{name} failed its AndroidJUnitRunner assertions")
        return result

    def api(
        self,
        method: str,
        path: str,
        body: dict[str, object] | None = None,
        *,
        timeout: int = 15,
    ) -> dict[str, object]:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.forward_port}{path}",
            data=None if body is None else json.dumps(body).encode("utf-8"),
            method=method,
            headers={
                "Authorization": "Bearer local",
                "Content-Type": "application/json",
                "X-MobileCore-Client": "mobilecode-dual-app-host-qa",
            },
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            decoded = json.loads(response.read().decode("utf-8"))
            if not isinstance(decoded, dict):
                raise RuntimeError(f"{path} returned a non-object response")
            return decoded

    def wait_for_health(self, *, require_model: bool, timeout: int = 120) -> dict[str, object]:
        deadline = time.monotonic() + timeout
        last_error = "unavailable"
        while time.monotonic() < deadline:
            try:
                health = self.api("GET", "/health")
                if not require_model or health.get("model_loaded") is True:
                    return health
                last_error = "model_not_loaded"
            except (OSError, ValueError, urllib.error.URLError) as error:
                last_error = error.__class__.__name__
            time.sleep(1)
        raise RuntimeError(f"MobileCore health timeout ({last_error})")

    def dump_ui(self) -> ET.Element:
        self.adb(
            "dump_mobilecore_ui",
            "shell",
            "uiautomator",
            "dump",
            "/sdcard/mobilecore-qa-window.xml",
            timeout=30,
        )
        raw = self.adb(
            "read_mobilecore_ui",
            "exec-out",
            "cat",
            "/sdcard/mobilecore-qa-window.xml",
            timeout=30,
        ).stdout
        return ET.fromstring(raw)

    def tap_mobilecore_load(self) -> None:
        self.adb("launch_mobilecore", "shell", "am", "start", "-W", "-n", MOBILECORE_ACTIVITY)
        time.sleep(2)
        self.adb("open_mobilecore_home_tab", "shell", "input", "tap", "80", "1150")
        time.sleep(1)
        patterns = (
            re.compile(r"^(加载|重新加载|启动)$"),
            re.compile(r"加载.*模型"),
            re.compile(r"启动.*服务"),
            re.compile(r"重新加载"),
        )
        for attempt in range(3):
            root = self.dump_ui()
            for node in root.iter("node"):
                if node.attrib.get("clickable") != "true":
                    continue
                labels = {
                    value
                    for value in (
                        node.attrib.get("text", ""),
                        node.attrib.get("content-desc", ""),
                    )
                    if value
                }
                if not any(
                    pattern.search(label)
                    for pattern in patterns
                    for label in labels
                ):
                    continue
                match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
                if match is None:
                    continue
                left, top, right, bottom = map(int, match.groups())
                self.adb(
                    "tap_mobilecore_load",
                    "shell",
                    "input",
                    "tap",
                    str((left + right) // 2),
                    str((top + bottom) // 2),
                )
                return
            if attempt == 0:
                self.adb("reopen_mobilecore_home_tab", "shell", "input", "tap", "80", "1150")
            time.sleep(1)
        raise RuntimeError("No visible MobileCore model-load control was found")

    def snapshot(self, name: str, payload: dict[str, object]) -> None:
        safe = sanitize_evidence_value(payload)
        (self.output_dir / f"{name}.json").write_text(
            json.dumps(safe, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def inspect_device_environment(self) -> None:
        properties: dict[str, bytes] = {}
        for key, property_name in (
            ("kernel_qemu", "ro.kernel.qemu"),
            ("boot_qemu", "ro.boot.qemu"),
            ("hardware", "ro.hardware"),
            ("model", "ro.product.model"),
        ):
            properties[key] = self.adb(
                f"read_device_{key}",
                "shell",
                "getprop",
                property_name,
                required=False,
            ).stdout.strip()
        self.device_model = properties["model"]
        self.environment = classify_android_environment(
            serial=self.args.serial,
            kernel_qemu=properties["kernel_qemu"].decode("utf-8", "replace"),
            boot_qemu=properties["boot_qemu"].decode("utf-8", "replace"),
            hardware=properties["hardware"].decode("utf-8", "replace"),
            model=properties["model"].decode("utf-8", "replace"),
        )
        if self.args.require_physical_device and self.environment != "physical_device":
            raise RuntimeError(
                "Physical-device acceptance was requested, but Android properties identify a non-physical target"
            )

    def install_and_prepare(self) -> None:
        self.adb("wait_for_device", "wait-for-device")
        self.inspect_device_environment()
        for name, path in (
            ("install_mobilecore", self.args.mobilecore_apk),
            ("install_mobilecode", self.args.mobilecode_apk),
        ):
            # QA devices may already carry a newer release build. The
            # instrumentation APK must target the locally built, debug-signed
            # application, so allow a controlled version downgrade while
            # preserving app data and installed model assets.
            self.adb(name, "install", "-r", "-d", str(path), timeout=300)
        self.adb(
            "install_mobilecode_test",
            "install",
            "-r",
            "-d",
            "-t",
            str(self.args.mobilecode_test_apk),
            timeout=300,
        )
        self.adb(
            "grant_mobilecore_notifications",
            "shell",
            "pm",
            "grant",
            MOBILECORE_PACKAGE,
            "android.permission.POST_NOTIFICATIONS",
            required=False,
        )
        if self.args.model_file is not None:
            remote_dir = f"/sdcard/Android/data/{MOBILECORE_PACKAGE}/files/models"
            self.adb("create_mobilecore_model_dir", "shell", "mkdir", "-p", remote_dir)
            self.adb(
                "push_mobilecore_model",
                "push",
                str(self.args.model_file),
                f"{remote_dir}/{self.args.model_file.name}",
                timeout=900,
            )
        self.adb(
            "forward_mobilecore_api",
            "forward",
            f"tcp:{self.forward_port}",
            "tcp:8080",
        )
        self.tap_mobilecore_load()
        health = self.wait_for_health(require_model=True, timeout=self.args.ready_timeout)
        self.snapshot("health_initial", health)

    def run_cross_app_tasks(self) -> None:
        self.adb(
            "enable_airplane_mode",
            "shell",
            "cmd",
            "connectivity",
            "airplane-mode",
            "enable",
            required=False,
        )
        try:
            self.instrumentation(
                "run_30_cross_app_tasks",
                CROSS_APP_TEST,
                timeout=self.args.task_timeout,
            )
            self.exercise_multimodal_cross_app_tasks()
        finally:
            self.adb(
                "disable_airplane_mode",
                "shell",
                "cmd",
                "connectivity",
                "airplane-mode",
                "disable",
                required=False,
            )
        self.snapshot("metrics_after_30_tasks", self.api("GET", "/metrics"))

    def exercise_multimodal_cross_app_tasks(self) -> None:
        health = self.wait_for_health(require_model=True)
        self.snapshot("health_before_multimodal", health)
        capabilities = health.get("capabilities")
        if not isinstance(capabilities, dict):
            capabilities = {}
        artifacts = health.get("artifacts")
        if not isinstance(artifacts, dict):
            artifacts = {}
        main_artifact = artifacts.get("main")
        projector_artifact = artifacts.get("mmproj")
        main_verified = isinstance(main_artifact, dict) and main_artifact.get("verified") is True
        projector_verified = (
            isinstance(projector_artifact, dict)
            and projector_artifact.get("verified") is True
        )
        pair_verified = main_verified and projector_verified
        image_advertised = capabilities.get("image_input") is True
        audio_advertised = capabilities.get("audio_input") is True
        require_image = bool(getattr(self.args, "require_image_multimodal", False))
        require_audio = bool(getattr(self.args, "require_audio_multimodal", False))
        require_verified_omni = bool(getattr(self.args, "require_verified_omni", False))
        if require_verified_omni:
            require_image = True
            require_audio = True

        self.multimodal_summary = {
            "status": "running",
            "localOnly": True,
            "offlineDuringTasks": True,
            "rawMediaPromptsAndOutputsPersisted": False,
            "capabilities": {
                "imageInput": image_advertised,
                "audioInput": audio_advertised,
                "audioSampleRateHz": int(health.get("audio_sample_rate_hz") or 0),
            },
            "artifactVerification": {
                "required": require_verified_omni,
                "mainVerified": main_verified,
                "projectorVerified": projector_verified,
                "pairVerified": pair_verified,
            },
            "image": "pending" if image_advertised else "not_advertised",
            "audio": "pending" if audio_advertised else "not_advertised",
        }

        if require_verified_omni and not pair_verified:
            self.multimodal_summary["status"] = "failed"
            self.snapshot("multimodal_summary", self.multimodal_summary)
            raise RuntimeError("Verified Omni artifacts are required for multimodal acceptance")
        if require_image and not image_advertised:
            self.multimodal_summary["status"] = "failed"
            self.snapshot("multimodal_summary", self.multimodal_summary)
            raise RuntimeError("Image multimodal acceptance requires image_input=true")
        if require_audio and not audio_advertised:
            self.multimodal_summary["status"] = "failed"
            self.snapshot("multimodal_summary", self.multimodal_summary)
            raise RuntimeError("Audio multimodal acceptance requires audio_input=true")

        for modality, advertised, test_name in (
            ("image", image_advertised, CROSS_APP_IMAGE_TEST),
            ("audio", audio_advertised, CROSS_APP_AUDIO_TEST),
        ):
            if not advertised:
                continue
            try:
                self.instrumentation(
                    f"run_cross_app_{modality}_quality_tasks",
                    test_name,
                    timeout=self.args.task_timeout,
                )
                self.multimodal_summary[modality] = "passed"
            except RuntimeError:
                self.multimodal_summary[modality] = "failed"
                self.multimodal_summary["status"] = "failed"
                self.snapshot("multimodal_summary", self.multimodal_summary)
                raise

        executed = image_advertised or audio_advertised
        self.multimodal_summary["status"] = "passed" if executed else "not_available"
        self.snapshot("multimodal_summary", self.multimodal_summary)

    def exercise_lifecycle(self) -> None:
        health = self.wait_for_health(require_model=True)
        active_model = str(health.get("active_model") or "")
        if not active_model:
            raise RuntimeError("MobileCore did not report an active model")

        unloaded = self.api("POST", "/mobilecore/model/unload", {})
        if unloaded.get("model_loaded") is not False:
            raise RuntimeError("MobileCore unload did not release the model")
        self.snapshot("model_unload", unloaded)
        reloaded = self.api(
            "POST",
            "/mobilecore/model/load",
            {"model_id": active_model, "context_length": 2048},
        )
        self.snapshot("model_reload", reloaded)

        recommendations = self.api("GET", "/v1/recommendations")
        candidates = [
            item.get("model_id")
            for item in recommendations.get("recommendations", [])
            if isinstance(item, dict) and item.get("model_id") != active_model
        ]
        if candidates:
            switched = self.api(
                "POST",
                "/mobilecore/model/load",
                {"model_id": str(candidates[0]), "context_length": 2048},
            )
            self.snapshot("model_switch", switched)
            self.api(
                "POST",
                "/mobilecore/model/load",
                {"model_id": active_model, "context_length": 2048},
            )
            switch_status = "passed"
        else:
            switch_status = "blocked_single_model"
        self.model_switch_status = switch_status
        if self.args.require_model_switch and switch_status != "passed":
            raise RuntimeError("A second compatible local model is required for model-switch acceptance")

        self.adb("background_mobilecore_with_mobilecode", "shell", "am", "start", "-W", "-n", MOBILECODE_ACTIVITY)
        self.wait_for_health(require_model=True)
        self.adb(
            "trim_mobilecore_memory",
            "shell",
            "am",
            "send-trim-memory",
            MOBILECORE_PACKAGE,
            "RUNNING_LOW",
            required=False,
        )
        pressure_health = self.wait_for_health(require_model=True)
        self.snapshot("health_after_memory_pressure", pressure_health)

        thermal = self.adb(
            "capture_thermal_state",
            "shell",
            "dumpsys",
            "thermalservice",
            required=False,
        )
        battery = self.adb(
            "capture_battery_state",
            "shell",
            "dumpsys",
            "battery",
            required=False,
        )
        self.snapshot(
            "device_pressure_summary",
            {
                "thermal_digest": sha256_bytes(thermal.stdout),
                "battery_digest": sha256_bytes(battery.stdout),
                "model_switch": switch_status,
            },
        )

        self.adb("force_stop_mobilecore", "shell", "am", "force-stop", MOBILECORE_PACKAGE)
        self.tap_mobilecore_load()
        restarted = self.wait_for_health(require_model=True, timeout=self.args.ready_timeout)
        self.snapshot("health_after_process_restart", restarted)

    def _capture_pressure_sample(self, elapsed_seconds: int) -> dict[str, object]:
        def capture(*arguments: str) -> str:
            try:
                result = subprocess.run(
                    [self.args.adb, "-s", self.args.serial, *arguments],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    timeout=30,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                return ""
            if result.returncode != 0:
                return ""
            return result.stdout.decode("utf-8", "replace")

        thermal = capture("shell", "dumpsys", "thermalservice")
        battery = capture("shell", "dumpsys", "battery")
        thermal_status, max_sensor_c, max_sensor_status = parse_thermal_service(thermal)
        return {
            "elapsedSeconds": elapsed_seconds,
            "batteryTemperatureC": parse_battery_temperature_c(battery),
            "maxReportedSensorTemperatureC": max_sensor_c,
            "thermalStatus": thermal_status,
            "maxSensorStatus": max_sensor_status,
        }

    def exercise_thermal_workload(self) -> None:
        duration = self.args.thermal_duration_seconds
        if duration <= 0:
            return
        started = time.monotonic()
        health = self.wait_for_health(require_model=True)
        active_model = str(health.get("active_model") or "")
        if not active_model:
            raise RuntimeError("Thermal workload requires an active MobileCore model")

        samples: list[dict[str, object]] = []
        workload_requests = 0
        workload_failures = 0
        self.adb(
            "enable_airplane_mode_for_thermal_workload",
            "shell",
            "cmd",
            "connectivity",
            "airplane-mode",
            "enable",
            required=False,
        )
        try:
            next_sample_at = started
            deadline = started + duration
            while time.monotonic() < deadline:
                now = time.monotonic()
                if now >= next_sample_at:
                    samples.append(
                        self._capture_pressure_sample(round(now - started))
                    )
                    next_sample_at = now + self.args.thermal_sample_seconds
                try:
                    response = self.api(
                        "POST",
                        "/v1/chat/completions",
                        {
                            "model": active_model,
                            "max_tokens": self.args.thermal_max_tokens,
                            "temperature": 0.0,
                            "stream": False,
                            "messages": [
                                {
                                    "role": "user",
                                    "content": "Controlled sustained local QA. Reply exactly: OK.",
                                }
                            ],
                        },
                        timeout=self.args.thermal_request_timeout,
                    )
                    choices = response.get("choices")
                    if not isinstance(choices, list) or not choices:
                        raise RuntimeError("empty controlled thermal response")
                    workload_requests += 1
                except (OSError, RuntimeError, ValueError, urllib.error.URLError):
                    workload_failures += 1
                    remaining = deadline - time.monotonic()
                    if remaining > 0:
                        time.sleep(min(remaining, 1.0))
            samples.append(
                self._capture_pressure_sample(round(time.monotonic() - started))
            )
        finally:
            self.adb(
                "disable_airplane_mode_after_thermal_workload",
                "shell",
                "cmd",
                "connectivity",
                "airplane-mode",
                "disable",
                required=False,
            )

        battery_values = [
            float(sample["batteryTemperatureC"])
            for sample in samples
            if sample["batteryTemperatureC"] is not None
        ]
        sensor_values = [
            float(sample["maxReportedSensorTemperatureC"])
            for sample in samples
            if sample["maxReportedSensorTemperatureC"] is not None
        ]
        status_values = [
            int(value)
            for sample in samples
            for value in (sample["thermalStatus"], sample["maxSensorStatus"])
            if value is not None
        ]
        telemetry_available = bool(battery_values or sensor_values or status_values)
        passed = workload_requests > 0 and workload_failures == 0 and telemetry_available
        observed_seconds = max(1, round(time.monotonic() - started))
        self.thermal_summary = {
            "status": "passed" if passed else "failed",
            "required": self.args.require_thermal,
            "environment": self.environment,
            "offlineDuringWorkload": True,
            "durationSecondsRequested": duration,
            "durationSecondsObserved": observed_seconds,
            "sampleIntervalSeconds": self.args.thermal_sample_seconds,
            "sampleCount": len(samples),
            "workloadRequests": workload_requests,
            "workloadFailures": workload_failures,
            "workloadAttempts": workload_requests + workload_failures,
            "successfulRequestsPerMinute": round(
                workload_requests * 60 / observed_seconds,
                2,
            ),
            "telemetryAvailable": telemetry_available,
            "throttlingObserved": bool(status_values and max(status_values) > 0),
            "maxThermalStatus": max(status_values) if status_values else None,
            "batteryTemperatureC": {
                "start": battery_values[0] if battery_values else None,
                "max": max(battery_values) if battery_values else None,
                "end": battery_values[-1] if battery_values else None,
            },
            "reportedSensorTemperatureC": {
                "start": sensor_values[0] if sensor_values else None,
                "max": max(sensor_values) if sensor_values else None,
                "end": sensor_values[-1] if sensor_values else None,
            },
            "samples": samples,
        }
        self.snapshot("thermal_workload_summary", self.thermal_summary)
        self.steps.append(
            Step(
                name="sustained_local_thermal_workload",
                status="passed" if passed else "failed",
                duration_ms=round((time.monotonic() - started) * 1000),
                result_digest=sha256_bytes(
                    json.dumps(
                        self.thermal_summary,
                        sort_keys=True,
                        separators=(",", ":"),
                    ).encode("utf-8")
                ),
                failure_kind=None if passed else "thermal_acceptance_failed",
            )
        )
        if self.args.require_thermal and not passed:
            raise RuntimeError(
                "Required sustained thermal workload did not produce complete local inference and telemetry evidence"
            )

    def capture_artifacts(self) -> None:
        screenshot = self.adb(
            "capture_mobilecore_screenshot",
            "exec-out",
            "screencap",
            "-p",
            required=False,
        ).stdout
        if screenshot.startswith(b"\x89PNG"):
            (self.output_dir / "final-screen.png").write_bytes(screenshot)

        logcat = self.adb(
            "capture_sanitized_logcat",
            "logcat",
            "-d",
            "-t",
            "1200",
            required=False,
        ).stdout.decode("utf-8", "replace")
        selected = []
        for line in logcat.splitlines():
            lowered = line.lower()
            if "mobilecore" not in lowered and "mobilecode" not in lowered:
                continue
            line = re.sub(r"data:[^\s]+", "<media-payload-omitted>", line)
            line = re.sub(r"(?i)bearer\s+\S+", "Bearer <redacted>", line)
            line = re.sub(r"(?i)(token|cookie|authorization)=\S+", r"\1=<redacted>", line)
            line = re.sub(r"/(?:data|storage|sdcard|Users|Volumes)/\S+", "<local-path-omitted>", line)
            selected.append(line)
        (self.output_dir / "logcat-sanitized.txt").write_text(
            "\n".join(selected[-400:]) + "\n",
            encoding="utf-8",
        )

    def write_manifest(self, *, status: str, error: str | None = None) -> None:
        manifest = {
            "schema": "mobilecore-dual-app-qa/v2",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "status": status,
            "environment": self.environment,
            "physical_device_required": self.args.require_physical_device,
            "device_id_hash": sha256_bytes(self.args.serial.encode())[:16],
            "device_model_hash": sha256_bytes(self.device_model)[:16],
            "controlled_tasks": 30,
            "offline_during_tasks": True,
            "model_switch": {
                "required": self.args.require_model_switch,
                "status": self.model_switch_status,
            },
            "multimodal": self.multimodal_summary,
            "thermal_workload": self.thermal_summary,
            "redaction": "raw_prompts_media_credentials_and_host_paths_omitted",
            "apks": {
                "mobilecore_sha256": sha256_file(self.args.mobilecore_apk),
                "mobilecode_sha256": sha256_file(self.args.mobilecode_apk),
                "mobilecode_test_sha256": sha256_file(self.args.mobilecode_test_apk),
            },
            "model": None
            if self.args.model_file is None
            else {
                "artifact_sha256": sha256_file(self.args.model_file),
            },
            "artifacts": {
                artifact.name: sha256_file(artifact)
                for artifact in (
                    self.output_dir / "final-screen.png",
                    self.output_dir / "logcat-sanitized.txt",
                )
                if artifact.is_file()
            },
            "steps": [asdict(step) for step in self.steps],
            **({"failure": error} if error else {}),
        }
        (self.output_dir / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )


def parse_args() -> argparse.Namespace:
    repository = Path(__file__).resolve().parents[1]
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb", default="adb")
    parser.add_argument(
        "--mobilecore-apk",
        type=Path,
        default=repository.parent / "MobileCore/android-app/app/build/outputs/apk/debug/app-debug.apk",
    )
    parser.add_argument(
        "--mobilecode-apk",
        type=Path,
        default=repository / "mobile_agent/build/app/outputs/flutter-apk/app-pure-debug.apk",
    )
    parser.add_argument(
        "--mobilecode-test-apk",
        type=Path,
        default=repository / "mobile_agent/build/app/outputs/apk/androidTest/pure/debug/app-pure-debug-androidTest.apk",
    )
    parser.add_argument("--model-file", type=Path)
    parser.add_argument(
        "--require-model-switch",
        action="store_true",
        help="Fail acceptance when the device does not expose a second loadable model.",
    )
    parser.add_argument(
        "--require-image-multimodal",
        action="store_true",
        help="Fail unless MobileCore advertises image input and the cross-app image quality tasks pass.",
    )
    parser.add_argument(
        "--require-audio-multimodal",
        action="store_true",
        help="Fail unless MobileCore advertises audio input and the cross-app audio quality tasks pass.",
    )
    parser.add_argument(
        "--require-verified-omni",
        action="store_true",
        help="Require verified main/projector artifacts plus passing image and audio cross-app tasks.",
    )
    parser.add_argument(
        "--require-physical-device",
        action="store_true",
        help="Fail before installation when Android properties identify an emulator.",
    )
    parser.add_argument(
        "--require-thermal",
        action="store_true",
        help="Require a successful sustained local inference workload with thermal telemetry.",
    )
    parser.add_argument("--thermal-duration-seconds", type=int, default=0)
    parser.add_argument("--thermal-sample-seconds", type=int, default=15)
    parser.add_argument("--thermal-max-tokens", type=int, default=8)
    parser.add_argument("--thermal-request-timeout", type=int, default=120)
    parser.add_argument("--output-dir", type=Path, default=repository / f".qa-artifacts/mobilecore-dual-app/{timestamp}")
    parser.add_argument("--forward-port", type=int, default=18080)
    parser.add_argument("--ready-timeout", type=int, default=180)
    parser.add_argument("--task-timeout", type=int, default=1800)
    args = parser.parse_args()
    for label in ("mobilecore_apk", "mobilecode_apk", "mobilecode_test_apk"):
        path = getattr(args, label)
        if not path.is_file():
            parser.error(f"{label.replace('_', '-')} not found: {path}")
    if args.model_file is not None and not args.model_file.is_file():
        parser.error(f"model-file not found: {args.model_file}")
    if args.thermal_duration_seconds < 0:
        parser.error("thermal-duration-seconds must be >= 0")
    if not 1 <= args.thermal_sample_seconds <= 60:
        parser.error("thermal-sample-seconds must be between 1 and 60")
    if not 1 <= args.thermal_max_tokens <= 64:
        parser.error("thermal-max-tokens must be between 1 and 64")
    if args.thermal_request_timeout < 1:
        parser.error("thermal-request-timeout must be >= 1")
    if args.require_thermal and args.thermal_duration_seconds <= 0:
        parser.error("--require-thermal requires --thermal-duration-seconds > 0")
    if args.require_physical_device and not args.require_thermal:
        parser.error("--require-physical-device requires --require-thermal")
    return args


def main() -> int:
    args = parse_args()
    runner = QaRunner(args)
    try:
        runner.install_and_prepare()
        runner.run_cross_app_tasks()
        runner.exercise_lifecycle()
        runner.exercise_thermal_workload()
        runner.capture_artifacts()
        runner.write_manifest(status="passed")
        print(runner.output_dir / "manifest.json")
        return 0
    except Exception as error:  # noqa: BLE001 - top-level evidence boundary
        public_error = f"{error.__class__.__name__}: QA step failed; inspect terminal output."
        runner.write_manifest(status="failed", error=public_error)
        print(f"{error.__class__.__name__}: {str(error)[:300]}", file=sys.stderr)
        print(runner.output_dir / "manifest.json", file=sys.stderr)
        return 1
    finally:
        runner.adb(
            "remove_mobilecore_forward",
            "forward",
            "--remove",
            f"tcp:{args.forward_port}",
            required=False,
        )


if __name__ == "__main__":
    raise SystemExit(main())
