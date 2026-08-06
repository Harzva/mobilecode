#!/usr/bin/env python3
"""Run bounded MobileCode QA through the external agent-device CLI.

This host-side adapter deliberately stays outside the Flutter APK. It persists
only digests, exit status, timings, and reviewed artifact identifiers. Raw CLI
stdout/stderr, accessibility labels, typed values, cookies, and credentials are
never written to the evidence manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import BinaryIO, Sequence


PINNED_AGENT_DEVICE_VERSION = "0.19.3"
DEFAULT_SESSION = "mobilecode-phone-use-qa"


@dataclass(frozen=True)
class StepEvidence:
    action: str
    status: str
    exit_code: int | None
    duration_ms: int
    started_at: str
    ended_at: str
    stdout_bytes: int
    stderr_bytes: int
    result_digest: str | None
    failure_kind: str | None


@dataclass
class RunningIosVideo:
    process: subprocess.Popen[bytes]
    log_handle: BinaryIO
    log_path: Path
    video_path: Path


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _safe_id(prefix: str, digest: str) -> str:
    return f"{prefix}-{digest[:16]}"


def _run(
    command: Sequence[str],
    *,
    action: str,
    dry_run: bool,
    timeout_seconds: int,
) -> StepEvidence:
    started_at = datetime.now(timezone.utc).isoformat()
    if dry_run:
        return StepEvidence(
            action=action,
            status="planned",
            exit_code=None,
            duration_ms=0,
            started_at=started_at,
            ended_at=started_at,
            stdout_bytes=0,
            stderr_bytes=0,
            result_digest=None,
            failure_kind=None,
        )

    started = time.monotonic()
    try:
        completed = subprocess.run(
            list(command),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds,
            env={**os.environ, "AGENT_DEVICE_NO_UPDATE_NOTIFIER": "1"},
        )
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout or b""
        stderr = error.stderr or b""
        return StepEvidence(
            action=action,
            status="failed",
            exit_code=None,
            duration_ms=round((time.monotonic() - started) * 1000),
            started_at=started_at,
            ended_at=datetime.now(timezone.utc).isoformat(),
            stdout_bytes=len(stdout),
            stderr_bytes=len(stderr),
            result_digest=_sha256(stdout + b"\0" + stderr),
            failure_kind="timeout",
        )

    combined = completed.stdout + b"\0" + completed.stderr
    return StepEvidence(
        action=action,
        status="passed" if completed.returncode == 0 else "failed",
        exit_code=completed.returncode,
        duration_ms=round((time.monotonic() - started) * 1000),
        started_at=started_at,
        ended_at=datetime.now(timezone.utc).isoformat(),
        stdout_bytes=len(completed.stdout),
        stderr_bytes=len(completed.stderr),
        result_digest=_sha256(combined),
        failure_kind=None if completed.returncode == 0 else "process_failed",
    )


def _start_ios_video(video_path: Path, log_path: Path) -> tuple[StepEvidence, RunningIosVideo | None]:
    started_at = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    command = [
        "xcrun",
        "simctl",
        "io",
        "booted",
        "recordVideo",
        "--codec",
        "h264",
        str(video_path),
    ]
    log_handle = log_path.open("wb")
    process = subprocess.Popen(
        command,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    time.sleep(0.25)
    exit_code = process.poll()
    if exit_code is not None:
        log_handle.close()
        log_bytes = log_path.read_bytes() if log_path.exists() else b""
        return (
            StepEvidence(
                action="video_start",
                status="failed",
                exit_code=exit_code,
                duration_ms=round((time.monotonic() - started) * 1000),
                started_at=started_at,
                ended_at=datetime.now(timezone.utc).isoformat(),
                stdout_bytes=0,
                stderr_bytes=len(log_bytes),
                result_digest=_sha256(log_bytes),
                failure_kind="process_failed",
            ),
            None,
        )
    return (
        StepEvidence(
            action="video_start",
            status="passed",
            exit_code=None,
            duration_ms=round((time.monotonic() - started) * 1000),
            started_at=started_at,
            ended_at=datetime.now(timezone.utc).isoformat(),
            stdout_bytes=0,
            stderr_bytes=0,
            result_digest=_sha256("simctl-recordVideo-started".encode()),
            failure_kind=None,
        ),
        RunningIosVideo(
            process=process,
            log_handle=log_handle,
            log_path=log_path,
            video_path=video_path,
        ),
    )


def _stop_ios_video(recorder: RunningIosVideo, timeout_seconds: int) -> StepEvidence:
    started_at = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    timed_out = False
    if recorder.process.poll() is None:
        recorder.process.send_signal(signal.SIGINT)
        try:
            recorder.process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            recorder.process.terminate()
            try:
                recorder.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                recorder.process.kill()
                recorder.process.wait(timeout=5)
    recorder.log_handle.close()
    log_bytes = recorder.log_path.read_bytes() if recorder.log_path.exists() else b""
    video_bytes = recorder.video_path.read_bytes() if recorder.video_path.exists() else b""
    valid_mp4 = len(video_bytes) > 32 and b"ftyp" in video_bytes[:32]
    success = not timed_out and valid_mp4
    return StepEvidence(
        action="video_stop",
        status="passed" if success else "failed",
        exit_code=recorder.process.returncode,
        duration_ms=round((time.monotonic() - started) * 1000),
        started_at=started_at,
        ended_at=datetime.now(timezone.utc).isoformat(),
        stdout_bytes=0,
        stderr_bytes=len(log_bytes),
        result_digest=_sha256(video_bytes + b"\0" + log_bytes),
        failure_kind=None if success else ("timeout" if timed_out else "invalid_artifact"),
    )


def _action_evidence(
    step: StepEvidence,
    *,
    platform: str,
    app_id_hash: str,
    device_hash: str,
    previous_digest: str | None,
    artifact_ids: list[str],
    dry_run: bool,
) -> dict[str, object]:
    mutating = step.action in {"install", "open", "close"}
    captures_artifact = step.action in {"screenshot", "video_start", "video_stop"}
    action_name = (
        "phoneUseCapture"
        if captures_artifact
        else "phoneUseAct"
        if mutating
        else "phoneUseObserve"
    )
    digest_source = (
        f"{step.action}|{step.started_at}|{step.result_digest or 'planned'}".encode()
    )
    return {
        "evidenceId": _safe_id("external-phone-use", _sha256(digest_source)),
        "actionName": action_name,
        "paramsSummary": f"external agent-device {step.action}",
        "startedAt": step.started_at,
        "endedAt": step.ended_at,
        "durationMs": step.duration_ms,
        "success": step.status in {"passed", "planned"},
        "artifactPaths": [],
        "urls": [],
        "logs": [
            "External agent-device output withheld; digest and byte counts retained."
        ],
        **({"exitCode": step.exit_code} if step.exit_code is not None else {}),
        **({"failureKind": step.failure_kind} if step.failure_kind else {}),
        "recoveryActions": (
            []
            if step.failure_kind is None
            else ["Run agent-device doctor and retry the failed bounded QA step."]
        ),
        "metadata": {
            "provider": {
                "type": "agentDeviceQa",
                "name": "external agent-device",
                "pinnedVersion": PINNED_AGENT_DEVICE_VERSION,
            },
            "deviceAction": step.action,
            "approval": {
                "required": mutating or captures_artifact,
                "granted": mutating or captures_artifact,
                "source": "explicit_cli_invocation"
                if mutating or captures_artifact
                else "none",
            },
            "snapshotEvidence": {
                "preDigest": previous_digest,
                "postDigest": step.result_digest,
            },
            "surface": {"packageNameHash": app_id_hash},
            "artifactIds": artifact_ids,
            "device": {
                "platform": platform,
                "selectorHash": device_hash,
            },
            "redaction": {
                "rawStdoutStored": False,
                "rawStderrStored": False,
                "rawTextIncluded": False,
                "credentialValueStored": False,
            },
            "execution": {
                "status": step.status,
                "dryRun": dry_run,
                "stdoutBytes": step.stdout_bytes,
                "stderrBytes": step.stderr_bytes,
                "resultDigest": step.result_digest,
                "countsAsExperiment": False,
                "countsAsStrategyAblationResult": False,
            },
        },
    }


def _selector_args(platform: str, device: str | None) -> list[str]:
    if not device:
        return []
    return ["--serial", device] if platform == "android" else ["--device", device]


def _capture_path(
    *,
    platform: str,
    output_path: Path,
    approved: bool,
    sensitive_flow: bool,
    dry_run: bool,
) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    """Stage iOS simctl captures on the system volume.

    CoreSimulator may reject direct writes to an external workspace volume even
    when the invoking host process can write there. The reviewed artifact is
    copied to ``output_path`` only after the capture command succeeds.
    """
    if platform != "ios" or not approved or sensitive_flow or dry_run:
        return output_path, None
    staging = tempfile.TemporaryDirectory(prefix="mobilecode-ios-capture-")
    return Path(staging.name) / output_path.name, staging


def build_plan(args: argparse.Namespace, screenshot_path: Path) -> list[tuple[str, list[str]]]:
    binary = args.agent_device_bin
    selector = _selector_args(args.platform, args.device)
    common = ["--platform", args.platform, "--session", args.session, *selector]
    plan: list[tuple[str, list[str]]] = [
        ("doctor", [binary, "doctor"]),
        ("devices", [binary, "devices", "--platform", args.platform, "--json"]),
        ("apps", [binary, "apps", "--platform", args.platform, *selector, "--json"]),
    ]
    if args.app_binary:
        plan.append(
            (
                "install",
                [
                    binary,
                    "install",
                    args.app_id,
                    args.app_binary,
                    *common,
                    "--json",
                ],
            )
        )
    plan.extend(
        [
            ("open", [binary, "open", args.app_id, *common, "--relaunch", "--json"]),
            ("capabilities", [binary, "capabilities", *common, "--json"]),
            ("snapshot", [binary, "snapshot", "-i", *common, "--json"]),
        ]
    )
    if args.approve_artifacts and not args.sensitive_flow:
        plan.append(
            (
                "screenshot",
                [
                    binary,
                    "screenshot",
                    str(screenshot_path),
                    "--max-size",
                    "1440",
                    *common,
                    "--json",
                ],
            )
        )
    plan.append(("close", [binary, "close", *common, "--json"]))
    return plan


def _validate_args(args: argparse.Namespace) -> None:
    if args.sensitive_flow and (args.approve_artifacts or args.approve_video):
        raise ValueError(
            "--sensitive-flow forbids screenshots, video, logs, and other artifacts; "
            "remove --approve-artifacts and --approve-video"
        )
    if args.approve_video and not args.approve_artifacts:
        raise ValueError("--approve-video requires --approve-artifacts")
    if args.approve_video and args.platform != "ios":
        raise ValueError("--approve-video currently supports iOS Simulator only")
    if not args.dry_run and shutil.which(args.agent_device_bin) is None:
        raise ValueError(
            f"agent-device executable not found: {args.agent_device_bin}. "
            f"Install agent-device@{PINNED_AGENT_DEVICE_VERSION} on the Mac/CI host."
        )
    if args.app_binary and not args.dry_run and not Path(args.app_binary).exists():
        raise ValueError(f"app binary does not exist: {args.app_binary}")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--app-binary")
    parser.add_argument("--device")
    parser.add_argument("--session", default=DEFAULT_SESSION)
    parser.add_argument("--output", default=".artifacts/agent-device-qa")
    parser.add_argument("--agent-device-bin", default="agent-device")
    parser.add_argument("--timeout-seconds", type=int, default=90)
    parser.add_argument("--approve-artifacts", action="store_true")
    parser.add_argument(
        "--approve-video",
        action="store_true",
        help="Record the booted iOS Simulator screen; never use for sensitive flows.",
    )
    parser.add_argument("--sensitive-flow", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    try:
        _validate_args(args)
    except ValueError as error:
        parser.error(str(error))

    run_started_at = datetime.now(timezone.utc).isoformat()
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    screenshot_path = output_dir / "mobilecode-screen.png"
    screenshot_capture_path, capture_staging = _capture_path(
        platform=args.platform,
        output_path=screenshot_path,
        approved=args.approve_artifacts,
        sensitive_flow=args.sensitive_flow,
        dry_run=args.dry_run,
    )
    video_staging: tempfile.TemporaryDirectory[str] | None = None
    video_capture_path: Path | None = None
    video_log_path: Path | None = None
    video_path = output_dir / "mobilecode-device-screen.mp4"
    if args.approve_video and not args.dry_run:
        video_staging = tempfile.TemporaryDirectory(prefix="mobilecode-ios-video-")
        video_capture_path = Path(video_staging.name) / video_path.name
        video_log_path = Path(video_staging.name) / "recording.log"
    plan = build_plan(args, screenshot_capture_path)
    steps: list[StepEvidence] = []
    opened = False
    video_recorder: RunningIosVideo | None = None

    for action, command in plan:
        if action == "close" and not opened and not args.dry_run:
            continue
        if action == "close" and video_recorder is not None:
            steps.append(_stop_ios_video(video_recorder, args.timeout_seconds))
            video_recorder = None
        evidence = _run(
            command,
            action=action,
            dry_run=args.dry_run,
            timeout_seconds=args.timeout_seconds,
        )
        steps.append(evidence)
        if action == "open" and evidence.status == "passed":
            opened = True
            if args.approve_video and not args.dry_run:
                assert video_capture_path is not None
                assert video_log_path is not None
                video_start, video_recorder = _start_ios_video(
                    video_capture_path,
                    video_log_path,
                )
                steps.append(video_start)
                if video_start.status == "failed":
                    evidence = video_start
        if evidence.status == "failed" and action not in {"close"}:
            if video_recorder is not None:
                steps.append(_stop_ios_video(video_recorder, args.timeout_seconds))
                video_recorder = None
            if opened:
                close_command = next(command for name, command in plan if name == "close")
                steps.append(
                    _run(
                        close_command,
                        action="close",
                        dry_run=False,
                        timeout_seconds=args.timeout_seconds,
                    )
                )
            break

    if video_recorder is not None:
        steps.append(_stop_ios_video(video_recorder, args.timeout_seconds))
        video_recorder = None

    if screenshot_capture_path.exists() and screenshot_capture_path != screenshot_path:
        shutil.copy2(screenshot_capture_path, screenshot_path)
    if capture_staging is not None:
        capture_staging.cleanup()
    video_capture_valid = any(
        step.action == "video_stop" and step.status == "passed" for step in steps
    )
    if (
        video_capture_valid
        and video_capture_path is not None
        and video_capture_path.exists()
    ):
        shutil.copy2(video_capture_path, video_path)
    if video_staging is not None:
        video_staging.cleanup()

    artifacts: list[dict[str, object]] = []
    if screenshot_path.exists() and not args.sensitive_flow:
        screenshot_digest = _sha256(screenshot_path.read_bytes())
        artifacts.append(
            {
                "artifactId": _safe_id("screenshot", screenshot_digest),
                "kind": "screenshot",
                "path": screenshot_path.name,
                "sha256": screenshot_digest,
                "localOnly": True,
                "shareableWithoutReview": False,
            }
        )
    if args.approve_video and video_capture_valid and video_path.exists():
        video_digest = _sha256(video_path.read_bytes())
        artifacts.append(
            {
                "artifactId": _safe_id("video", video_digest),
                "kind": "video",
                "path": video_path.name,
                "sha256": video_digest,
                "localOnly": True,
                "shareableWithoutReview": False,
            }
        )

    failed = any(step.status == "failed" for step in steps)
    device_fingerprint = _sha256((args.device or "auto").encode("utf-8"))[:16]
    app_fingerprint = _sha256(args.app_id.encode("utf-8"))[:16]
    serialized_steps: list[dict[str, object]] = []
    previous_digest: str | None = None
    for step in steps:
        step_artifact_ids = (
            [
                str(artifact["artifactId"])
                for artifact in artifacts
                if artifact["kind"] == "screenshot"
            ]
            if step.action == "screenshot"
            else [
                str(artifact["artifactId"])
                for artifact in artifacts
                if artifact["kind"] == "video"
            ]
            if step.action == "video_stop"
            else []
        )
        serialized_steps.append(
            _action_evidence(
                step,
                platform=args.platform,
                app_id_hash=app_fingerprint,
                device_hash=device_fingerprint,
                previous_digest=previous_digest,
                artifact_ids=step_artifact_ids,
                dry_run=args.dry_run,
            )
        )
        previous_digest = step.result_digest or previous_digest
    manifest = {
        "schemaVersion": 1,
        "provider": {
            "type": "agentDeviceQa",
            "name": "external agent-device",
            "pinnedVersion": PINNED_AGENT_DEVICE_VERSION,
            "embeddedInApk": False,
        },
        "platform": args.platform,
        "sessionPurpose": "mobilecode_phone_use_qa",
        "appIdHash": app_fingerprint,
        "deviceSelectorHash": device_fingerprint,
        "approval": {
            "artifactCaptureApproved": args.approve_artifacts,
            "source": "explicit_cli_flag" if args.approve_artifacts else "none",
            "videoCaptureApproved": args.approve_video,
        },
        "redaction": {
            "sensitiveFlow": args.sensitive_flow,
            "rawStdoutStored": False,
            "rawStderrStored": False,
            "accessibilityLabelsStored": False,
            "credentialValuesStored": False,
            "cookiesStored": False,
            "tokensStored": False,
            "logsEnabled": False,
            "videoEnabled": any(artifact["kind"] == "video" for artifact in artifacts),
        },
        "status": "failed" if failed else ("planned" if args.dry_run else "passed"),
        "steps": serialized_steps,
        "artifactIds": [artifact["artifactId"] for artifact in artifacts],
        "artifacts": artifacts,
        "startedAt": run_started_at,
        "endedAt": datetime.now(timezone.utc).isoformat(),
        "countsAsExperiment": False,
        "countsAsStrategyAblationResult": False,
    }
    manifest_path = output_dir / "action-evidence.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"status": manifest["status"], "evidence": str(manifest_path)}))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
