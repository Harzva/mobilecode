# MobileCode ↔ MobileCore Dual-App QA

## Boundary

MobileCore is the on-device inference engine. It owns model discovery, loading, unloading, runtime execution, multimodal capability reporting, resource preflight, recommendations, and performance metrics.

MobileCode is the control center. It owns model routing, user consent, Phone Use, transaction-risk classification, one-shot approvals, tool execution, and ActionEvidence. MobileCore cannot click, type, log in, approve a transaction, or place an order.

## Implemented Link

`MobileCoreClient` discovers the active model and runtime instead of relying on a hard-coded model name. The negotiated snapshot includes:

- active model, backend, runtime, runtime revision, and quantization;
- text, image, audio, video, and output capabilities;
- model/projector artifact presence and verification state;
- memory/storage preflight and typed failure code;
- installed models, device recommendations, and decode/latency metrics;
- model load, unload, and switch controls using public `model_id` and optional
  public `projector_id` only;
- typed verified-Omni status plus a dedicated load control that refuses partial
  or unverified pairs and rechecks the active `/health` runtime, artifact
  verification and pinned digests, and requested image/audio capability after
  loading.

The v2 client reads health before and after the models/metrics/recommendations
bundle. If MobileCore changes the active runtime during that window, MobileCode
retries once and then returns the typed `runtime_snapshot_changed` result rather
than combining capabilities from one model with metrics from another. Lifecycle
IDs containing path separators or control characters are rejected before a
request is sent, and a switch is successful only when `/health` reports the
exact requested public model ID.

Model switching also performs a projected post-switch memory check. MobileCode
may count the current runtime peak as reclaimable only when health and metrics
identify the same active model, caps that value by the active model's estimated
memory, and keeps 10% projected headroom. Under pressure it reduces requested
context to at most 2048 tokens. The client revalidates the runtime identity
immediately before the load request; a concurrent model, backend, capability,
quantization, or background-state change returns `runtime_snapshot_changed`
without sending `/mobilecore/model/load`.

The TuiMa control sheet exposes that state inside MobileCode. When MobileCore
reports a complete verified Omni pair that is not active, the sheet offers an
explicit local activation control. Image and audio entry points remain hidden
until the loaded runtime's `/health` response advertises the corresponding
capability. If an already-selected attachment survives an external model
change, MobileCode may reactivate that verified pair, then repeats the runtime
capability check before sending any media. Selected media is held only in
memory, sent only to the local MobileCore endpoint, removed after the request,
and excluded from saved chat turns and ActionEvidence. A local-only media
request fails closed instead of falling back to cloud inference.

This control path proves protocol enforcement and fail-closed selection; it is
not evidence that the large Qwen2.5-Omni artifacts have run successfully on a
physical phone. That remains a separate gate below.

Adaptive routing currently applies these rules:

- privacy-sensitive or offline work stays on MobileCore;
- local image/audio work requires an advertised local capability;
- memory or thermal pressure reduces context to 2048 tokens and selects the smallest safe installed recommendation, including when privacy/offline routing is also active; multimodal attachments retain their capability-compatible active model instead of blindly switching to a text-only recommendation;
- the latest completed decode rate, or the service average while the latest rate is unavailable, caps the next local output budget at 8, 32, 128, or 256 tokens, preventing an extremely slow runtime from accepting an unbounded mobile request;
- complex cloud routing requires explicit approval;
- Phone Use plans may use MobileCore inference, but every device action remains in MobileCode's approval and evidence boundary.

Before chat or Agent traffic opens a cloud request, MobileCode checks the current
OS network-transport state and derives an in-memory task signal from definitive
no-network state, explicit credential/login/payment markers, the previously
detected cloud-transport failure state, request size, and Agent mode. A
definitive offline result routes to MobileCore before the first cloud request;
available or unknown transport remains guarded by timeout/failure fallback
because an active Wi-Fi or mobile interface does not prove internet access. The
signal omits request text and network identifiers from evidence. If the local
service is unavailable, privacy/offline routing fails closed. Selecting a cloud
provider only makes that route available. Every long-context or Agent task must
receive a separate one-task approval card before any cloud request opens;
declining keeps the task on MobileCore or cancels it when the local runtime is
unavailable. Approval evidence stores only the approval ID, decision, provider
preset, scope, and redacted routing booleans. MobileCode never changes a
TuiMa-only request to cloud on its own.

