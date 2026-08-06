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
- model load, unload, and switch controls using public `model_id` only.

The TuiMa control sheet exposes that state inside MobileCode. Image and audio entry points are capability-gated. Selected media is held only in memory, sent only to the local MobileCore endpoint, removed after the request, and excluded from saved chat turns and ActionEvidence. A local-only media request fails closed instead of falling back to cloud inference.

Adaptive routing currently applies these rules:

- privacy-sensitive or offline work stays on MobileCore;
- local image/audio work requires an advertised local capability;
- memory or thermal pressure reduces context to 2048 tokens and selects the smallest safe installed recommendation;
- complex cloud routing requires explicit approval;
- Phone Use plans may use MobileCore inference, but every device action remains in MobileCode's approval and evidence boundary.

## Controlled Android Run

Date: 2026-08-06

Environment: Android 16 arm64 emulator, 2 CPU cores, approximately 2.5 GB RAM. This is emulator evidence, not physical-device evidence.

Model: `qwen2.5-0.5b-instruct-q4_k_m.gguf`

Model SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`

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
| Cross-model switch | Not run | Only one installed model was available |
| Physical thermal behavior | Not run | Emulator temperature is not physical-device evidence |
| Physical Android device | Not run | No Android physical device was connected |

Observed final-request metrics on the constrained emulator were approximately 0.43 decode tokens/s, 3.1 seconds to first token, 12.4 seconds total for a four-token controlled response, and 462 MB runtime peak memory. These numbers characterize this software-emulated host only and are not phone performance claims.

The repeatable runner is:

```bash
python3 scripts/run_mobilecore_dual_app_qa.py \
  --serial <dedicated-qa-device> \
  --model-file <controlled-gguf>
```

Raw screenshots and sanitized logcat remain under the ignored `.qa-artifacts/` directory. The runner's manifest contains APK/model hashes, step digests, safe metrics, environment class, and redaction state; it does not persist prompts, images, audio, credentials, cookies, tokens, raw UI text, or host paths.

## Verification

- 90 focused Flutter evidence/routing/provider tests passed.
- 16 MobileCore client and adaptive-policy tests passed.
- MobileCore Android unit tests passed.
- MobileCore local API instrumentation passed its model-ID control, no-path response, multimodal contract, rejection, and metrics-counter checks.
- A post-fix real-GGUF smoke reported active-model preflight `625617760` required bytes versus `1096425472` available bytes, `runtime=llama.cpp`, two completed requests, zero failures, and a non-zero average decode rate.
- MobileCode `pureDebug` APK and cross-app Android test APK built successfully.

## Remaining Release Gates

Before claiming phone-grade local intelligence or using this route for ordering acceptance:

1. Run the same 30-task lane on a physical Android device and retain reviewed evidence.
2. Install at least two compatible models and pass real cross-model switching under memory pressure.
3. Install a verified Qwen2.5-Omni pair and pass image/audio local-only tasks without cloud fallback.
4. Measure sustained-device temperature, battery, background restriction, and process recovery on physical hardware.
5. Keep transaction approval and final device actions in MobileCode; never expose a MobileCore action bypass.
