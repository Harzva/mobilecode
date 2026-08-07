# MobileCode

<p align="center">
  <img src="mobile_agent/assets/icons/mobilecode-logo.svg" alt="MobileCode logo" width="96">
  <br />
  <strong>Phone-native AI Coding Harness</strong>
  <br />
  The agent harness runs on the phone. Models can be remote; the coding loop, files, previews, runtime routing, and shipping controls stay in MobileCode.
  <br />
  不是远程 IDE 的手机壳，而是真正把 agent loop、工具状态、文件、预览和发布控制面放到手机本机的 MobileCode。
</p>

<p align="center">
  <a href="https://github.com/Harzva/mobilecode/actions/workflows/mobile-runtime-ci.yml"><img alt="Mobile Runtime CI" src="https://github.com/Harzva/mobilecode/actions/workflows/mobile-runtime-ci.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/Harzva/mobilecode/actions/workflows/mobile-app-release.yml"><img alt="Mobile App Release" src="https://github.com/Harzva/mobilecode/actions/workflows/mobile-app-release.yml/badge.svg"></a>
  <a href="https://github.com/Harzva/mobilecode/actions/workflows/android-apk.yml"><img alt="Android APK" src="https://github.com/Harzva/mobilecode/actions/workflows/android-apk.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/Harzva/mobilecode/actions/workflows/android-app-test.yml"><img alt="Android Smoke" src="https://github.com/Harzva/mobilecode/actions/workflows/android-app-test.yml/badge.svg?branch=main"></a>
  <img alt="Version" src="https://img.shields.io/badge/version-v0.1.78-2555FF">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Flutter-0B9B7E">
</p>

<p align="center">
  <a href="docs/assets/mobilecode-short-teaser.mp4"><strong>Watch 15s Short</strong></a>
  ·
  <a href="docs/assets/mobilecode-promo-vertical.mp4"><strong>Watch 9:16 Promo Video</strong></a>
  ·
  <a href="docs/assets/mobilecode-readme-cover.mp4">README Motion Cover</a>
  ·
  <a href="https://harzva.github.io/mobilecode/mobilecode-principle-video.html">HTML Principle Video</a>
  ·
  <a href="https://github.com/Harzva/mobilecode/releases/tag/v0.1.78">Download v0.1.78 app</a>
  ·
  <a href="https://harzva.github.io/mobilecode/">GitHub Pages Demo</a>
</p>

<p align="center">
  <a href="https://harzva.github.io/mobilecode/">Demo Lab</a>
  ·
  <a href="https://harzva.github.io/mobilecode/demo/2048/">2048 Demo</a>
  ·
  <a href="https://harzva.github.io/mobilecode/github-test/">GitHub Test</a>
  ·
  <a href="https://github.com/Harzva/mobilecode/actions/runs/27287231941">Dual app build</a>
  ·
  <a href="https://github.com/Harzva/mobilecode/releases">Download app builds</a>
  ·
  <a href="docs/mobilecode-release-qa.md">Release QA</a>
</p>

<p align="center">
  <a href="https://harzva.github.io/mobilecode/">
    <img src="docs/assets/mobilecode-readme-showcase.svg" alt="MobileCode phone-native AI coding harness workflow" width="960">
  </a>
</p>

<p align="center">
  <a href="https://harzva.github.io/mobilecode/mobilecode-principle-video.html">
    <img src="docs/assets/mobilecode-short-poster.png" alt="MobileCode 15-second Remotion teaser cover" width="960">
  </a>
  <br>
  <sub>15-second Remotion teaser with voiceover. Full explainer covers demand, pain, RuntimeProvider, and GitHub-first shipping.</sub>
</p>

## Product Preview

MobileCode is packaged as a phone-native coding harness: a small mobile companion for writing, previewing, running agent tasks, and shipping artifacts from the same handheld workspace.

<p align="center">
  <img src="app/public/showcase/mobilecode-product-preview.png" alt="MobileCode product preview and mobile coding identity board" width="960">
</p>

<p align="center">
  <video src="app/public/showcase/mobilecode-product-walkthrough.mp4" width="360" controls muted playsinline>
    <a href="app/public/showcase/mobilecode-product-walkthrough.mp4">Watch MobileCode product walkthrough MP4</a>
  </video>
  <br>
  <sub>If your Markdown viewer does not embed video, open <a href="app/public/showcase/mobilecode-product-walkthrough.mp4">mobilecode-product-walkthrough.mp4</a>.</sub>
</p>

