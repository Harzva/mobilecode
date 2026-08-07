# Qwen-UI-Agent benchmark analysis for MobileCode

Analysis date: 2026-07-30

## Source artifact

- Official project: <https://tongyi-mai.github.io/Qwen-UI-Agent/>
- Official repository: <https://github.com/Tongyi-MAI/Qwen-UI-Agent>
- Local report: `docs/research/qwen-ui-agent-technical-report.pdf`
- Report SHA-256: `c57f7e2605b370237ff0b4f1e3ef85609e5785c87391e469d0b82f33dffa9567`

The benchmark names and Qwen-UI-Agent scores below come from the official
technical report dated 2026-07-29. They are upstream results, not MobileCode
results.

## Benchmarks used in the report

| Group | Benchmarks | Reported Qwen-UI-Agent result |
| --- | --- | --- |
| Mobile use | MobileWorld, MobileWorld-Real, AndroidDaily | 82.1%, 92.2%, 97.5% |
| Computer use | OSWorld-Verified, OSWorld-v2 | 79.5%; 40.0% partial progress and 13.9% binary completion |
| Browser and DeepSearch | WebArena, BrowseComp, BrowseComp-ZH | 73.6%, 64.1%, 75.0% |
| GUI grounding | ScreenSpot-Pro, ScreenSpot-V2, MMBench-GUI L2, OSWorld-G-Refined, UI-Vision | 81.5% on ScreenSpot-Pro with zoom-in; the report also gives results for the other four grounding sets |
| General capability | MMMU-Pro, RealWorldQA, CharXiv-RQ, MathVision, AI2D_TEST, MMLU-Pro, IFEval | Capability-retention evaluation after GUI post-training |
| Agentic capability | Tau2-Bench, Terminal-Bench 2.0, Claw-Eval, BFCL-v4, SkillsBench, QwenClawBench | Tool use, terminal work, multi-turn interaction, skills, and autonomous task execution |

AndroidWorld and WebVoyager are discussed in related work or infrastructure
context, but they are not part of the report's main evaluation tables.

## Benchmarks MobileCode can use

### P0: directly relevant

1. **MobileWorld** for long-horizon Android Phone Use. Its public environment
   covers cross-app GUI tasks, user interaction, and MCP tools. Start with a
   small adapter subset before attempting the report's 117-task GUI-only set.
2. **AndroidWorld** for reproducible emulator regression. It is a practical
   first public comparison because tasks have programmatic setup and evaluators.
3. **ScreenSpot-V2 / ScreenSpot-Pro** for static grounding. Use them to measure
   screenshot-to-element and screenshot-to-coordinate accuracy independently
   of end-to-end task planning.
4. **BFCL-v4** for typed CLI Hub and tool-selection correctness. Map MobileCode
   tool schemas into the official evaluator without changing the benchmark
   ground truth.
5. **Terminal-Bench 2.0** for the Alpine/CLI execution route. Run it in a
   controlled host or CI sandbox; do not present a hand-selected Android-safe
   subset as a full Terminal-Bench score.
6. **SkillsBench** for `SKILL.md` selection, loading, and effective skill use.

### P1: useful after P0 adapters

- **WebArena** for browser, HTML preview, and stateful web workflows.
- **OSWorld-Verified / OSWorld-v2** for Mac/CI cross-platform GUI and CLI
  coordination. These evaluate the desktop helper path rather than the APK
  itself.
- **AndroidDaily** for physical-device behavior on changing third-party apps.
  It is operationally expensive because accounts, permissions, pop-ups, app
  versions, and network state must be controlled and audited.

### Not currently reproducible as a public comparison

The official Qwen-UI-Agent repository currently publishes the site and report,
but not the 409-task MobileWorld-Real task set, its account setup, or its
AutoJudge implementation. MobileCode can adopt its evaluation ideas, but must
not claim a MobileWorld-Real score without an official release or an agreed
evaluation route.

## MobileCode's own benchmark stack

### 1. MobileHarnessBench

This is the primary formal benchmark. It evaluates a phone-native AI coding
harness rather than general phone tapping.

Its six task categories are:

- `file_intake`
- `code_edit`
- `preview_verification`
- `github_delivery`
- `harness_evidence`
- `runtime_orchestration`

