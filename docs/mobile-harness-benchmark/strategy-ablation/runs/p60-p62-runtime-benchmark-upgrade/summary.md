# P6.0-P6.2 Runtime Benchmark Upgrade

- run_id: `p60-p62-runtime-benchmark-upgrade`
- run_kind: `strategy_pilot_not_counted`
- counts_as_experiment: `false`
- counts_as_strategy_ablation_result: `false`
- status: `passed`
- score_boundary: `pilot_p60_p62_contract_score_not_counted`
- total_score_not_counted: `100.0`

## Evidence

- Contract doc: `docs/mobile-harness-benchmark/strategy-ablation/p60-p62-runtime-benchmark-contract.md`
- Contract JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_contract.json`
- Verifier JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_verifier.json`
- Scoreboard: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_scoreboard.csv`
- Run JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/run.json`

## Scope

- P6.0 defines task taxonomy, runtime assertions, and score dimensions.
- P6.1 defines mailbox, EvidenceLedger, RuntimeEventBus, MemoryCommitProposal, and role contracts.
- P6.2 defines runtime verifier JSON and non-counted run contracts, with Android/WebView evidence hooks.
- This run is a contract/scaffold proof only, not a formal benchmark.

## Next P6.3 Android Real Device Lane

Install the latest APK on a real Android device or dedicated emulator, verify Accessibility state, run Mobile Phone Use dry/action probes, capture screenshot/UI XML/logcat/focus state, and add WebView state assertions for generated artifacts. Keep the run non-counted until repeated samples and promotion gates pass.
