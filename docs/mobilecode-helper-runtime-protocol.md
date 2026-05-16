# MobileCode Helper Runtime Protocol

MobileCode Helper is a local Android companion daemon that can expose shell-like execution without tying the Flutter app directly to Termux. The Flutter app talks to the helper through localhost HTTP.

## Endpoint Base

Default base URL:

```text
http://127.0.0.1:8765
```

## Prototype Daemon

The current deployable prototype has two forms:

- `MobileCodeHelperService.kt`: Android foreground-service prototype injected by `mobile_agent/tooling/prepare_android_project.py`.
- `mobilecode_helper_daemon.py`: small Python daemon that can run inside Termux while the standalone Helper APK is still being built.

The Flutter app can start the Android service through the `mobilecode/system_tools` method channel:

```text
startHelperService
stopHelperService
helperServiceStatus
```

The Termux/Python fallback can be started with:

```bash
cd mobile_agent
./tooling/run_mobilecode_helper_daemon.sh
```

Equivalent direct command:

```bash
python3 tooling/mobilecode_helper_daemon.py \
  --host 127.0.0.1 \
  --port 8765 \
  --workspace-root "$HOME/mobilecode_projects" \
  --auth-token "$MOBILECODE_HELPER_TOKEN"
```

Both prototypes implement `/v1/health`, `/v1/execute`, `/v1/execute/stream`, `/v1/project/preflight`, `/v1/tasks/current`, `/v1/tasks`, `/v1/tasks/:id/logs`, `/v1/task/stop`, and `/v1/tasks/:id/stop`. Both prototypes intentionally run allowlisted commands without shell expansion and reject working directories outside the configured workspace boundary.

## Localhost Auth

The Python daemon supports an optional shared token:

```http
X-MobileCode-Token: <token>
Authorization: Bearer <token>
```

If `--auth-token` or `MOBILECODE_HELPER_TOKEN` is set, every endpoint requires one of those headers and returns HTTP 401 with `failureKind: authFailed` when the token is missing or invalid. The Android foreground-service prototype currently reports `authRequired: false`; the next APK iteration should pass an app-generated token to the Flutter provider before enabling enforcement.

## Health

```http
GET /v1/health
```

Response:

```json
{
  "name": "MobileCode Helper",
  "available": true,
  "ready": true,
  "status": "Helper foreground service is running.",
  "protocolVersion": 1,
  "authRequired": true,
  "capabilities": {
    "shell": true,
    "git": true,
    "node": false,
    "python": false,
    "flutter": false,
    "androidBuild": false,
    "pty": true,
    "backgroundService": true,
    "webViewPreview": true,
    "cloudBuild": false
  },
  "taskRegistry": {
    "runningCount": 0,
    "maxTasks": 50
  },
  "missingDependencies": [],
  "recoveryActions": []
}
```

## Command Execution

```http
POST /v1/execute
Content-Type: application/json
```

Request:

```json
{
  "command": "git status",
  "cwd": "/storage/emulated/0/Documents/MobileCode/project",
  "env": {},
  "timeoutMs": 120000
}
```

Response:

```json
{
  "command": "git status",
  "stdout": "",
  "stderr": "",
  "exitCode": 0,
  "durationMs": 42,
  "taskId": "task-1715780000000",
  "failureKind": "none"
}
```

## Project Preflight

Project preflight is a structured file inspection endpoint. The app should prefer it over arbitrary shell probes when the active runtime is MobileCode Helper.

```http
POST /v1/project/preflight
Content-Type: application/json
```

Request:

```json
{
  "cwd": "/helper/workspace/project"
}
```

Response:

```json
{
  "success": true,
  "cwd": "/helper/workspace/project",
  "detectedFiles": ["./package.json", "./.git"]
}
```

The helper currently detects `package.json`, `pubspec.yaml`, `requirements.txt`, `pyproject.toml`, and `.git` within depth 2. MobileCode maps those markers to Node/npm, Flutter, Python, and Git-aware action flows before running Install/Test/Preview.

## Streaming Execution