MobileCode requires the `mobilecore.local` protocol-v2 declaration before any
model control or inference call. A timeout or explicit Agent pause sends an
authenticated, content-free cancellation request. MobileCore serializes access
to its shared llama context and returns `runtime_busy` to overlapping chat or
model-lifecycle requests instead of allowing concurrent native decode.

When local inference informs a Phone Use approval card, MobileCode now links the two ActionEvidence records by identifier in both directions: the inference record stores `deviceOperationEvidenceIds`, and the device record stores `mobileCoreInferenceEvidenceIds`. The relation contains IDs only; prompts, media, screenshots, typed values, and credentials are not copied into either record.

## Controlled Android Run

Date: 2026-08-06

Environment: Android 16 arm64 emulator, 2 CPU cores, approximately 2.5 GB RAM. This is emulator evidence, not physical-device evidence.

Primary model: `qwen2.5-0.5b-instruct-q4_k_m.gguf`

Model SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`

Switch model: `qwen3-0.6b-q4_k_m.gguf`

Switch-model SHA-256: `18ea1f301079bba6391ab6d455c0c8565fd5a3214075eb2cd9daf351dedc719b`

The host-side runner installed MobileCore, MobileCode, and the MobileCode test APK on the same Android instance. It loaded the real GGUF through the visible MobileCore UI, enabled airplane mode, then executed the instrumentation test from the MobileCode process against MobileCore's loopback service.

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Buffered local inference | 15/15 passed | Real GGUF, MobileCode process to MobileCore loopback |
| SSE local inference | 15/15 passed | Stream completion marker and non-empty text asserted |
| Offline isolation | Passed | Airplane mode enabled for all 30 tasks and restored afterward |
| Model unload/reload | Passed | Public `model_id`; no client model path |
| Background continuity | Passed | MobileCore stayed ready after MobileCode became foreground |
| Low-memory notification | Passed | `RUNNING_LOW` delivered; health remained available |
| MobileCore process restart | Passed | Visible UI reload restored model-ready health |
| Cross-model switch | Passed | Qwen2.5 → Qwen3 load completed, then Qwen2.5 was restored |
| Physical thermal behavior | Not run | Emulator temperature is not physical-device evidence |
| Physical Android device | Not run | No Android physical device was connected |

Observed final-request metrics on the constrained emulator were approximately 0.46 decode tokens/s average, 2.9 seconds to first token, 11.6 seconds total, and 462 MB runtime peak memory. The final strict-run Qwen3 switch loaded in 1.2 seconds and reported 456 MB. These numbers characterize this software-emulated host only and are not phone performance claims.

### MobileCoreClient v2 control refresh

On 2026-08-07, a clean-built v0.1.73 `pureRelease` MobileCode APK containing the coherent
runtime snapshot and exact switch confirmation was installed on the same
Android 16 arm64 emulator. APK SHA-256 was
`f6a555adf103e775bdc2b3169acf9617119f0ae414d95f07d056f7239cdbecd5`.
Cold launch completed without an app crash, ANR, or OOM.

The real MobileCore control sheet atomically displayed the Qwen2.5 active model,
`llama.cpp`, CPU backend, `Q4_K_M`, ready preflight, capability state, 0.44
decode tokens/s, 2957 ms first-token latency, and 462 MB peak runtime memory.
The same UI then switched Qwen2.5 → Qwen3 and confirmed the exact Qwen3 public
ID as active with 456 MB peak memory, before restoring the exact Qwen2.5 public
ID. This proves the v2 control path against the running dual-app service, but it
remains emulator evidence and does not satisfy the physical-device gate.

### v0.1.78 projected-switch and offline regression

On 2026-08-07, the final `pureDebug` v0.1.78 (`68`) candidate containing the
projected-memory switch preflight was clean-built and reinstalled with its
Android test APK. The MobileCode APK SHA-256 was
`f7ef72d6f615edae7015e6113d0c60b14eabf0ae42181ebae7b2b490581f705c`.

The same Android 16 ARM64 emulator then passed the full 30-task cross-app lane
again in airplane mode: 15 buffered requests and 15 SSE requests completed in
274.615 seconds. The test asserted non-empty local output, SSE completion,
MobileCore metrics, and absence of the controlled prompt marker in metrics.
Airplane mode was restored by the host runner. MobileCode cold-launched as
v0.1.78, MobileCore 0.1.4-rc6 remained a foreground service with protocol v2
and the real Qwen2.5 GGUF loaded, and the post-run log scan found no app fatal
exception, ANR, OOM, or SIGABRT. This is repeatable emulator evidence; it does
not replace the pending physical-device lane.

The published, stable-signed `mobilecode-v0.1.78.apk` was then downloaded from
the successful Android release workflow. Its 33,073,027-byte payload and
SHA-256 `5123f48f93161838b166259061857b058ab63429051544e4ac0234088a886073`
match the GitHub Release record. It reports `0.1.78+68`, verifies with the
existing MobileCode release certificate, clean-installs and renders
`v0.1.78` plus `TuiMa 就绪`, while MobileCore remains a foreground protocol-v2
service with the real local model ready. Strict post-download scans found no
recognizable credential or concrete private-host-path value, and logcat found
no fatal exception, ANR, OOM, or SIGABRT.

### main-dev strict-evidence regression

On 2026-08-07, source commit `5dad210` was rebuilt after the physical-device
runner became fail-closed. The `pureDebug` APK SHA-256 was
`8866bbf09edac497bc15dc051cedce7e7c9ff56e428f9497afd1ce549c92e567`;
the matching AndroidTest APK SHA-256 was
`967847cbfac116ae30f59297d495f73eac763eea310df96e3c6bfe9406c47144`.
Both APKs verified with Android APK Signature Scheme v2.

The Android 16 ARM64 emulator then completed another 30-task dual-app run with
30 requests completed, zero request failures, and zero failed host steps across
37 recorded steps. The runner observed airplane mode enabled for the controlled
tasks and restored afterward, rather than writing a fixed offline claim. It also
completed a two-model switch and accepted `RUNNING_LOW` while MobileCore
remained model-ready. The active runtime reported about 0.35 average decode
tokens/s and 462 MB peak memory on this constrained emulator.

This run intentionally records multimodal as `not_available`: the active
MobileCore runtime advertised neither image nor audio input, so MobileCode did
not expose or execute those attachment lanes. Background-restriction recovery,
the 15-minute thermal lane, verified Omni media, and physical-device acceptance
remain open. A separate strict preflight supplied the same APKs to the emulator
with `--require-physical-device`; it verified all three pinned APK signatures,
classified the target as an emulator, failed before installation, and recorded
`offline_during_tasks=false`.

### Attachment reactivation and adaptive-switch regression

On 2026-08-07, MobileCode closed two client-side integration gaps without
changing the MobileCore/Phone Use authority boundary. A selected local image or
audio attachment now survives an external change to a text-only model when
MobileCore reports a complete verified Omni pair: the send preflight permits the
adaptive policy to reactivate that pair, and the actual request still requires
the refreshed `/health` capability. When memory or thermal pressure recommends a
smaller text model, the adaptive route now uses the coherent
`switchModelWithPreflight` lifecycle path and writes a redacted
`adaptive_pressure_switch` control record to ActionEvidence. Decode throttling
also falls back to MobileCore's completed service average when the latest request
has not yet published its own rate.

The complete Flutter regression suite passed 583 tests and the focused
MobileCore/adaptive-policy/evidence set passed 88 tests. A new `pureDebug`
v0.1.78 (`68`) APK was built with SHA-256
`eeb22d81cb53903bc5342c9a38f9328d670d53ce7718deef02e2c210e41172ef`;
the AndroidTest APK SHA-256 remained
`967847cbfac116ae30f59297d495f73eac763eea310df96e3c6bfe9406c47144`.
Both verify with Android APK Signature Scheme v2. These are local debug build and
contract-regression results, not physical-device, verified-Omni, or release-asset
acceptance.

### One-task cloud approval check

On 2026-08-07, the one-task cloud approval path was exercised through the real
MobileCode UI on the same Android arm64 emulator. After synchronizing the
feature with the v0.1.75 release baseline, a clean universal `pureRelease` QA
APK had SHA-256
`ca6d6908b3c4d315a76adf5d974c4e923df2a3acd9d43d6566a2fad074a0511d`.
The Gradle and Flutter output timestamps, sizes, and hashes matched, and the
compiled binary contained the approval-card labels before installation. This
extra check was added after QA detected and rejected an older copied APK whose
timestamp did not represent newly compiled Dart code. The synchronized v0.1.75
APK installed successfully and cold-launched in 0.5 seconds without a crash,
ANR, or OOM on the emulator. Its signing certificate is explicitly identified
as Android Debug, so it is QA evidence rather than a production-signed asset.

The emulator used a clearly fake, non-secret provider value and a benign
complex-task marker. Before any provider request opened, MobileCode displayed
the cloud inference approval card with the selected provider, the fact that
task context would leave the device, one-task scope, and an explicit statement
that the approval does not cover Phone Use, login, payment, or ordering. The
request text was not rendered by the card. Selecting `Use MobileCore` produced
no provider HTTP/401 event and routed the request into the local MobileCore
process. The constrained emulator did not complete that local inference within
the 120-second client limit; MobileCode surfaced the timeout and restored the
composer without falling back to cloud. This proves the approval and
fail-closed route on an emulator, not local-model performance or physical-device
readiness.

### Published v0.1.75 Android artifact

The [v0.1.75 Android release workflow](https://github.com/Harzva/mobilecode/actions/runs/31127234312)
completed successfully from the tagged merge commit. A fresh download of the
official `mobilecode-v0.1.75.apk` reported `0.1.75+65`, measured 33,047,539
bytes, and matched both the GitHub asset digest and local SHA-256
`66e7a26bb7efa4b3c6f959b3e8063fb05a25f91e5b13463211c80c60da5272e2`.
The APK verifies with Signature Scheme v2 and the MobileCode release
certificate (`CN=MobileCode, O=Harzva`), not the Android Debug certificate.

The downloaded official APK installed cleanly after removing the differently
signed QA build from the Android 16 ARM64 emulator. The first cold launch
reached Android's microphone-consent sheet in 1.254 seconds. Dismissing that
sheet returned `com.mobilecode.app/.MainActivity` to the resumed state with the
process alive and the `v0.1.75` home screen visible. The captured logcat had no
MobileCode fatal exception, ANR, process death, or out-of-memory signal. This is
release-package and emulator-launch evidence; it does not satisfy any physical
device, controlled-account, thermal, or Omni quality gate.

### Protocol-v2, chat-template, and cancellation refresh

On 2026-08-07, a pre-release MobileCode v0.1.76 (`66`) integration build and
MobileCore 0.1.4-rc4 (`8`) were
clean-built and installed on the Android 16 arm64 emulator. The MobileCode
`pureRelease` APK SHA-256 was
`4c0592cf7e0c1fd45145e3eaced74f405c5fe6fa96f72e7dcbd83a9657a8da11`;
the MobileCore debug QA APK SHA-256 was
`dcb2ae4c1c67c7171ab7c57a1996a6257950b92256c83dc93f20e3f3e03a7e44`.
The running `/health` response published `mobilecore.local` v2.0 with client
major range 2–2 and the exact active Qwen2.5 public model ID.

After applying the GGUF chat template, a direct controlled request returned
exactly `OK` instead of the off-topic continuation produced by the previous raw
role-text prompt. A fresh MobileCode chat then completed the same request through
TuiMa Local and displayed `OK` in the app. That cross-app request used 46 prompt
tokens and 1 completion token, completed in 18,313 ms, and reported 0.106655
decode tokens/s. These timings describe the constrained emulator only.

A separate 128-token request was cancelled through
`POST /mobilecore/inference/cancel`. The original request returned the typed
`cancelled` code, `/metrics` recorded one failed/cancelled request, and the
MobileCore process returned to 0.0% sampled CPU within two seconds without a
crash, ANR, or OOM. Instrumentation also proves that a concurrent second chat is
rejected as `runtime_busy`; this guard was added after an obsolete background QA
probe exposed that two simultaneous NanoHTTPD requests could otherwise enter the
same llama context.

After rebasing onto the published v0.1.75 approval and cross-app QA baseline,
the final v0.1.76 QA APK was installed from scratch. It cold-launched through
the Android microphone permission sheet, resumed `MainActivity`, displayed
`v0.1.76` and `TuiMa ready`, and again returned exactly `OK` for the controlled
request. Logcat contained no MobileCode crash, ANR, OOM, or SIGABRT marker. The
local APK is Android Debug-signed and is therefore QA evidence, not the
production-signed GitHub Release asset.

### Verified Omni activation control refresh

On 2026-08-07, a clean `pureDebug` MobileCode v0.1.77 (`67`) APK containing
the typed Omni status and dedicated verified-pair activation path was built,
installed, and cold-launched on the Android 16 ARM64 emulator. The APK SHA-256
was `3833b98f95c113454658d471e9824bb66d2f83c9117c03c48d192a86a47a3c11`.
Cold launch completed in 2,694 ms, the app remained resumed, and filtered logcat
contained no MobileCode fatal exception, ANR, OOM, or SIGABRT marker.

MobileCore 0.1.4-rc4 exposed protocol v2 and loaded the real local
`qwen2.5-0.5b-instruct-q4_k_m` runtime by public model ID. After a visible
service restart and control-sheet retry, MobileCode displayed the exact active
model, `llama.cpp`, CPU backend, `Q4_K_M`, 462 MB peak runtime memory, ready
preflight, three installed models, and explicit `image no · audio no`
capabilities. The stopped-service interval was surfaced as the typed
`service_unavailable` state instead of stale controls.

The same emulator lacked both pinned Qwen2.5-Omni artifacts, and its preflight
reported insufficient memory and storage for that pair. MobileCode therefore
did not render the verified-Omni activation control and did not expose image or
audio attachment entry points. This proves real dual-app capability gating and
the unverified/insufficient-resource refusal path; the successful activation
path remains contract-tested until a capable physical device with both verified
artifacts is available.

### Withdrawn v0.1.76 Android artifact

The official APK described below was withdrawn on 2026-08-07 after post-build
review found that its old public workflow supplied runtime service credentials
as Dart compile definitions. The remaining explicitly named debug-signed APK is
QA-only. The historical package checks are retained for traceability, but this
section is not a current download recommendation.

The [v0.1.76 Android release workflow](https://github.com/Harzva/mobilecode/actions/runs/31128209900)
completed all source-analysis, signing, build, version, artifact, and Release
upload steps from merge commit `0860190`. A fresh GitHub download of
`mobilecode-v0.1.76.apk` reported `0.1.76+66`, measured 33,053,383 bytes, and
matched the GitHub asset digest and local SHA-256
`52c53c26d51d6335588a443fd3f84f9a36ed9ac093de79a4238a23b2ff3ead31`.
It verifies with APK Signature Scheme v2 and the MobileCode release certificate
(`CN=MobileCode, O=Harzva`), not the Android Debug certificate.

After removing the differently signed QA app, the official APK installed on
the Android 16 ARM64 emulator, cold-launched through the microphone permission
sheet, resumed `MainActivity`, displayed `v0.1.76` and `TuiMa ready`, and
completed the controlled `Reply only OK` request with the exact answer `OK`.
The app process remained alive and logcat contained no crash, ANR, OOM, or
SIGABRT marker. This closes official package and emulator pairing evidence, not
the physical-device, controlled-account, thermal, background-recovery, or
full 30-task gates.

### Published v0.1.77 Android artifact and reopened background gate

The [v0.1.77 Android workflow](https://github.com/Harzva/mobilecode/actions/runs/31128587598)
ran from merge commit `d031692`, passed the new fail-closed credential policy,
and published an upload-signed `0.1.77+67` APK. A fresh download measured
33,046,287 bytes and SHA-256
`f008ede0e0305c835c3bf45bcc56f22c4fc911d0ae10b513f298d1bdfb0a1c1d`,
matching GitHub's asset digest. The APK verifies with Signature Scheme v2 and
the MobileCode release certificate. AOT string checks found no recognizable
key, bearer-token, JWT, or private host-path pattern.

The exact APK installed from scratch on the Android 16 ARM64 emulator, reported
version code 67 / version name 0.1.77, rendered `v0.1.77`, stayed alive, and
produced no fatal, ANR, OOM, or SIGABRT marker. MobileCore 0.1.4-rc4 separately
returned a compatible v2 health payload and loaded the controlled Qwen2.5 model
through its public model ID.

The final cross-app request was not counted as passed. After MobileCore updated
its foreground notification, Android's service record reported
`isForeground=false`; switching to MobileCode then froze the MobileCore process
and MobileCode correctly displayed `TuiMa offline`. This reopens the unattended
background-recovery gate and identifies the next fix: MobileCore must preserve
foreground-service state when refreshing its notification before the official
v0.1.77 APK is credited with a controlled local-chat pairing.

### MobileCore rc6 background closure and typed recovery state

MobileCore `0.1.4-rc6` reasserts its explicitly typed `dataSync` foreground
notification before model work on every service delivery. The acceptance lane
also discovered that Android had marked one emulator install as
`background_restricted`; AOSP intentionally strips foreground-service status
from packages in that state. That restricted run is recorded as a rejected
precondition, not as a runtime failure or pass, and neither production App
changes secure settings automatically.

After restoring the emulator through the same user-controlled background-use
policy represented by Android Battery settings, MobileCode remained resumed
for 40 authenticated polls (about two minutes) while MobileCore retained the
real Qwen2.5 0.5B model. All 40 health requests passed, the service ended with
`isForeground=true`, both processes remained alive and unfrozen, and the
filtered safety log contained no FGS timeout, ANR, OOM, or SIGABRT marker.

The follow-up client contract adds `background_restricted` to MobileCore
`/health`. MobileCode maps `true` to a typed, fail-closed recovery state,
preserves the active-model metadata for diagnosis, shows a Battery-settings
instruction, and sends no local inference payload until the restriction is
cleared. The full Flutter suite now passes 578 tests.

## Local vision chain

A separate controlled emulator check used a Qwen3.5 0.8B main GGUF plus its mmproj. `/v1/models` exposed the projector as metadata on the main model, loading returned `image_input=true`, and `/health` reported `runtime=llama.cpp/libmtmd`. A real JPEG data-URI request completed through the same OpenAI-compatible endpoint with 93 total tokens and 542 MB reported runtime memory. There was no crash, ANR, or OOM.

This is capability/transport evidence, not a vision-quality result. The model answered the controlled animal-breed prompt incorrectly, so MobileCode must not describe the current vision route as accuracy-qualified. Generic imported artifacts were also correctly reported as present but unverified.

On 2026-08-07, a new MobileCode-process instrumentation lane generated two
512×512 controlled PNG fixtures with different large digits, sent each through
the structured local OpenAI request to MobileCore, and required the two answers
to pass case-specific semantic checks and have different normalized-output
digests. AndroidJUnitRunner completed the latest device-side run in about 134.5
seconds with one test and zero failures. The active runtime was the same generic
Qwen3.5/libmtmd pair with `image_input=true`, `audio_input=false`, and both
artifacts explicitly `verified=false`. This improves cross-app image-path and
minimal non-collapse evidence; it does not overturn the failed breed probe,
qualify broad vision accuracy, prove audio, or satisfy verified Omni acceptance.

The host runner now judges AndroidJUnitRunner output rather than trusting the
`adb shell am instrument` process exit code. Android returns exit code zero even
when JUnit prints `FAILURES!!!`; the runner rejects those results, records only
a result digest and typed `instrumentation_failed`, and refreshes `/health`
immediately before media tasks so a reclaimed process or changed model cannot
reuse stale capability state. Model responses remain in test-process memory and
are compared by SHA-256 for non-collapse; they are not copied into the manifest
or assertion output.

The repeatable runner is:

```bash
python3 scripts/run_mobilecore_dual_app_qa.py \
  --serial <dedicated-qa-device> \
  --model-file <controlled-gguf> \
  --require-model-switch