| Runs on the phone | Remote by choice | GitHub-first shipping |
| --- | --- | --- |
| Agent trace, tool selection, runtime routing, local files, WebView preview, result cards | Model provider, optional Cloud Runtime, external Termux/Helper backends | Repo discovery, Contents API commits, Pages publish, Actions builds, release artifacts |

## Why MobileCode

MobileCode 的第一性原理很简单：手机端不适合塞一个完整桌面编译环境，但非常适合成为 AI coding 的本机 harness。

它不是 Codex Remote、Claude Remote 或云端 IDE 的移动端外壳。模型可以来自云端 provider，但对话、工具编排、运行时选择、文件落盘、WebView 预览、GitHub 发布和恢复提示都在手机 App 内闭环。

它把最重的部分交给外部平台，把最贴近用户的部分留在手机上：

| Layer | MobileCode does | External layer does |
| --- | --- | --- |
| Phone-native harness | Chat, tool trace, role cards, file cards, preview, runtime diagnostics, settings | None |
| Local runtime | Helper / Termux / WebViewOnly through `RuntimeProvider` | Shell, logs, small local tasks |
| GitHub-first workspace | Repo Hub, watchlist, remote-linked folders, Pages publish cards | Repos, Contents API commits, Actions builds, artifacts |
| Web artifacts | Generate HTML, run publish readiness checks, open browser/WebView | GitHub Pages hosting |
| Heavy builds | Show workflow status, jobs, artifacts | GitHub Actions APK/Web/release builds |

## Research Signal: Mobile Harness Era

PhoneWorld 的最新研究把 phone-use agent 的瓶颈从“模型是否会点手机”推进到“谁能规模化提供可控环境、任务、验证器、轨迹和训练/评测 harness”。这不是对 MobileCode 的直接背书，但它清晰说明了一个方向：手机 Agent 的下一阶段核心资产是可执行、可复现、可验证的 harness。

MobileCode 选择从 AI coding 切入同一条趋势：模型可以远程，重构建可以交给 GitHub Actions，但会话、工具轨迹、文件、HTML/Markdown 预览、运行时路由、GitHub 发布、构建 artifact 和结果证据需要在手机端形成闭环。

