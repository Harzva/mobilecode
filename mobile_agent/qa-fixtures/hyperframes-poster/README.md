# HyperFrames poster fixture

This offline fixture is used by MobileCode's Android Alpine proof. It keeps
the editable HTML as the source artifact and exposes a small deterministic
timeline adapter through `window.__timelines['main']`.

From this directory, with `hyperframes` installed:

```sh
hyperframes check . --json
hyperframes render . --low-memory-mode --workers 1 --quality draft -o output.mp4
```

The Android proof copies the same HTML into `/root/hyperframes-poster` inside
the PRoot Alpine runtime, installs the `hyperframesCli` profile, runs `check`,
and then renders an MP4 with explicit approval.
