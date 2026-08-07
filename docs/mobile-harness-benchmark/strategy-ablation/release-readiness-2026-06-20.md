# Mobile Harness Strategy Release Readiness - 2026-06-20

This note records the current MobileCode app-side strategy framework status. It
is release-readiness evidence for the implementation layer, not a counted
benchmark result.

## Supported Strategy Modes

| Strategy | App runner | Default status | Counted result allowed |
| --- | --- | --- | --- |
| Auto / unknown ID | Falls back to PEV | Safe default | No |
| `react_single_agent` | `ReactStrategyRunner` | Enabled | No |
| `plan_execute_verify_single_agent` | `PlanExecuteVerifyStrategyRunner` | Enabled | No |
| `react_with_final_verifier` | `ReactWithFinalVerifierStrategyRunner` | Enabled | No |
| `supervisor_handoff_multi_agent` | `SupervisorHandoffStrategyRunner` | Enabled | No |
| `swarm_router_multi_agent` | `SwarmRouterStrategyRunner` | Experimental gate | No |
| `hierarchical_swarm_multi_agent` | `HierarchicalSwarmStrategyRunner` | Experimental gate | No |

## Implemented

- `StrategyDispatcher.defaultSafe` routes every registered strategy ID and
  blocks disabled or experimental strategies through a traceable blocked output.
- ReAct, PEV, ReAct+FinalVerifier, Supervisor/Handoff, SwarmRouter, and
  HierarchicalSwarm runners emit `StrategyTrace`, `StepVerification`, and
  `ActionEvidence`.
- Supervisor/Handoff creates filtered packets for CodeAgent, RuntimeAgent,
  PreviewAgent, VerifierAgent, MemoryAgent, and ReporterAgent.
- `HarnessMemoryPacketService` creates TTL-bound, compacted, redacted packets
  from `MemoryService` and returns proposal-only memory commits.
- P2 retry/final status aggregation treats the latest verification per step as
  authoritative.

## Non-Counted Boundary

Current outputs are fake/dry-run/pilot only. They must stay non-counted until a
real run has:

- model logs
- token records
- verifier outputs
- tool evidence
- device or emulator evidence
- screenshot or preview evidence

If any of the above is missing, `counts_as_experiment=false` and
`counts_as_strategy_ablation_result=false` remain mandatory.

## Android APK / Emulator QA

Release APK QA was run on 2026-06-20 with `Pixel_7_API_36` through
`emulator-5554`.

- APK: `mobile_agent/build/app/outputs/flutter-apk/app-release.apk`
- SHA256:
  `7dcdfcd532981c05892017d40af3541c424b31e6f7f0682110540ff4ad416fb8`
- Package/activity: `com.mobilecode.app/.MainActivity`
- Public evidence directory:
  `docs/mobile-harness-benchmark/strategy-ablation/evidence/android-strategy-qa-20260620/`
- Full local evidence directory:
  `mobile_agent/qa-output/android-strategy-qa-20260620-062617/`
- Install evidence: `install.txt` records `Success`.
- Launch evidence: `launch.txt` records `Status: ok` and
  `Activity: com.mobilecode.app/.MainActivity`.
- Focus evidence: `window-focus-after-strategy.txt` keeps focus on
  `com.mobilecode.app/com.mobilecode.app.MainActivity`.
- App log evidence: `logcat-app-after-details.txt` contains no
  `FATAL EXCEPTION`, `E/flutter`, `ANR`, or `MissingPluginException`.

The Tools page displayed the Mobile Harness Strategy card with Auto, ReAct,
Plan-Execute-Verify, Supervisor/Handoff, and Experimental Swarm. Each mode ran
a non-counted dry trace and displayed current strategy, run status, trace
count, evidence count, blocked reason, retry/replan state, handoff summary, and
memory packet summary.

| UI mode | Current strategy | Run status | Trace events | Evidence records | Blocked reason | Handoffs | Evidence |
| --- | --- | --- | ---: | ---: | --- | ---: | --- |
| Auto | `plan_execute_verify_single_agent` | `strategy_pilot_not_counted` | 14 | 3 | `none` | 0 | `evidence/android-strategy-qa-20260620/screenshot-strategy-auto-details.png`, `evidence/android-strategy-qa-20260620/window-strategy-auto-details.xml` |
| ReAct | `react_single_agent` | `strategy_pilot_not_counted` | 10 | 3 | `none` | 0 | `evidence/android-strategy-qa-20260620/screenshot-strategy-react-details.png`, `evidence/android-strategy-qa-20260620/window-strategy-react-details.xml` |
| Plan-Execute-Verify | `plan_execute_verify_single_agent` | `strategy_pilot_not_counted` | 14 | 3 | `none` | 0 | `evidence/android-strategy-qa-20260620/screenshot-strategy-pev-details.png`, `evidence/android-strategy-qa-20260620/window-strategy-pev-details.xml` |
| Supervisor/Handoff | `supervisor_handoff_multi_agent` | `strategy_pilot_not_counted` | 15 | 6 | `none` | 6 | `evidence/android-strategy-qa-20260620/screenshot-strategy-supervisor-details.png`, `evidence/android-strategy-qa-20260620/window-strategy-supervisor-details.xml` |
| Experimental Swarm | `swarm_router_multi_agent` | `strategy_pilot_not_counted` | 1 | 0 | `experimental_strategy_disabled` | 0 | `evidence/android-strategy-qa-20260620/screenshot-strategy-swarm-details.png`, `evidence/android-strategy-qa-20260620/window-strategy-swarm-details.xml` |

All five UI runs show `counts_as_experiment=false`. Experimental Swarm remains
visible for QA but blocked by the feature gate, as intended.

## Reproduction Commands

```bash
cd mobile_agent
flutter test test/services/ test/widgets/strategy_mode_card_test.dart
```

```bash
python3 -m py_compile \
  scripts/run_mobile_harness_strategy_ablation.py \
  scripts/validate_mobile_harness_strategy_ablation.py \
  scripts/generate_mobile_harness_strategy_callback_pilot.py
```

```bash
python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold/run.json

python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/p4c-callback-pilot/run.json

git diff --check
```

## Release Blockers

- No remaining blocker for the non-counted strategy selector dry-run UI.
- No remaining blocker for Android release APK install/launch smoke QA.
- Real provider/tool/device callbacks remain gated and must not be promoted to
  counted benchmark output without the evidence set above.
- Experimental Swarm remains feature-gated and blocked for counted output.

## Next Pilot Plan

1. Keep all fake/dry-run/pilot outputs labeled non-counted.
2. Preserve the Android QA evidence set when preparing release notes.
3. Only after UI and emulator evidence pass, design the first real callback
   pilot with explicit provider/tool/device authorization.
4. Before enabling counted output, require model logs, token records, verifier
   outputs, tool evidence, device/emulator evidence, and screenshots or preview
   evidence.