```

The counted physical-device lane must opt into property-based physical-device
enforcement, host-controlled background restriction/recovery, and a sustained
offline inference workload. Strict physical mode refuses to start unless model
switching is required and the thermal duration is at least 900 seconds:

```bash
python3 scripts/run_mobilecore_dual_app_qa.py \
  --serial <physical-android-serial> \
  --model-file <controlled-gguf> \
  --expected-mobilecore-cert-sha256 <64-hex-fingerprint> \
  --expected-mobilecode-cert-sha256 <64-hex-fingerprint> \
  --expected-mobilecode-test-cert-sha256 <64-hex-fingerprint> \
  --require-model-switch \
  --require-physical-device \
  --require-background-recovery \
  --require-thermal \
  --thermal-duration-seconds 900 \
  --thermal-sample-seconds 15
```

The runner automatically executes MobileCode-process image/audio quality tasks
for every capability advertised by the active MobileCore `/health` snapshot.
The verified Omni gate additionally requires both pinned artifacts to report
`verified=true`, both media capabilities to be active, and all four controlled
image/audio cases to pass while the device is offline:

```bash
python3 scripts/run_mobilecore_dual_app_qa.py \
  --serial <physical-android-serial> \
  --expected-mobilecore-cert-sha256 <64-hex-fingerprint> \
  --expected-mobilecode-cert-sha256 <64-hex-fingerprint> \
  --expected-mobilecode-test-cert-sha256 <64-hex-fingerprint> \
  --require-model-switch \
  --require-physical-device \
  --require-background-recovery \
  --require-thermal \
  --thermal-duration-seconds 900 \
  --require-verified-omni
