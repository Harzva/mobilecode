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
  public `projector_id` only.

The v2 client reads health before and after the models/metrics/recommendations
bundle. If MobileCore changes the active runtime during that window, MobileCode
retries once and then returns the typed `runtime_snapshot_changed` result rather
than combining capabilities from one model with metrics from another. Lifecycle
IDs containing path separators or control characters are rejected before a
request is sent, and a switch is successful only when `/health` reports the
exact requested public model ID.

The TuiMa control sheet exposes that state inside MobileCode. Image and audio entry points are capability-gated. Selected media is held only in memory, sent only to the local MobileCore endpoint, removed after the request, and excluded from saved chat turns and ActionEvidence. A local-only media request fails closed instead of falling back to cloud inference.

Adaptive routing currently applies these rules:

- privacy-sensitive or offline work stays on MobileCore;
- local image/audio work requires an advertised local capability;
- memory or thermal pressure reduces context to 2048 tokens and selects the smallest safe installed recommendation, including when privacy/offline routing is also active; multimodal attachments retain their capability-compatible active model instead of blindly switching to a text-only recommendation;
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

## Local vision chain

A separate controlled emulator check used a Qwen3.5 0.8B main GGUF plus its mmproj. `/v1/models` exposed the projector as metadata on the main model, loading returned `image_input=true`, and `/health` reported `runtime=llama.cpp/libmtmd`. A real JPEG data-URI request completed through the same OpenAI-compatible endpoint with 93 total tokens and 542 MB reported runtime memory. There was no crash, ANR, or OOM.

This is capability/transport evidence, not a vision-quality result. The model answered the controlled animal-breed prompt incorrectly, so MobileCode must not describe the current vision route as accuracy-qualified. Generic imported artifacts were also correctly reported as present but unverified.

The repeatable runner is:

```bash
python3 scripts/run_mobilecore_dual_app_qa.py \
  --serial <dedicated-qa-device> \
  --model-file <controlled-gguf> \
  --require-model-switch
```

The counted physical-device lane must opt into both property-based physical-device enforcement and a sustained offline inference workload:

```bash
python3 scripts/run_mobilecore_dual_app_qa.py \
  --serial <physical-android-serial> \
  --model-file <controlled-gguf> \
  --require-model-switch \
  --require-physical-device \
  --require-thermal \
  --thermal-duration-seconds 900 \
  --thermal-sample-seconds 15
```

The v2 runner verifies `ro.kernel.qemu`, `ro.boot.qemu`, hardware, and model properties instead of trusting the adb serial prefix. During the thermal lane it keeps the device offline, repeatedly performs bounded local inference, and records only numeric temperature/status samples plus aggregate request and failure counts. Raw `dumpsys` output and inference responses are never written.

Raw screenshots and sanitized logcat remain under the ignored `.qa-artifacts/` directory. The runner's manifest contains APK/model hashes, step digests, safe metrics, environment class, and redaction state; it does not persist model filenames, prompts, responses, images, audio, credentials, cookies, tokens, raw UI text, raw system dumps, or host paths.

## Verification

- The complete MobileCode Flutter suite passed 565 tests after the Client v2,
  adaptive-routing, pressure-switch, proactive-offline, and one-task cloud
  approval follow-ups.
- The focused MobileCore client suite passed 16 tests, including coherent
  runtime snapshots, exact switch confirmation, public projector IDs,
  path-like ID rejection, projector metadata, and image-capability parsing.
- The focused adaptive-policy suite passed 13 tests, including privacy/offline
  fail-closed routing, cloud-consent gating, constrained context/model choice,
  one-task approval expiry semantics, and multimodal capability retention under
  resource pressure.
- Four network-transport tests cover definitive no-network routing, available
  transport, unknown/error behavior, and evidence redaction. Interface type,
  SSID, address, and probe-host details are never recorded.
- Two approval-card widget tests cover approve/decline behavior and confirm the
  card does not render request content.
- A local Android arm64 `pureRelease` build passed and its manifest version was
  verified as `0.1.73+63`; this local build is validation evidence only and is
  not the stable-signed GitHub Release asset.
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
- MobileCore local API instrumentation passed its model-ID control, incompatible-projector rejection, no-path response, multimodal contract, rejection, and metrics-counter checks.
- A post-fix real-GGUF smoke reported active-model preflight `625617760` required bytes versus `1096425472` available bytes, `runtime=llama.cpp`, two completed requests, zero failures, and a non-zero average decode rate.
- MobileCode `pureDebug` APK and cross-app Android test APK built successfully.
- The dual-app runner privacy/classification/thermal workload passes five deterministic host-side unit tests.
- ActionEvidence inference-to-device linking passes focused unit coverage, including idempotency and action-type rejection.

## Remaining Release Gates

Before claiming phone-grade local intelligence or using this route for ordering acceptance:

1. Run the same 30-task lane on a physical Android device and retain reviewed evidence.
2. Repeat the two-model switch and memory-pressure lane on physical hardware; emulator acceptance is complete.
3. Install a verified Qwen2.5-Omni pair and pass image/audio local-only tasks without cloud fallback.
4. Add a labeled vision task set and quality threshold; the current real image run proves execution but not accuracy.
5. Measure sustained-device temperature, battery, background restriction, and process recovery on physical hardware.
6. Keep transaction approval and final device actions in MobileCode; never expose a MobileCore action bypass.
