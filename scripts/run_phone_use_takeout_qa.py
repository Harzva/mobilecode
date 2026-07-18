#!/usr/bin/env python3
"""Run a non-production takeout-like flow through MobileCode Phone Use.

The debug-only bridge is protected by Android's DUMP permission and is reached
only from adb shell. Evidence stores digests and assertion outcomes, never raw
bridge output, labels, typed values, package names, serials, or device paths.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import shutil
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence


PACKAGE_NAME = "com.mobilecode.app"
FIXTURE_COMPONENT = f"{PACKAGE_NAME}/.PhoneUseTakeoutQaActivity"
BRIDGE_COMPONENT = f"{PACKAGE_NAME}/.PhoneUseQaBridgeReceiver"
RESULT_DIRECTORY = "files/phone-use-qa"


class QaFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class Step:
    name: str
    status: str
    duration_ms: int
    started_at: str
    request_digest: str
    result_digest: str
    failure_kind: str | None

    def evidence(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "durationMs": self.duration_ms,
            "startedAt": self.started_at,
            "requestDigest": self.request_digest,
            "resultDigest": self.result_digest,
            **({"failureKind": self.failure_kind} if self.failure_kind else {}),
            "rawRequestStored": False,
            "rawResultStored": False,
        }


def _canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _run(command: Sequence[str], *, timeout: float = 30) -> subprocess.CompletedProcess[bytes]:
    completed = subprocess.run(
        list(command),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if completed.returncode != 0:
        raise QaFailure(f"host_command_failed:{Path(command[0]).name}")
    return completed


class PhoneUseBridge:
    def __init__(self, adb: str, serial: str) -> None:
        self.adb = adb
        self.serial = serial
        self.steps: list[Step] = []

    def adb_command(self, *arguments: str, timeout: float = 30) -> subprocess.CompletedProcess[bytes]:
        return _run([self.adb, "-s", self.serial, *arguments], timeout=timeout)

    def request(self, name: str, action: dict[str, Any], *, timeout: float = 15) -> dict[str, Any]:
        request_id = f"qa-{uuid.uuid4().hex}"
        encoded = base64.urlsafe_b64encode(_canonical(action)).decode().rstrip("=")
        started_at = datetime.now(timezone.utc).isoformat()
        started = time.monotonic()
        failure_kind: str | None = None
        result: dict[str, Any] = {}
        try:
            self.adb_command(
                "shell",
                "am",
                "broadcast",
                "-n",
                BRIDGE_COMPONENT,
                "--es",
                "request_id",
                request_id,
                "--es",
                "action_b64",
                encoded,
            )
            relative_path = f"{RESULT_DIRECTORY}/{request_id}.json"
            deadline = time.monotonic() + timeout
            payload: dict[str, Any] | None = None
            while time.monotonic() < deadline:
                completed = subprocess.run(
                    [
                        self.adb,
                        "-s",
                        self.serial,
                        "shell",
                        "run-as",
                        PACKAGE_NAME,
                        "cat",
                        relative_path,
                    ],
                    check=False,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    timeout=5,
                )
                if completed.returncode == 0 and completed.stdout:
                    payload = json.loads(completed.stdout)
                    break
                time.sleep(0.1)
            if payload is None or payload.get("requestId") != request_id:
                raise QaFailure("qa_bridge_result_timeout")
            self.adb_command(
                "shell", "run-as", PACKAGE_NAME, "rm", "-f", relative_path
            )
            decoded = payload.get("result")
            if not isinstance(decoded, dict):
                raise QaFailure("qa_bridge_invalid_result")
            result = decoded
            failure_kind = decoded.get("failureKind")
            return result
        except (QaFailure, json.JSONDecodeError) as error:
            failure_kind = str(error).split(":", 1)[0]
            raise
        finally:
            self.steps.append(
                Step(
                    name=name,
                    status="failed" if failure_kind and not result else "passed",
                    duration_ms=round((time.monotonic() - started) * 1000),
                    started_at=started_at,
                    request_digest=_sha256(_canonical(action)),
                    result_digest=_sha256(_canonical(result)),
                    failure_kind=failure_kind,
                )
            )


def _require(condition: bool, failure_kind: str) -> None:
    if not condition:
        raise QaFailure(failure_kind)


def _snapshot(bridge: PhoneUseBridge, name: str) -> dict[str, Any]:
    result = bridge.request(name, {"type": "semantic_snapshot"})
    _require(result.get("status") == "passed", "semantic_snapshot_failed")
    snapshot = result.get("snapshot")
    _require(isinstance(snapshot, dict), "semantic_snapshot_missing")
    _require(snapshot.get("redactionApplied") is True, "snapshot_not_redacted")
    _require(snapshot.get("rawTextIncluded") is False, "snapshot_contains_raw_text")
    return snapshot


def _node(snapshot: dict[str, Any], label: str) -> dict[str, Any]:
    nodes = snapshot.get("interactiveNodes")
    if not isinstance(nodes, list):
        raise QaFailure("semantic_nodes_missing")
    for node in nodes:
        if isinstance(node, dict) and node.get("label") == label:
            return node
    raise QaFailure("semantic_target_missing")


def _ref(snapshot: dict[str, Any], label: str) -> str:
    node = _node(snapshot, label)
    generation = snapshot.get("refsGeneration")
    _require(isinstance(generation, int), "semantic_generation_missing")
    return f"{node['ref']}~s{generation}"


def _wait_stage(bridge: PhoneUseBridge, expected: str, timeout: float = 8) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    latest: dict[str, Any] = {}
    while time.monotonic() < deadline:
        latest = bridge.request("observe_fixture_state", {"type": "qa_state"})
        if latest.get("stage") == expected:
            time.sleep(0.35)
            return latest
        time.sleep(0.15)
    raise QaFailure("fixture_stage_timeout")


def _tap_label(bridge: PhoneUseBridge, label: str, name: str) -> None:
    for attempt in range(3):
        snapshot = _snapshot(bridge, f"{name}_snapshot_{attempt + 1}")
        result = bridge.request(
            name,
            {"type": "tap_ref", "ref": _ref(snapshot, label), "approved": True},
        )
        if result.get("status") == "passed":
            return
        if result.get("failureKind") not in {
            "ref_frame_expired",
            "ref_generation_mismatch",
            "ref_target_changed",
        }:
            break
    raise QaFailure("semantic_tap_failed")


def _write_manifest(
    path: Path,
    *,
    serial: str,
    status: str,
    steps: list[Step],
    assertions: list[str],
    artifacts: list[dict[str, Any]],
    failure_kind: str | None,
) -> None:
    manifest = {
        "schemaVersion": 1,
        "suite": "phone-use-takeout-sandbox",
        "status": status,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "target": {
            "platform": "android",
            "packageNameHash": _sha256(PACKAGE_NAME.encode())[:16],
            "deviceHash": _sha256(serial.encode())[:16],
            "debugOnly": True,
            "fixtureUsesFakeData": True,
        },
        "safety": {
            "realMerchantUsed": False,
            "realAccountUsed": False,
            "realAddressUsed": False,
            "realOrderCommitted": False,
            "paymentAttempted": False,
            "finalTransactionRequiresSeparateApproval": True,
        },
        "assertions": assertions,
        "steps": [step.evidence() for step in steps],
        "artifacts": artifacts,
        "redaction": {
            "rawBridgeOutputStored": False,
            "rawAccessibilityTreeStored": False,
            "typedValuesStored": False,
            "credentialValuesStored": False,
            "packageNameStored": False,
            "deviceSerialStored": False,
        },
        **({"failureKind": failure_kind} if failure_kind else {}),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def finalize_existing_artifacts(args: argparse.Namespace) -> int:
    if not args.approve_artifacts:
        raise QaFailure("artifact_finalization_requires_approval")
    output = Path(args.output).resolve()
    manifest_path = output / "action-evidence.json"
    if not manifest_path.is_file():
        raise QaFailure("action_evidence_manifest_missing")
    manifest = json.loads(manifest_path.read_text())
    artifacts = manifest.setdefault("artifacts", [])
    for item in artifacts:
        if not isinstance(item, dict) or not isinstance(item.get("fileName"), str):
            continue
        existing_path = output / item["fileName"]
        if not existing_path.is_file():
            continue
        existing_content = existing_path.read_bytes()
        _require(
            item.get("sha256") == _sha256(existing_content),
            "existing_artifact_digest_mismatch",
        )
        item["bytes"] = len(existing_content)
    existing_names = {
        item.get("fileName") for item in artifacts if isinstance(item, dict)
    }
    specifications = (
        ("phoneuse-takeout-sandbox.mp4", "screen_recording"),
        ("phoneuse-takeout-sandbox.gesture-telemetry.json", "gesture_telemetry"),
        ("phoneuse-takeout-logcat.txt", "reviewed_logcat"),
    )
    attached = 0
    for file_name, kind in specifications:
        path = output / file_name
        if not path.is_file() or file_name in existing_names:
            continue
        content = path.read_bytes()
        if kind == "screen_recording":
            _require(len(content) > 32 and b"ftyp" in content[:32], "invalid_video_artifact")
        elif kind == "gesture_telemetry":
            json.loads(content)
        elif kind == "reviewed_logcat":
            lowered = content.lower()
            for forbidden in (b"authorization", b"bearer ", b"cookie=", b"password=", b"oauth"):
                _require(forbidden not in lowered, "logcat_sensitive_marker_detected")
        digest = _sha256(content)
        artifacts.append(
            {
                "artifactId": f"phone-use-{kind}-{digest[:16]}",
                "kind": kind,
                "fileName": file_name,
                "sha256": digest,
                "bytes": len(content),
                "localOnly": True,
                "shareableWithoutReview": False,
            }
        )
        attached += 1
    manifest["artifactFinalizedAt"] = datetime.now(timezone.utc).isoformat()
    manifest["artifactFinalization"] = {
        "approved": True,
        "attachedCount": len(artifacts),
        "newlyAttachedCount": attached,
        "rawArtifactContentEmbedded": False,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": "passed", "attachedCount": attached, "manifest": str(manifest_path)}))
    return 0


def observe_lifecycle(args: argparse.Namespace) -> int:
    if not args.expected_lifecycle or args.expect_background_restricted is None:
        raise QaFailure("lifecycle_expectation_missing")
    adb = args.adb or shutil.which("adb")
    if not adb:
        raise QaFailure("adb_not_found")
    output = Path(args.output).resolve()
    manifest_path = output / "action-evidence.json"
    if not manifest_path.is_file():
        raise QaFailure("action_evidence_manifest_missing")
    bridge = PhoneUseBridge(adb, args.serial)
    action = {
        "type": "qa_mark_recovery" if args.mark_recovery_before_observe else "qa_state"
    }
    observed = bridge.request("observe_phone_use_lifecycle", action)
    status = observed if args.mark_recovery_before_observe else observed.get("phoneUseStatus")
    _require(isinstance(status, dict), "phone_use_lifecycle_status_missing")
    expected_restricted = args.expect_background_restricted == "true"
    _require(status.get("lifecycleState") == args.expected_lifecycle, "lifecycle_state_mismatch")
    _require(
        status.get("backgroundRestricted") is expected_restricted,
        "background_restriction_flag_mismatch",
    )
    _require(status.get("serviceConnected") is True, "accessibility_service_not_ready")

    safe_observation = {
        "lifecycleState": status.get("lifecycleState"),
        "backgroundRestricted": status.get("backgroundRestricted"),
        "serviceConnected": status.get("serviceConnected"),
        "blockedReason": status.get("blockedReason"),
        "observedAt": datetime.now(timezone.utc).isoformat(),
    }
    safe_observation["observationDigest"] = _sha256(_canonical(safe_observation))
    manifest = json.loads(manifest_path.read_text())
    manifest.setdefault("lifecycleObservations", []).append(safe_observation)
    assertion = {
        "background_restricted": "background_restricted_observed",
        "recovering": "recovering_observed_after_explicit_request",
        "ready": "ready_observed_after_background_recovery",
    }.get(args.expected_lifecycle, f"lifecycle_{args.expected_lifecycle}_observed")
    if assertion not in manifest.setdefault("assertions", []):
        manifest["assertions"].append(assertion)
    manifest.setdefault("steps", []).extend(step.evidence() for step in bridge.steps)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(
        json.dumps(
            {
                "status": "passed",
                "lifecycleState": args.expected_lifecycle,
                "backgroundRestricted": expected_restricted,
                "manifest": str(manifest_path),
            }
        )
    )
    return 0


def run(args: argparse.Namespace) -> int:
    adb = args.adb or shutil.which("adb")
    if not adb:
        raise QaFailure("adb_not_found")
    output = Path(args.output).resolve()
    manifest_path = output / "action-evidence.json"
    bridge = PhoneUseBridge(adb, args.serial)
    assertions: list[str] = []
    artifacts: list[dict[str, Any]] = []
    failure_kind: str | None = None

    try:
        bridge.adb_command("get-state")
        bridge.adb_command("shell", "run-as", PACKAGE_NAME, "true")
        initial_state = bridge.request("check_phone_use_ready", {"type": "qa_state"})
        phone_status = initial_state.get("phoneUseStatus", {})
        _require(phone_status.get("serviceConnected") is True, "accessibility_service_not_ready")
        _require(phone_status.get("lifecycleState") == "ready", "phone_use_lifecycle_not_ready")
        assertions.append("accessibility_service_ready")

        bridge.adb_command("shell", "am", "start", "-W", "-n", FIXTURE_COMPONENT)
        _wait_stage(bridge, "search")
        stale_search_button = ""
        for attempt in range(3):
            initial = _snapshot(bridge, f"search_snapshot_{attempt + 1}")
            search_input = _ref(initial, "Search restaurants")
            stale_search_button = _ref(initial, "Search")
            text_result = bridge.request(
                "enter_fake_search",
                {
                    "type": "set_text_ref",
                    "ref": search_input,
                    "text": "noodles qa fake",
                    "approved": True,
                },
            )
            if text_result.get("status") == "passed":
                break
            if text_result.get("failureKind") not in {
                "ref_frame_expired",
                "ref_generation_mismatch",
                "ref_target_changed",
            }:
                break
        _require(text_result.get("status") == "passed", "set_text_ref_failed")
        stale_result = bridge.request(
            "reject_stale_search_ref",
            {"type": "tap_ref", "ref": stale_search_button, "approved": True},
        )
        _require(stale_result.get("failureKind") == "ref_frame_expired", "stale_ref_not_rejected")
        assertions.append("stale_ref_rejected_after_mutation")

        _tap_label(bridge, "Search", "submit_search")
        _wait_stage(bridge, "restaurants")
        _tap_label(bridge, "Golden Noodle Shop", "select_fake_restaurant")
        _wait_stage(bridge, "menu")
        _tap_label(bridge, "Add beef noodles", "add_fake_item")
        _wait_stage(bridge, "menu_cart")

        cart_snapshot = _snapshot(bridge, "cart_entry_snapshot")
        cart_node = _node(cart_snapshot, "Open cart")
        bounds = cart_node.get("bounds", {})
        coordinate_result = bridge.request(
            "open_cart_by_coordinate_contract",
            {
                "type": "tap",
                "x": bounds.get("centerX"),
                "y": bounds.get("centerY"),
                "approved": True,
            },
        )
        _require(coordinate_result.get("status") == "passed", "coordinate_tap_failed")
        _wait_stage(bridge, "cart")
        assertions.append("coordinate_tap_resolved_from_semantic_bounds")

        for attempt in range(3):
            note_snapshot = _snapshot(bridge, f"delivery_note_snapshot_{attempt + 1}")
            note_result = bridge.request(
                "enter_fake_delivery_note",
                {
                    "type": "set_text_ref",
                    "ref": _ref(note_snapshot, "Delivery note fake slot"),
                    "text": "QA fake note",
                    "approved": True,
                },
            )
            if note_result.get("status") == "passed":
                break
            if note_result.get("failureKind") not in {
                "ref_frame_expired",
                "ref_generation_mismatch",
                "ref_target_changed",
            }:
                break
        _require(note_result.get("status") == "passed", "delivery_note_input_failed")
        _tap_label(bridge, "Review order", "open_order_review")
        _wait_stage(bridge, "review")

        review_snapshot = _snapshot(bridge, "review_snapshot")
        contract = review_snapshot.get("coordinateContract", {})
        _require(contract.get("origin") == "top_left", "coordinate_origin_mismatch")
        _require(contract.get("sourceWidth") == contract.get("inputWidth"), "coordinate_width_mismatch")
        _require(contract.get("sourceHeight") == contract.get("inputHeight"), "coordinate_height_mismatch")
        assertions.append("coordinate_contract_consistent")

        final_ref = _ref(review_snapshot, "Confirm order")
        risk_preview = bridge.request(
            "classify_final_transaction_risk",
            {
                "type": "risk_preview",
                "requestedAction": "tap_ref",
                "ref": final_ref,
            },
        )
        risk = risk_preview.get("riskAssessment", {})
        _require(risk_preview.get("status") == "passed", "transaction_risk_preview_failed")
        _require(risk.get("trusted") is True, "transaction_risk_not_trusted")
        _require(
            risk.get("riskClass") == "externalTransaction",
            "final_transaction_risk_not_classified",
        )
        _require(len(str(risk.get("previewDigest", ""))) == 64, "preview_digest_invalid")
        _require(len(str(risk.get("frameDigest", ""))) == 64, "frame_digest_invalid")
        assertions.append("trusted_transaction_risk_classified")
        assertions.append("transaction_preview_digest_bound")

        expired_approval = bridge.request(
            "reject_changed_page_approval",
            {
                "type": "tap_ref",
                "ref": final_ref,
                "approved": True,
                "preconditionSnapshotDigest": "0" * 64,
            },
        )
        _require(
            expired_approval.get("failureKind") == "approval_preview_expired",
            "page_bound_approval_not_enforced",
        )
        assertions.append("approval_rejected_on_snapshot_digest_mismatch")

        blocked_commit = bridge.request(
            "reject_unapproved_final_commit",
            {"type": "tap_ref", "ref": final_ref},
        )
        _require(blocked_commit.get("failureKind") == "approval_required", "final_commit_not_gated")
        final_state = _wait_stage(bridge, "review")
        _require(final_state.get("commitAttempts") == 0, "transaction_commit_attempted")
        assertions.append("final_commit_blocked_without_separate_approval")
        assertions.append("zero_transaction_commit_attempts")

        sensitive_capture = bridge.request(
            "reject_sensitive_screenshot",
            {"type": "qa_capture_screenshot", "approved": True, "sensitiveFlow": True},
        )
        _require(
            sensitive_capture.get("failureKind") == "sensitive_artifact_capture_blocked",
            "sensitive_screenshot_not_blocked",
        )
        assertions.append("sensitive_screenshot_blocked")

        if args.approve_artifacts:
            capture = bridge.request(
                "capture_reviewed_sandbox_screenshot",
                {"type": "qa_capture_screenshot", "approved": True, "sensitiveFlow": False},
            )
            _require(capture.get("status") == "passed", "approved_screenshot_failed")
            device_path = capture.get("artifactPath")
            _require(isinstance(device_path, str), "approved_screenshot_path_missing")
            image = bridge.adb_command(
                "exec-out", "run-as", PACKAGE_NAME, "cat", device_path
            ).stdout
            _require(image.startswith(b"\x89PNG\r\n\x1a\n"), "approved_screenshot_invalid")
            output.mkdir(parents=True, exist_ok=True)
            screenshot_path = output / "phoneuse-takeout-sandbox.png"
            screenshot_path.write_bytes(image)
            host_digest = _sha256(image)
            _require(host_digest == capture.get("sha256"), "approved_screenshot_digest_mismatch")
            bridge.adb_command("shell", "run-as", PACKAGE_NAME, "rm", "-f", device_path)
            artifacts.append(
                {
                    "artifactId": capture.get("artifactId"),
                    "kind": "screenshot",
                    "fileName": screenshot_path.name,
                    "sha256": host_digest,
                    "localOnly": True,
                    "shareableWithoutReview": False,
                }
            )
            assertions.append("approved_screenshot_digest_verified")

        status = "passed"
        return_code = 0
    except (QaFailure, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        status = "failed"
        failure_kind = str(error).split(":", 1)[0] or error.__class__.__name__
        return_code = 1
    finally:
        _write_manifest(
            manifest_path,
            serial=args.serial,
            status=status,
            steps=bridge.steps,
            assertions=assertions,
            artifacts=artifacts,
            failure_kind=failure_kind,
        )

    print(json.dumps({"status": status, "failureKind": failure_kind, "manifest": str(manifest_path)}))
    return return_code


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb")
    parser.add_argument("--output", required=True)
    parser.add_argument("--approve-artifacts", action="store_true")
    parser.add_argument("--finalize-existing-artifacts", action="store_true")
    parser.add_argument("--observe-lifecycle", action="store_true")
    parser.add_argument("--expected-lifecycle")
    parser.add_argument(
        "--expect-background-restricted", choices=("true", "false")
    )
    parser.add_argument("--mark-recovery-before-observe", action="store_true")
    return parser.parse_args(argv)


if __name__ == "__main__":
    try:
        parsed = parse_args(sys.argv[1:])
        if parsed.observe_lifecycle:
            raise SystemExit(observe_lifecycle(parsed))
        if parsed.finalize_existing_artifacts:
            raise SystemExit(finalize_existing_artifacts(parsed))
        raise SystemExit(run(parsed))
    except QaFailure as error:
        print(json.dumps({"status": "failed", "failureKind": str(error)}))
        raise SystemExit(1)