```http
POST /v1/execute/stream
Content-Type: application/json
Accept: application/x-ndjson
```

Each response line is a JSON object:

```json
{"type":"stdout","data":"build output"}
{"type":"stderr","data":"warning output"}
{"type":"exit","exitCode":0,"durationMs":1200,"taskId":"task-1715780000000"}
```

## Task Recovery

```http
GET /v1/tasks/current
```

Response:

```json
{
  "running": false,
  "taskId": "task-1715780000000",
  "command": "npm test",
  "logs": ["stdout: test ok"],
  "task": {
    "id": "task-1715780000000",
    "taskId": "task-1715780000000",
    "command": "npm test",
    "cwd": "/helper/workspace/project",
    "status": "succeeded",
    "startedAtMs": 1715780000000,
    "finishedAtMs": 1715780001200,
    "exitCode": 0,
    "durationMs": 1200,
    "logs": ["stdout: test ok"],
    "failureKind": "none"
  }
}
```

Task status values are:

```text
queued, running, succeeded, failed, cancelled, timedOut, lost, unknown
```

Task failure kinds are:

```text
none, timeout, cancelled, dependencyMissing, commandBlocked, cwdOutsideWorkspace, authFailed, processFailed, runtimeLost, unknown
```

Task history:

```http
GET /v1/tasks?limit=20
```

Response:

```json
{
  "tasks": [
    {
      "id": "task-1715780000000",
      "status": "succeeded",
      "command": "npm test",
      "failureKind": "none",
      "logs": ["stdout: test ok"]
    }
  ],
  "count": 1
}
```

Task logs:

```http
GET /v1/tasks/task-1715780000000/logs?limit=200
```

Response:

```json
{
  "taskId": "task-1715780000000",
  "logs": ["stdout: test ok"]
}
```

Task cancellation:

```http
POST /v1/task/stop
```

Compatibility endpoint for the currently running task:

Response:

```json
{
  "success": true,
  "stopped": true
}
```

Task ID endpoint for queue-ready clients:

```http
POST /v1/tasks/task-1715780000000/stop
```

Helper implementations must treat tasks as a registry keyed by task ID, not as a single global process. A task record owns its command, status, timing, exit code, failure kind, and recent logs. Running process handles are stored in an in-memory `taskId -> process` map, while task snapshots are persisted for recovery.

If a matching task is running, the helper should terminate only that task's process, mark the task `cancelled`, set `failureKind` to `cancelled`, append a stop log line, persist the task snapshot, and make the updated state visible from `/v1/tasks/current`, `/v1/tasks`, and `/v1/tasks/:id/logs`. Other running tasks must remain running. If the matching task exists but is not running, the endpoint should return `success: true` with `stopped: false` and the persisted `task`. If the task ID is unknown, return HTTP 404 with `success: false`.

The Android service persists task history under its app-private runtime directory. The Termux/Python prototype persists the latest task as `.mobilecode-helper-task.json` and the recoverable task database as `.mobilecode-helper-tasks.json` in the configured workspace root. If the helper restarts while a task is marked `running`, it must return `lost`/`runtimeLost` with a recovery error instead of pretending the process is still alive.

## Workspace Sync

```http
POST /v1/sync
```

Request:

```json
{
  "sourcePath": "/app/workspace/project",
  "targetPath": "/helper/workspace/project"
}
```

Response:

```json
{
  "success": true,
  "sourcePath": "/app/workspace/project",
  "targetPath": "/helper/workspace/project"
}
```

## Build And App Lifecycle

Required endpoints:

```text
POST /v1/build/web
POST /v1/build/apk
POST /v1/apk/install
POST /v1/app/launch
POST /v1/app/uninstall
POST /v1/task/stop
POST /v1/tasks/:id/stop
```

Build response:

```json
{
  "success": true,
  "outputPath": "/helper/workspace/project/build/web",
  "buildTimeMs": 12000,
  "fileSize": 123456
}
```

The helper should reject unsafe paths, enforce command policy, stream logs promptly, and keep long-running work in a foreground service.