```

The image fixtures are generated in the MobileCode test process and contain
two labeled digits. The audio fixtures are generated PCM WAV tone/silence
pairs at MobileCore's advertised sample rate. Requests travel only to
`127.0.0.1` during airplane mode. The test process checks non-empty,
case-relevant, non-collapsed outputs; the host manifest stores only pass/fail,
capability and artifact-verification booleans, step digests, and numeric sample
rate. It never stores fixture bytes, prompts, response text, or data URIs.

The v2 runner verifies `ro.kernel.qemu`, `ro.boot.qemu`, hardware, and model
properties instead of trusting the adb serial prefix. It now treats airplane
mode as an asserted state rather than a best-effort command: both the enabled
state and post-test restoration must be observed through Android settings, and
the manifest derives `offline_during_tasks` from those observations instead of
hard-coding it. During the thermal lane it keeps the device offline, repeatedly
performs bounded local inference, and records only numeric temperature/status
samples plus aggregate request and failure counts. Raw `dumpsys` output and
inference responses are never written.

Strict physical mode also requires Android to accept the `RUNNING_LOW` trim
injection and requires MobileCore to remain model-ready afterward. A failed or
unsupported trim command is recorded as failed low-memory evidence and cannot
produce a passing physical manifest.

The background-recovery lane uses host-side ADB app-ops only on the dedicated
QA device. It snapshots the existing background modes, applies a temporary
restriction, verifies that the stopped MobileCore loopback service is
unavailable, restores the original modes, and requires a visible foreground
MobileCore recovery to reach `model_loaded=true`. The production apps never
edit app-ops or Android secure settings. Evidence contains booleans and step
digests only, not raw app-op output.

On 2026-08-07, this lane passed once on the Android 16 ARM64 emulator:
both restriction commands were accepted and observed, the stopped service was
unavailable while restricted, the original app-ops were restored, and a visible
MobileCore foreground recovery returned to `model_loaded=true`. This validates
the harness and recovery sequence only; it is not physical-device background
evidence.

Before a counted physical run installs anything, the runner uses `apksigner`
to compare all three APK certificate SHA-256 fingerprints with the explicitly
pinned values. It records only public certificate fingerprints and match
booleans, never keystore paths or passwords. The MobileCode app and its
instrumentation APK must use a compatible controlled QA signing identity;
this lane does not relabel that pair as the production-signed Release APK. The
official Release APK keeps its separate download, signature, cold-launch, and
TuiMa pairing evidence above.

Raw screenshots and sanitized logcat remain under the ignored `.qa-artifacts/` directory. The runner's manifest contains APK/model hashes, step digests, safe metrics, environment class, and redaction state; it does not persist model filenames, prompts, responses, images, audio, credentials, cookies, tokens, raw UI text, raw system dumps, or host paths.

## Verification

- The complete MobileCode Flutter suite passed 577 tests after the Client v2,
  adaptive-routing, pressure-switch, proactive-offline, one-task cloud approval,
  protocol-handshake, cancellation, and bounded-output follow-ups.
- The focused MobileCore client/adaptive-policy/approval suite passed 43 tests
  covering coherent
  runtime snapshots, exact switch confirmation, public projector IDs,
  path-like ID rejection, projector metadata, image-capability parsing,
  verified-Omni activation, partial-pair rejection, post-load pinned-digest
  matching, and audio capability confirmation.
- The focused adaptive-policy coverage includes privacy/offline
  fail-closed routing, cloud-consent gating, constrained context/model choice,
  one-task approval expiry semantics, and multimodal capability retention under
  resource pressure.
- Four network-transport tests cover definitive no-network routing, available
  transport, unknown/error behavior, and evidence redaction. Interface type,
  SSID, address, and probe-host details are never recorded.
- Two approval-card widget tests cover approve/decline behavior and confirm the
  card does not render request content.
- A clean local Android arm64 `pureRelease` build passed and its manifest version was
  verified as `0.1.76+66`; this local build is validation evidence only and is
  not the stable-signed GitHub Release asset.
- A later `pureDebug` v0.1.77 (`67`) APK with verified-Omni activation control
  also built, installed, cold-launched, and rendered the real MobileCore control
  state on the Android 16 ARM64 emulator. It is debug-signed QA evidence, not a
  release asset.
- The real emulator UI displayed the one-task cloud approval card before a
  complex cloud request. Declining routed to MobileCore, and the subsequent
  local timeout remained fail-closed instead of opening the cloud provider.
- APK acceptance now compares the final Flutter artifact with the Gradle output
  and checks compiled approval labels, preventing a copied stale artifact from
  being mistaken for a fresh build.
- A local iOS Simulator build also passed after adding the OS connectivity
  plugin, confirming the proactive-offline route compiles on both mobile
  platforms. This remains simulator build evidence, not physical-iOS QA.
- MobileCore Android unit tests passed.
- MobileCore local API instrumentation passed 2/2 tests covering model-ID control, incompatible-projector rejection, no-path response, multimodal contract, request-body consumption, cancellation, serialized inference, `runtime_busy`, and metrics counters.
- A post-fix real-GGUF smoke reported active-model preflight `625617760` required bytes versus `1096425472` available bytes, `runtime=llama.cpp`, two completed requests, zero failures, and a non-zero average decode rate.
- MobileCode `pureDebug` APK and cross-app Android test APK built successfully.
- The dual-app runner privacy, classification, multimodal, thermal,
  background-recovery, APK-signing, and strict physical-gate paths pass 16
  deterministic host-side unit tests, including mandatory model switching,
  15-minute thermal duration, observed airplane-mode restoration, and
  fail-closed `RUNNING_LOW` injection.
- ActionEvidence inference-to-device linking passes focused unit coverage, including idempotency and action-type rejection.
- The final v0.1.78 client regression passes 583 Flutter tests, including stale-runtime rejection before model load, projected-memory refusal without a load request, and decode-rate fallback to the completed service average.

## Remaining Release Gates

Before claiming phone-grade local intelligence or using this route for ordering acceptance:

1. Run the same 30-task lane on a physical Android device and retain reviewed evidence.
2. Repeat the two-model switch and memory-pressure lane on physical hardware; emulator acceptance is complete.
3. Install a verified Qwen2.5-Omni pair and pass image/audio local-only tasks without cloud fallback.
4. Add a labeled vision task set and quality threshold; the current real image run proves execution but not accuracy.
5. Measure sustained-device temperature, battery, background restriction, and process recovery on physical hardware.
6. Keep transaction approval and final device actions in MobileCode; never expose a MobileCore action bypass.
