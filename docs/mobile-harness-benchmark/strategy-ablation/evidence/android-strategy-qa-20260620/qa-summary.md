# Android Strategy QA Summary - 2026-06-20

Scope: release APK emulator QA for the Mobile Harness Strategy card. This is
non-counted dry-trace evidence only, not a benchmark result.

## Build

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- SHA256: `7dcdfcd532981c05892017d40af3541c424b31e6f7f0682110540ff4ad416fb8`
- Package: `com.mobilecode.app`
- Emulator: `Pixel_7_API_36` via `emulator-5554`

## Install / Launch

- `install.txt`: `Success`
- `launch.txt`: `Status: ok`, `Activity: com.mobilecode.app/.MainActivity`
- `window-focus-after-strategy.txt`: focus remained on `com.mobilecode.app/.MainActivity`
- `logcat-app-after-details.txt`: no `FATAL EXCEPTION`, `E/flutter`, `ANR`, or `MissingPluginException`

## Strategy UI Dry Trace

| Mode | Current strategy | Status | Trace | Evidence | Blocked reason | Handoffs | Memory packet |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Auto | `plan_execute_verify_single_agent` | `strategy_pilot_not_counted` | 14 | 3 | `none` | 0 | `strace_ui-auto` |
| ReAct | `react_single_agent` | `strategy_pilot_not_counted` | 10 | 3 | `none` | 0 | `strace_ui-react` |
| Plan-Execute-Verify | `plan_execute_verify_single_agent` | `strategy_pilot_not_counted` | 14 | 3 | `none` | 0 | `strace_ui-planExecuteVerify` |
| Supervisor/Handoff | `supervisor_handoff_multi_agent` | `strategy_pilot_not_counted` | 15 | 6 | `none` | 6 | `strace_ui-supervisorHandoff` |
| Experimental Swarm | `swarm_router_multi_agent` | `strategy_pilot_not_counted` | 1 | 0 | `experimental_strategy_disabled` | 0 | `strace_ui-experimentalSwarm` |

Every mode showed `counts_as_experiment=false`.

## Key Evidence Files

- `screenshot-launch.png`
- `screenshot-tools-top.png`
- `screenshot-strategy-auto-details.png`
- `screenshot-strategy-react-details.png`
- `screenshot-strategy-pev-details.png`
- `screenshot-strategy-supervisor-details.png`
- `screenshot-strategy-swarm-details.png`
- `window-strategy-auto-details.xml`
- `window-strategy-react-details.xml`
- `window-strategy-pev-details.xml`
- `window-strategy-supervisor-details.xml`
- `window-strategy-swarm-details.xml`
- `logcat-app-after-details.txt`