Its primary metrics are task success, verified success, trace completeness,
recovery rate, artifact availability, human intervention count, and steps to
completion. Its evidence tiers cover T0 offline fixtures, Android emulator and
real device, iOS simulator and real device, and an authorized GitHub sandbox.

Current evidence boundary:

- 25 v0 seed tasks;
- 200 v1 and 1,000 v2 candidate tasks;
- 5 representative T0 dry runs: 4 passed and 1 typed GitHub block;
- 60 `smoke-v2` T0 runs: 50 fixture passes and 10 typed GitHub blocks;
- no counted Android/iOS mobile result;
- no counted baseline comparison result.

### 2. Mobile Harness Reasoning Strategy Ablation

This is a MobileHarnessBench sub-track for comparing six execution strategies:
ReAct, Plan-Execute-Verify, ReAct plus final verifier, Supervisor/Handoff,
SwarmRouter, and HierarchicalSwarm. It measures time, tokens/cost, verified
success, handoff quality, memory reuse, recovery, artifacts, and human
intervention.

The current results are scaffolds or non-counted pilots. They do not support a
strategy ranking yet.

### 3. Phone Use contract and runtime QA

P5.7 checks the Accessibility service, action schema, Flutter bridge, and
redaction boundary. P6.3 has one Android emulator runtime lane with install,
launch, Accessibility, dry/action probes, Back/Home, screenshots, UI XML, and
logcat evidence.

This is useful QA evidence, but it is not yet a general Phone Use benchmark:
the current P6.3 run is an emulator run, uses one tool-contract probe, and is
explicitly marked `counts_as_experiment=false`.

### 4. MobileCore / TuiMa local-LLM benchmark

MobileCore owns a separate runtime benchmark. The public README currently
records an Android AVD smoke run for Qwen2.5-0.5B Q4_K_M and explicitly labels
it as non-production evidence. The newer `tuima-llm-benchmark-v2` work freezes
the model, prompt, runtime revision, profile, and scoring algorithm, then
measures model load, prefill, first-token latency, decode throughput, memory,
battery, thermal state, sustained performance, and stability.

This should remain a separate benchmark family: MobileHarnessBench evaluates
agent workflow completion, while TuiMa evaluates local inference performance.
MobileCode may consume TuiMa results for local/cloud routing.

## Evaluation changes worth adopting

MobileHarnessBench should add the following fields without replacing its
deterministic verifiers:

- binary completion and partial progress;
- `agent_failure`, `env_error`, `user_takeover`, and `safety_block` as separate
  terminal outcomes;
- successful-trajectory length, model calls, and wall time;
- GUI, CLI, API, and ask-user action counts;
- stale-element-reference misclick rate;
- approval correctness and approval replay rejection;
- secret-leakage rate across screenshots, recordings, logs, and reports;
- recovery rate for pop-ups, background interruption, network change, and
  unexpected page state.

The Qwen report's trajectory judge uses multiple VLM votes for real apps where
programmatic state is unavailable. MobileCode should keep deterministic
verifiers for files, GitHub, HTML, CLI, and app-owned state, and use a
human-audited multi-judge only for residual third-party-app cases.

Qwen-UI-Agent also shows that GUI and CLI actions are complementary. MobileCode
can batch deterministic, typed CLI/file operations after policy validation, but
should not batch unobserved GUI mutations, ordering, booking, payment, message
sending, or other approval-sensitive actions.

## Paper assessment

MobileCode has a defensible paper direction as a systems-and-benchmark
contribution: a phone-native coding harness combining CLI, GitHub, HTML/WebView,
runtime routing, and evidence-gated execution. It should not compete with
Qwen-UI-Agent as a new foundation GUI model.

The current paper draft is reviewable but not empirically submission-ready.
Before submission it needs:

1. a frozen counted task subset with fully implemented verifiers;
2. counted Android real-device, iOS simulator/real-device, and GitHub sandbox
   runs;
3. locked baseline runs for chat-only mobile coding, desktop remote IDE, and
   MobileCode harness flows;
4. repeated runs and confidence intervals for stochastic agents;
5. ablations for semantic references, ActionEvidence, approvals, runtime
   routing, and recovery;
6. a safety track covering stale references, approval replay, secrets,
   publishing, ordering, and payment boundaries;
7. adapters to at least one public phone benchmark and one public CLI/tool-use
   benchmark.

With those experiments, the strongest claim is not "best phone-use model", but
"a verifiable phone-native control plane for AI coding and cross-surface
delivery."
