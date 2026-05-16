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
  --workspace-root "$HOME/mobilecode_projects"
```

Both prototypes implement `/v1/health`, `/v1/execute`, `/v1/execute/stream`, `/v1/tasks/current`, and `/v1/task/stop`. Both prototypes intentionally run allowlisted commands without shell expansion and reject working directories outside the configured workspace boundary.

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
  "taskId": "task-1715780000000"
}
```

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
    "logs": ["stdout: test ok"]
  }
}
```

Task status values are:

```text
queued, running, succeeded, failed, cancelled, timedOut, lost, unknown
```

The Android service persists the latest task snapshot under its app-private runtime directory. The Termux/Python prototype persists the same shape as `.mobilecode-helper-task.json` in the configured workspace root. If the helper restarts while a task is marked `running`, it must return `lost` with a recovery error instead of pretending the process is still alive.

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
