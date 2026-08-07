# HyperFrames CLI Compatibility

MobileCode exposes a bounded HyperFrames CLI profile through the existing CLI
Hub and Alpine Linux runtime. The upstream CLI remains the source of truth for
the command syntax: [HyperFrames CLI documentation](https://hyperframes.heygen.com/packages/cli).

## Supported Slice

The bundled `hyperframes-cli` entry currently exposes these typed tasks:

| taskKind | Access | Runtime behavior |
| --- | --- | --- |
| `hyperframes_cli_probe` | probe | Reads Node/npm/HyperFrames versions |
| `hyperframes_lint` | read-only | Runs `hyperframes lint . --json` |
| `hyperframes_check` | read-only | Runs `hyperframes check . --json` with bounded check flags |
| `hyperframes_compositions` | read-only | Lists compositions as JSON |
| `hyperframes_render` | mutation | Renders an MP4 to a workspace-relative path after approval |

The same allowlist is implemented by the Linux Sandbox PRoot runner, the
Android MobileCode Helper service, and the local Python Helper daemon. The
runtime never accepts a model-provided shell string or arbitrary argument list.

Example typed payload:

```json
{
  "cliId": "hyperframes-cli",
  "taskKind": "hyperframes_render",
  "payload": {
    "output": "exports/demo.mp4",
    "composition": "Main",
    "approved": true
  },
  "reason": "Render the verified HTML composition"
}
```

`hyperframes_check` accepts only the bounded scalar flags `snapshots`, `strict`,
`noContrast`, `frameCheck`, and `samples` (1-100). Render accepts a relative
`.mp4` output and a simple composition identifier. `publish`, `add`,
`transcribe`, TTS, background removal, and long-running `preview` are not part
of this first slice.

## Alpine Profile

The `hyperframesCli` profile installs or verifies:

- Node.js and npm
- Chromium
- FFmpeg
- `hyperframes` from npm

The Android APK is the control plane. Alpine supplies the CLI and media
toolchain, but it does not make a model or browser engine run inside the APK
itself. HyperFrames render still depends on target-ABI package availability,
Node compatibility, a usable Chromium binary, and FFmpeg; the profile reports
dependency failure instead of claiming render support when any prerequisite is
missing.

On Android, the runner pins `HYPERFRAMES_BROWSER_PATH=/usr/bin/chromium` and
software screenshot capture. This uses the Chromium already installed in the
Alpine profile and avoids HyperFrames' managed-browser download/lock flow,
which is not a good fit for an Android PRoot filesystem.

## Preview Boundary

HyperFrames `preview` is a long-running development server. MobileCode keeps
the existing WebView/preview surface for interactive preview and only routes
bounded CLI tasks through Agent tool calling. This avoids leaving an unmanaged
server process behind in the Helper or Alpine runtime.

## Verification Status

Evidence captured on 2026-07-13:

- Host HyperFrames `0.7.55` passed `check` on the bundled editable poster
  fixture with lint, runtime, and layout gates all green.
- The same fixture rendered to a 10-second MP4 on the host; `ffprobe` reported
  `1920x1080` and `10.000000` seconds.
- Android emulator `sdk_gphone64_arm64` / API 36 successfully initialized the
  Alpine 3.24.1 aarch64 rootfs. On a 4 GB guest, the real `hyperframesCli`
  install completed inside PRoot: Node `24.17.0`, npm `11.12.1`, Chromium
  `150.0.7871.114`, FFmpeg `8.1.2`, and HyperFrames `0.7.55`. Alpine emitted a
  sandbox database permission warning during apk mutation, but the runner's
  postcondition check verified every runtime binary and the HyperFrames CLI.
- The installed runtime then passed the same editable HTML fixture through
  `hyperframes lint`, `hyperframes check`, and `hyperframes render` on-device.
  The Android MP4 is preserved under
  `mobile_agent/qa-output/android-hyperframes-closeout-20260713/android-4gb-proof/`;
  `ffprobe` reports H.264, `640x360`, `30fps`, `1.000000` second, and 56,598
  bytes. HyperFrames used system Chromium's screenshot capture fallback because
  the Alpine package is not `chrome-headless-shell`; this is valid local render
  output, with a documented performance tradeoff.
- A clean final Android run after pinning the browser path passed setup, profile
  verification, probe, lint, check, and render in 60.572 seconds. Its focused
  log is preserved under
  `mobile_agent/qa-output/android-hyperframes-closeout-20260713/android-4gb-proof-final/proof.log`;
  the final render reported `Browser: env` and produced the same 56,598-byte
  `640x360`, 30fps, 1-second MP4.
- Android native WebView PNG/PDF capture passed `HtmlRenderRunnerInstrumentedTest`
  with 2/2 tests. The external HTML preview surface was opened with the same
  poster, showed rendered/source modes, and the emulator click proof opened the
  Android share sheet for both PNG and PDF. Android now registers the same
  `mobilecode/html_renderer` channel used by iOS; the HTML file remains
  editable through the code view.
- The current APK was clicked through the editable path: `编辑源码` opened a
  writable `EditText`, a marker was inserted, `Save` wrote it back to the
  app-owned HTML file, and returning to preview reloaded the edited document.
  The subsequent PNG export opened the Android share sheet and produced a
  verified `1920x1080` PNG. Evidence is preserved under
  `mobile_agent/qa-output/android-hyperframes-closeout-20260713/` as
  `ui-editable-preview-after-save.xml`, `ui-editable-export.xml`, and
  `android-ui-editable-export.png`.
- The final APK was clicked through again after the runtime fix: the editor
  reported `Modified`, the saved HTML retained the `EDITED` marker, and the
  PNG share sheet showed `Sharing image` with an image preview. The current
  artifact is `android-ui-final-editable-export.png` (`1920x1080`, 687,455
  bytes), with UI evidence in `ui-final-edit-typed.xml`,
  `ui-final-after-save.xml`, and `ui-final-export-share.xml`.

The device result is now complete for the current slice: editable HTML is the
source, native preview provides direct PNG/PDF export, and the Alpine
HyperFrames CLI provides the approved MP4 render path. A generic emulator QA
run may inject a local HTTP APK mirror through the setup manifest to avoid CDN
transfer stalls; normal generic-emulator setup uses HTTP because this PRoot
environment cannot complete the mirror's TLS exchange, while physical Android
devices keep HTTPS.