- Paper: [PhoneWorld: Scaling Phone-Use Agent Environments](https://arxiv.org/abs/2605.29486)
- Local PDF: [docs/research/phoneworld-scaling-phone-use-agent-environments-2605.29486.pdf](docs/research/phoneworld-scaling-phone-use-agent-environments-2605.29486.pdf)
- MobileCode analysis: [PhoneWorld 与 Mobile Harness 时代](docs/mobile-harness/phoneworld-mobile-harness-era.md)
- MobileCode product roadmp: [MobileCode 长期路线图](docs/mobilecode-long-term-roadmap.md)
- Long-term roadmp: [Mobile Harness 长期路线图](docs/mobile-harness-roadmp/roadmp-mobile-harness.md)
- ICLR draft: [PDF](paper/iclr-mobile-harness/main.pdf) · [TeX](paper/iclr-mobile-harness/main.tex)
- Anonymous supplement boundary: [include/exclude and redaction gate](paper/iclr-mobile-harness/SUPPLEMENT_BOUNDARY.md)
- Current anonymous supplement: `paper/iclr-mobile-harness/build/mobile-harness-anonymous-supplement.zip` (staged file count and byte size are emitted by the supplement script)
- Benchmark seed: [MobileHarnessBench](docs/mobile-harness-benchmark/README.md)
- Controlled Phone Use v1: [30-task protocol](docs/mobile-harness-benchmark/phone-use/README.md) · [readiness gate](docs/mobile-harness-benchmark/reports/phone-use-v1-readiness.md)
- Latest Android emulator QA: [release build and Phone Use evidence](docs/mobile-harness-benchmark/reports/2026-08-01-android-emulator-qa.md)
- Qwen UI-Agent study: [benchmark analysis](docs/research/qwen-ui-agent-benchmark-analysis.md) · [local technical report](docs/research/qwen-ui-agent-technical-report.pdf)
- v1 task bank: [200 MobileHarnessBench candidate tasks](docs/mobile-harness-benchmark/tasks/v1-task-bank.json)
- v2 task bank: [1000 MobileHarnessBench candidate tasks](docs/mobile-harness-benchmark/tasks/v2-task-bank.json)
- v2 quality audit: [machine audit report](docs/mobile-harness-benchmark/reports/v2-quality-audit.md)
- Verifier contracts: [machine-readable catalog](docs/mobile-harness-benchmark/verifiers/verifier-contracts.json) · [coverage readiness](docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md)
- Baseline protocol: [comparison readiness](docs/mobile-harness-benchmark/reports/baseline-protocol-readiness.md)
- Baseline run contract: [result schema readiness](docs/mobile-harness-benchmark/reports/baseline-run-contract.md)
- Baseline scaffold: [not-run scaffold manifest](docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-scaffold/README.md)
- Baseline T0 dry run: [not-counted dry-run manifest](docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-dry-run-t0/README.md)
- Baseline pilot pack: [prompt and evidence templates](docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-pilot-pack/README.md)
- Baseline pilot readiness: [non-counted readiness gate](docs/mobile-harness-benchmark/reports/baseline-pilot-readiness.md)
- Core claim readiness: [positioning claim boundary](docs/mobile-harness-benchmark/reports/core-claim-readiness.md)
- Evidence maturity: [claim maturity matrix](docs/mobile-harness-benchmark/reports/evidence-maturity-matrix.md)
- Evaluation protocol readiness: [E1-E5 machine-checkable protocol](docs/mobile-harness-benchmark/reports/evaluation-protocol-readiness.md)
- Method presentation readiness: [visuals, algorithms, modules and formulas gate](docs/mobile-harness-benchmark/reports/method-presentation-readiness.md)
- Bibliography readiness: [verified related-work metadata](docs/mobile-harness-benchmark/reports/bibliography-readiness.md)
- Threats to validity: [review risk matrix](docs/mobile-harness-benchmark/reports/threats-to-validity.md)
- Page-limit readiness: [compiled PDF page boundary](docs/mobile-harness-benchmark/reports/page-limit-readiness.md)
- Reproducibility checklist: [command-to-artifact matrix](docs/mobile-harness-benchmark/reports/reproducibility-checklist.md)
- Submission readiness: [draft upload gate](docs/mobile-harness-benchmark/reports/submission-readiness.md)
- Paper claim ledger: [claim-to-evidence map](docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md)
- Mobile-tier readiness: [Android/iOS readiness probe](docs/mobile-harness-benchmark/reports/mobile-tier-readiness.md)
- Mobile evidence pack: [T2/T3 capture templates](docs/mobile-harness-benchmark/reports/mobile-evidence-pack-readiness.md) · [execution playbook](docs/mobile-harness-benchmark/mobile-evidence/2026-06-06-mobile-evidence-pack/execution-playbook.md)
- Draft frozen subset: [planning manifest](docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json) · [readiness report](docs/mobile-harness-benchmark/reports/frozen-subset-readiness.md)
- Mobile test strategy: [Android/iOS benchmark tiers](docs/mobile-harness-benchmark/mobile-test-strategy.md)
- Simulator launcher reference: [simutil](https://github.com/dungngminh/simutil)
- MobileCode Skill Spec: [SKILL.md + WebView script + permission + verifier contract](docs/mobile-harness-benchmark/skill-spec.md)
- Harness Task Registry: [task metadata for Tools, sheets, routes, skills and benchmark evidence](docs/mobile-harness-benchmark/harness-task-registry.md)
- v0 dry run evidence: [2026-06-06 representative run](docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/summary.md)
- smoke-v2 T0 evidence: [2026-06-06 60-task smoke run](docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md)

## Inspired by On-device AI Gallery Patterns

Recent on-device AI applications are moving from plain chat demos toward task galleries, skill packages, tool bridges, model/runtime management and benchmark views. Google AI Edge Gallery is a useful public example of this product shape: it organizes on-device models around tasks, custom tasks, skills, MCP tooling and benchmark surfaces. MobileCode adopts the pattern but changes the object of evaluation. Instead of becoming a general model gallery, MobileCode turns phone-native AI coding into a harness: incoming files, artifact editing, HTML/Markdown preview, GitHub delivery, runtime routing, verifier contracts and evidence reports.

The practical design consequence is now explicit in the repo:

- Skills use `SKILL.md`, `scripts/index.html`, permission tokens and verifier contracts.
- Tools, sheets and pages are promoted into a Harness Task Registry instead of remaining one-off buttons.
- Benchmark Lab is becoming an in-app surface for MobileHarnessBench status, task tiers and evidence boundaries.
- Claims remain evidence-bound: T0 fixture runs, mobile tiers, GitHub sandbox delivery and baseline comparison are reported separately.

## Effect Showcase

These thumbnails are generated from the live GitHub Pages demos with `just-thumbnail`, so the README shows rendered pages rather than mock claims.

<table>
  <tr>
    <td width="33%">
      <a href="https://harzva.github.io/mobilecode/">
        <img src="docs/assets/thumb-demo-lab/responsive.png" alt="MobileCode Demo Lab responsive preview">
      </a>
      <br>
      <strong>Demo Lab</strong>
      <br>
      Product landing and demo index published on GitHub Pages.
    </td>
    <td width="33%">
      <a href="https://harzva.github.io/mobilecode/demo/2048/">
        <img src="docs/assets/thumb-2048/responsive.png" alt="MobileCode 2048 responsive preview">
      </a>
      <br>
      <strong>2048 Web</strong>
      <br>
      Touch-first generated HTML game for mobile WebView checks.
    </td>
    <td width="33%">
      <a href="https://harzva.github.io/mobilecode/github-test/">
        <img src="docs/assets/thumb-github-test/responsive.png" alt="MobileCode GitHub Test responsive preview">
      </a>
      <br>
      <strong>GitHub Test</strong>
      <br>
      Browser-side token and repo access verification page.
    </td>
  </tr>
</table>

| Scene | What to try | Link |
| --- | --- | --- |
| Demo Lab | A static landing page for published mobile demos | [Open demo lab](https://harzva.github.io/mobilecode/) |
| 2048 Web | Touch-first generated HTML game, useful for WebView and mobile layout checks | [Play 2048](https://harzva.github.io/mobilecode/demo/2048/) |
| GitHub Test | Verify token identity, repo access, and Pages readiness from a browser | [Open GitHub test](https://harzva.github.io/mobilecode/github-test/) |
| Repo Hub | Watch repos, map them to `mobilecode_projects/github/<owner>/<repo>/`, inspect Actions, edit files through GitHub API | `mobile_agent/lib/screens/github_repo_hub_screen.dart` |
| Published Work Card | After Pages publish, show Pages URL, repo URL, local file path, browser open, copy/share, and redeploy actions | `mobile_agent/lib/screens/home_screen.dart` |

## Product Loop

```mermaid
flowchart LR
  A["User prompt on phone"] --> B["AI generates HTML / code artifact"]
  B --> C["Local WebView preview"]
  C --> D["HTML publish readiness check"]
  D --> E["GitHub Pages publish"]
  E --> F["Shareable work card"]
  B --> G["GitHub Repo Hub"]
  G --> H["Contents API edit + commit"]
  G --> I["GitHub Actions workflow_dispatch"]
  I --> J["Jobs, logs, artifacts"]
```

## Current Capabilities

- Runtime abstraction: `RuntimeProvider`, `RuntimeManager`, Helper, External Termux, planned Embedded Lite, Cloud, and WebViewOnly fallback.
- MobileCode Helper prototype: health, execute, streaming logs, task stop, task state, preflight checks.
- Chat and agent process UI: model call progress, stop control, trace cards, generated artifact cards.
- HTML-first generation: built-in HTML/UI skill context, publish readiness checks, WebView preview, browser open, GitHub Pages publish.
- GitHub-first workspace: repo list, watchlist, language/Pages/local filters, local existence status, Remote-linked folder marker.
- [Safe container architecture](docs/mobilecode-container-architecture.md): multi-workspace, multi-runtime, multi-preview, and evidence-ledger model for phone-native AI coding.
- GitHub Actions surface: workflows, latest run status, jobs/steps, workflow dispatch, artifact zip download record.
- API-backed file flow: browse remote tree, read text files, edit, commit via GitHub Contents API, reload on SHA conflict.
- Extension management: Roles, Skill, MCP, Memory, Agent, Hook Registry surfaces for role-based workflows.
- Observability: RR AgentView, pending role approvals, Token Usage/cache-hit statistics, searchable/sortable LiteLLM-style pricing with manual snapshot checks, and Device Telemetry htop-style phone health.
- [Phone Use safety loop](docs/mobilecode-device-automation-architecture.md): cropped semantic snapshots and short-lived `@e` refs, trusted native transaction-risk classification, page-bound one-shot approval cards, unified ActionEvidence, and Keystore/Keychain `secret_id` credential slots.
- [MobileCore local inference bridge](docs/mobilecore-dual-app-qa.md): dynamic model/capability discovery, model ID load/unload/switch controls, local-only image/audio transport, adaptive memory/thermal routing, and redacted inference ActionEvidence. MobileCore remains the inference engine; MobileCode remains the approval, Phone Use, transaction-risk, and evidence control center.
- [Lark Native API plan](docs/lark-native-api-upgrade-plan.md): agent-facing, Node-free Lark OpenAPI tools for Docs, Drive, Sheets, Bitable, Wiki, and evidence publishing; official CLI/MCP remain Mac/CI development probes, not embedded app runtimes.

## MobileCore Link Status

MobileCode no longer hard-codes a local Qwen model. `MobileCoreClient` resolves the active model, runtime, revision, backend, quantization, capabilities, artifact state, resource preflight, Android background-restriction state, recommendations, and performance metrics from the co-installed MobileCore service. The in-app TuiMa sheet can load, unload, and switch installed models by public `model_id`; ordinary clients never receive or submit absolute model paths. Cross-model switching projects the memory available after reclaiming the matching active runtime, retains safety headroom, and revalidates the runtime immediately before loading so a stale snapshot cannot trigger a lifecycle request. A background-restricted MobileCore remains visible for recovery but is removed from eligible local routes before inference payloads are sent.

Image and audio buttons appear only when the active local runtime advertises the corresponding capability. Attachment bytes stay in memory, are sent only to `127.0.0.1`, are never persisted in chat turns or evidence, and never fall back to a cloud provider. Local inference evidence records safe model/runtime/latency metadata while omitting prompts, media, credentials, and payloads.

The latest controlled Android emulator run passed 30 real cross-app offline tasks (15 buffered and 15 SSE), model unload/reload, a Qwen2.5-to-Qwen3 switch, background continuity, low-memory notification, and MobileCore process restart recovery. The current fail-closed runner additionally observed airplane-mode enable/restore, completed 30/30 requests with zero failed host steps, and rejected a counted physical run on the emulator before installation. A separate Qwen3.5 GGUF/mmproj run completed a real local image request through `llama.cpp/libmtmd`; its incorrect breed classification remains recorded as a failed broad-quality probe. A later MobileCode-process two-digit image sanity set passed both distinct cases, proving the cross-app attachment path without upgrading the generic, unverified artifacts into a broad accuracy claim. Physical-device, thermal, verified Omni audio, and broader vision-quality acceptance remain open. See [the evidence-bound report](docs/mobilecore-dual-app-qa.md).

## Phone Use Safety Status

As of 2026-07-18, the Auto Agent can observe Android UI and request a semantic
action preview, but it cannot click or type directly. Android classifies the
target from the admitted accessibility node, and MobileCode shows a 20-second,
one-shot approval card. Checkout/payment/order-like targets receive a distinct
transaction confirmation. The ticket is consumed before execution and is bound
to the full SHA-256 page snapshot; changed pages fail closed.

| Acceptance area | Result | Evidence boundary |
| --- | --- | --- |
| Flutter regression suite | 534 tests passed | Includes tool adapter, ActionRunner, one-shot/expiry/replay, credential redaction, and UI provisioning tests. |
| Android native build | `devharnessDebug` and `pureDebug` Kotlin variants passed; final pure debug APK assembled | Release QA fixtures remain debug-only. |
| Fake ordering acceptance | 29 redacted steps and 11 assertions passed; trusted `externalTransaction` classification, mismatched-page rejection, zero commit attempts | Fake merchant/data only; no payment, address, account, or real order endpoint. Manifest SHA-256: `93ce81cc52ca4c618661bc5b9a6b07676f63b1c325744aaa2ff1e602ed9a85e4`. |
| Controlled credential path | Provision/store/delete, `secret_id` preview, approved resolution, and evidence serialization passed with fake account data | Credential value absent from evidence and rendered status; screenshots/video/logs blocked for sensitive flow. |
| iOS source build | Unsigned device profile build passed | Signed install is blocked until Xcode provisioning/account readiness is restored. |
| Physical devices | Not passed | Acceptance host had zero Android physical devices and zero available iOS physical devices. No real-device or real external-account claim is made. |

Recording and log collection stay in the host-side QA adapter. MobileCode does
not bundle a second recorder app or `agent-device` runtime into the APK.

## Long-term Termux-like Runtime Plan

MobileCode is the phone-native layer for agent control, artifact review, and release evidence.
The long-term runtime direction is a **Termux-like substrate** (git + node + python + shell) that is invoked by the app as a service, while the user stays in MobileCode's control surface.

It should **not** be an embedded Termux terminal UI, and it should not become a generic remote IDE shell. The phone is still the command center: chat, role controls, route selection, previews, and shipping actions remain first-class inside MobileCode.

- Layer 1 - **MobileCode App**: conversations, tool cards, prompt state, repo selection, publish checks, and evidence surfaces.
- Layer 2 - **Termux-like Runtime**: long-term execution substrate for commands and project-level tooling, with isolation, caching, and runtime profiles.
- Layer 3 - **Bridge Layer**: typed runtime API, auth/session binding, intent routing, quota + timeout policy, and cancellation semantics.
- Layer 4 - **Evidence Layer**: command traces, logs, verifier signals, publish artifacts, and reproducibility records.

```mermaid
flowchart TB
  A["MobileCode App\nAgent UI / control / evidence cards"] --> B["Bridge Layer\nIntents / auth / quotas / telemetry"]
  B --> C["Termux-like Runtime\nGit / Node / Python / Shell"]
  B --> D["Remote Service Backends\nGitHub Actions / providers"]
  C --> E["Runtime output + logs"]
  E --> F["Evidence Layer\nTrace card / verifier feed / artifacts"]
  F --> A
```

Current repo implementation has runtime abstractions and helper paths in place; the full Termux-like embedded substrate is a roadmap objective, not a completed production feature yet.

## Architecture

```mermaid
flowchart TB
  UI["Flutter App\nChat · Files · Preview · Settings"] --> RM["RuntimeManager"]
  RM --> H["MobileCode Helper\nAndroid foreground service / daemon"]
  RM --> T["External Termux\nfallback shell"]
  RM --> W["WebViewOnly\npreview-only fallback"]
  RM --> C["Cloud Runtime\nheavy tasks later"]
  UI --> GH["GitHub Deep Service"]
  GH --> Repo["Repos / Contents API"]
  GH --> Pages["GitHub Pages"]
  GH --> Actions["GitHub Actions"]
  Actions --> Artifacts["APK / Web / release artifacts"]
```

## Quick Start

### Try the published demos

Open:

- [Demo Lab](https://harzva.github.io/mobilecode/)
- [2048 Web Demo](https://harzva.github.io/mobilecode/demo/2048/)
- [GitHub Test](https://harzva.github.io/mobilecode/github-test/)

### Build the product site

```bash
cd app
npm install
npm run build
```

### Delegate bounded development tasks

Non-multimodal small tasks should default to `cxspark`: README/docs drafts, narrow code patches, checklists, prompt edits, and mechanical changes. The parent Codex session still owns planning, review, verification, commits, releases, visual/device QA, and any risky operation. See [cxspark Agent Workflow](docs/cxspark-agent-workflow.md).

### Build the Flutter app

Local Flutter SDK is required:

```bash
cd mobile_agent
flutter pub get
flutter create --platforms=android,ios .
flutter build apk --release
```

For release QA, prefer GitHub Actions so the build is reproducible:

- [Mobile Runtime CI](https://github.com/Harzva/mobilecode/actions/workflows/mobile-runtime-ci.yml)
- [Build Android APK](https://github.com/Harzva/mobilecode/actions/workflows/android-apk.yml)
- [Android App Smoke Test](https://github.com/Harzva/mobilecode/actions/workflows/android-app-test.yml)

### Run MobileHarnessBench dry runs

```bash
python scripts/generate_mobile_harness_task_bank.py
python scripts/run_mobile_harness_bench.py --task-set representative-v0 --run-id 2026-06-06-v0-dry-run
python scripts/run_mobile_harness_bench.py --task-set smoke-v2 --run-id 2026-06-06-smoke-v2-t0
python scripts/audit_mobile_harness_task_bank.py
python scripts/collect_mobile_harness_mobile_tier_evidence.py
python scripts/generate_mobile_harness_mobile_evidence_pack.py
python scripts/generate_mobile_harness_frozen_subset.py
python scripts/generate_mobile_harness_verifier_contract_readiness.py
python scripts/generate_mobile_harness_baseline_protocol.py
python scripts/generate_mobile_harness_baseline_run_contract.py
python scripts/generate_mobile_harness_baseline_scaffold.py
python scripts/generate_mobile_harness_baseline_dry_run.py
python scripts/generate_mobile_harness_baseline_pilot_pack.py
python scripts/generate_mobile_harness_baseline_pilot_readiness.py
python scripts/generate_mobile_harness_claim_ledger.py
python scripts/generate_mobile_harness_core_claim_readiness.py
python scripts/generate_mobile_harness_evidence_maturity_matrix.py
python scripts/generate_mobile_harness_evaluation_protocol_readiness.py
python scripts/generate_mobile_harness_method_presentation_readiness.py
python scripts/generate_mobile_harness_bibliography_readiness.py
python scripts/generate_mobile_harness_threats_to_validity.py
python scripts/generate_mobile_harness_page_limit_readiness.py
python scripts/generate_mobile_harness_reproducibility_checklist.py
python scripts/generate_mobile_harness_submission_readiness.py
python scripts/validate_mobile_harness_bench.py
python scripts/prepare_mobile_harness_supplement.py
```

The benchmark line is intentionally evidence-bound. The current data contains 25 v0 seed tasks, a 200-task v1 candidate bank and a 1000-task v2 candidate bank. v2 expands the taxonomy from five categories to six by adding runtime orchestration, mobile profiles, test oracles and Android/iOS test tiers.

| Evidence area | Current state | Boundary |
| --- | --- | --- |
| Task supply | v0 seed, v1 200-task bank, v2 1000-task bank, frozen 60-task paper subset planning manifest | Candidate supply is not counted as mobile experiment evidence. |
| T0 fixture runs | Representative five-task run plus `smoke-v2` 60-task run with 50 fixture passes and 10 typed GitHub-delivery blocks | T0 does not replace Android/iOS device evidence. |
| Mobile evidence pack | 48 Android T2 / iOS T3 templates, device metadata templates, run manifests and execution playbook | `counts_as_mobile_experiment=false` until real captures are attached. |
| Verifier contracts | 12 machine-readable verifier contracts covering 1225 current task definitions | Readiness coverage is not full mobile-device verifier implementation. |
| Baseline protocol | Three comparison flows, seven metrics, run schema, scaffold, dry run and pilot pack | No counted baseline result is claimed yet. |
| Paper gate | Claim ledger, evidence maturity matrix, E1-E5 protocol, threats, page limit, reproducibility and submission readiness | Submission remains not upload-ready until venue metadata, mobile evidence, counted baselines and final supplement are complete. |

The App-side Benchmark Lab mirrors this structure as a product surface: task registry, evidence tiers, verifier readiness, T0 runs, mobile evidence pack and open gates are visible in the phone UI without overstating readiness artifacts as completed experiments.

## Runtime Strategy

MobileCode does not try to become a full Termux clone. The long-term model is:

```text
Flutter App
  -> RuntimeProvider abstraction
  -> MobileCode Helper
  -> External Termux fallback
  -> Embedded Lite runtime later
  -> Cloud runtime for heavy builds
  -> GitHub Pages + GitHub Actions for shipping
```

That keeps the phone lightweight while still letting users produce shareable web pages, inspect repos, commit small changes, and build APKs through GitHub Actions.

## Repository Structure

```text
.
├─ app/                     React/Vite product site
├─ docs/                    GitHub Pages demos, QA docs, runtime docs
├─ mobile_agent/            Flutter app source
│  ├─ lib/screens/          Home, GitHub Repo Hub, Skill/MCP/Agent/Memory UI
│  ├─ lib/services/         Runtime, GitHub, Pages, Helper, skill services
│  └─ assets/               Role avatars and icons
├─ mobile-coding-*.md       Product and architecture analysis
└─ README.md                Project homepage
```

## Release Line

Current candidate: `v0.1.78` (`0.1.78+68`).

See:

- [MobileCore dual-app evidence](docs/mobilecore-dual-app-qa.md) - 30 real offline cross-app requests, buffered/SSE parity, unload/reload, background continuity, low-memory notification, and process restart recovery passed on Android emulator.
- [Release assets](https://github.com/Harzva/mobilecode/releases/tag/v0.1.78) - the final signed Android `pure` APK is 33,073,027 bytes with SHA-256 `5123f48f93161838b166259061857b058ab63429051544e4ac0234088a886073`; the downloaded asset reports `0.1.78+68`, matches the MobileCode release certificate, contains no recognizable credential or concrete private-host-path value, and clean-launches with MobileCore ready on the Android 16 ARM64 emulator.
- [iOS Simulator](https://github.com/Harzva/mobilecode/actions/runs/31135405199) and [unsigned archive](https://github.com/Harzva/mobilecode/actions/runs/31135408249) - `0.1.78+68` now passes generated-project verification, simulator build/install/launch survival and crash-log checks, plus unsigned device archive packaging. These private workflow artifacts are build evidence, not signed physical-iPhone acceptance.
- [Signed Android v0.1.77 workflow](https://github.com/Harzva/mobilecode/actions/runs/31128587598) - the downloaded official `0.1.77+67` APK has SHA-256 `f008ede0e0305c835c3bf45bcc56f22c4fc911d0ae10b513f298d1bdfb0a1c1d`, verifies with the MobileCode release certificate, contains zero recognizable key/JWT/Bearer or private-host-path patterns, and clean-launches on the Android 16 ARM64 emulator.
- v0.1.77 makes the public release workflows fail closed if they reference or compile raw provider keys, relay bearer tokens, or an OAuth client secret. Public relay URLs, OAuth client IDs, and redirect URIs remain allowed configuration; users may still save their own provider key through the app's secure-storage flow.
- MobileCore `0.1.4-rc6` closes the emulator foreground-service regression. A 40-poll Android 16 lane kept MobileCode resumed while MobileCore retained its real local model and foreground service with zero failed health polls, freezes, FGS timeouts, ANRs, OOMs, or SIGABRTs. Android `background_restricted` is now a typed fail-closed routing state, not a hidden timeout.
- The former v0.1.76 official APK was withdrawn after post-build review found that the old public workflow supplied runtime service credentials as Dart compile definitions. The explicitly named debug-signed QA APK remains emulator evidence only; affected provider credentials should be rotated outside the repository.
- v0.1.76 requires the `mobilecore.local` v2 compatibility handshake before local model control or inference. Missing, malformed, or unsupported protocols fail closed with typed evidence; MobileCore still cannot perform Phone Use actions.
- Local timeouts and explicit Agent pauses now request native inference cancellation, while measured slow runtimes receive a bounded next-response budget; overlapping MobileCore work fails as `runtime_busy` instead of racing the shared llama context.
- [Signed Android v0.1.75 workflow](https://github.com/Harzva/mobilecode/actions/runs/31127234312) - the previous downloaded `0.1.75+65` APK has SHA-256 `66e7a26bb7efa4b3c6f959b3e8063fb05a25f91e5b13463211c80c60da5272e2`, verifies with the MobileCode release certificate, and clean-launches on the Android 16 ARM64 emulator without crash, ANR, or OOM.
- v0.1.75 added a per-task cloud inference approval card, redacted approval evidence, and fail-closed decline routing to MobileCore while keeping Phone Use, login, payment, and ordering outside that approval.
- Post-build inspection of v0.1.72 caught an iOS generated-project permission nesting bug and an incomplete smoke-test crash filter. v0.1.73 writes the microphone and speech-recognition descriptions into the top-level app plist and verifies both bundle metadata and TCC launch logs before publishing simulator assets.
- Previous signed Android evidence: [v0.1.72](https://github.com/Harzva/mobilecode/releases/tag/v0.1.72) and its [APK workflow](https://github.com/Harzva/mobilecode/actions/runs/31123426875). The downloaded 33 MB asset has SHA-256 `acdada50092e7aa2e9727ee8a45e9c20f4c977b4be6e7c21f0ce48e1be955101`, verifies with the MobileCode release certificate, and clean-launched on the Android 16 ARM64 emulator.
- Previous stable evidence: [v0.1.69](https://github.com/Harzva/mobilecode/releases/tag/v0.1.69) and its [Android APK workflow](https://github.com/Harzva/mobilecode/actions/runs/31091939149).
- [Version Policy](docs/mobilecode-version-policy.md)
- [Release QA Checklist](docs/mobilecode-release-qa.md)
- [Helper Runtime Protocol](docs/mobilecode-helper-runtime-protocol.md)
- [Production Hardening Notes](docs/mobilecode-production-hardening.md)

## Roadmap

| Priority | Next focus | Stop condition |
| --- | --- | --- |
| P0 | Pass Mobile Runtime CI, Android APK build, Android smoke test for the pushed commit | APK artifact is downloadable and app launches |
| P1 | Smooth Repo Hub file edit conflict handling and artifact download UX | User can recover from SHA conflicts and find downloaded artifacts |
| P2 | Expand API-backed workspace into selected repo file import/export | Phone can edit selected repo files without true clone |
| Later | Helper APK maturity, queue recovery, PTY, cloud heavy builds | Runtime remains replaceable behind `RuntimeProvider` |

## Status

This repository is actively moving toward a deployable mobile coding workspace. The Android build path is GitHub Actions-first; local machines without Flutter/Android SDK should use CI artifacts instead of local builds.

## License

No license file is included yet. Add a `LICENSE` before treating this as a reusable open-source distribution.
