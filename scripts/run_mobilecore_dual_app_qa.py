#!/usr/bin/env python3
"""Run privacy-safe MobileCode ↔ MobileCore Android QA on one device.

The runner is intentionally host-side. It installs both applications, may
provision a caller-supplied GGUF into MobileCore's app-private external model
directory, starts the model through the visible MobileCore UI, runs the native
30-task cross-app instrumentation test, and exercises lifecycle and pressure
checks. Raw prompts, media, credentials, and local host paths are not written to
the manifest. Run this only on a dedicated QA device with controlled accounts.
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


class QaRunner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.steps: list[Step] = []
        self.output_dir = args.output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.forward_port = args.forward_port

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

    def api(self, method: str, path: str, body: dict[str, object] | None = None) -> dict[str, object]:
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
        with urllib.request.urlopen(request, timeout=15) as response:
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
        safe = {
            key: value
            for key, value in payload.items()
            if key
            not in {
                "path",
                "prompt",
                "messages",
                "image",
                "audio",
                "token",
                "cookie",
            }
        }
        (self.output_dir / f"{name}.json").write_text(
            json.dumps(safe, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def install_and_prepare(self) -> None:
        self.adb("wait_for_device", "wait-for-device")
        for name, path in (
            ("install_mobilecore", self.args.mobilecore_apk),
            ("install_mobilecode", self.args.mobilecode_apk),
        ):
            self.adb(name, "install", "-r", str(path), timeout=300)
        self.adb(
            "install_mobilecode_test",
            "install",
            "-r",
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
            self.adb(
                "run_30_cross_app_tasks",
                "shell",
                "am",
                "instrument",
                "-w",
                "-r",
                "-e",
                "class",
                CROSS_APP_TEST,
                MOBILECODE_TEST_RUNNER,
                timeout=self.args.task_timeout,
            )
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
        device = self.adb(
            "read_device_identity",
            "shell",
            "getprop",
            "ro.product.model",
            required=False,
        ).stdout.strip()
        manifest = {
            "schema": "mobilecore-dual-app-qa/v1",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "status": status,
            "environment": "emulator" if self.args.serial.startswith("emulator-") else "physical_device",
            "device_id_hash": sha256_bytes(self.args.serial.encode())[:16],
            "device_model_hash": sha256_bytes(device)[:16],
            "controlled_tasks": 30,
            "offline_during_tasks": True,
            "redaction": "raw_prompts_media_credentials_and_host_paths_omitted",
            "apks": {
                "mobilecore_sha256": sha256_file(self.args.mobilecore_apk),
                "mobilecode_sha256": sha256_file(self.args.mobilecode_apk),
                "mobilecode_test_sha256": sha256_file(self.args.mobilecode_test_apk),
            },
            "model": None
            if self.args.model_file is None
            else {
                "file_name": self.args.model_file.name,
                "sha256": sha256_file(self.args.model_file),
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
    return args


def main() -> int:
    args = parse_args()
    runner = QaRunner(args)
    try:
        runner.install_and_prepare()
        runner.run_cross_app_tasks()
        runner.exercise_lifecycle()
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
