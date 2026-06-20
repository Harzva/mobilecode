# MobileCode Local Model Distribution Strategy

Last updated: 2026-06-19

## Release Rule

MobileCode release builds must not bundle LLM weight files in the APK.

The app may ship the local inference runtime, provider UI, model manager, and
documentation links, but model artifacts are user-installed assets. This keeps
the APK small, avoids store-review and license surprises, and lets users decide
whether their device storage, battery, and privacy needs justify local models.

## User Flow

1. The user opens Models and Provider.
2. MobileCode shows an On-device / Local model section.
3. The section lists recommended models from a signed or checksummed remote
   model manifest.
4. The user taps a download link or imports an existing model file.
5. MobileCode downloads into app-owned model storage using a temporary file.
6. MobileCode verifies size and checksum before marking the model ready.
7. The user selects the local model runtime and tokenizer.
8. MobileCode loads the runtime and shows memory use, load status, and tokens/s.

Local models are opt-in. If no model is downloaded, MobileCode continues to use
the configured remote provider.

## Model Manifest

The app should read a small JSON manifest from GitHub Pages or another public
static endpoint. The manifest should be safe to cache and should not contain
secrets.

Current public manifest path:

- Repository source: `docs/mobilecode-local-models.json`
- GitHub Pages URL: `https://harzva.github.io/mobilecode/mobilecode-local-models.json`

The first manifest entries are candidate/research entries, not direct install
artifacts. A model becomes a direct-install item only after MobileCode has a
mobile runtime artifact URL, tokenizer URL, SHA-256 checksums, memory guidance,
and license review.

Recommended fields:

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-06-19T00:00:00Z",
  "models": [
    {
      "id": "qwen3-0.6b-executorch",
      "displayName": "Qwen3 0.6B On-device",
      "runtime": "executorch",
      "platform": "android",
      "format": "pte",
      "modelUrl": "https://example.com/models/qwen3-0.6b/model.pte",
      "tokenizerUrl": "https://example.com/models/qwen3-0.6b/tokenizer.json",
      "modelSha256": "replace-with-real-sha256",
      "tokenizerSha256": "replace-with-real-sha256",
      "approxBytes": 500000000,
      "minRamMb": 4096,
      "license": "model-license-name",
      "notes": "Recommended starter model for local code/chat experiments."
    }
  ]
}
```

The manifest is for discovery and update messaging only. The app must still
verify each downloaded artifact before using it.

## Storage

Use app-owned model storage by default:

- Android: app private files directory, for example `files/models/<model-id>/`.
- iOS: app container documents or application support directory.
- User-imported files: copy into the app model directory before loading.

Do not rely on `/data/local/tmp` outside developer QA. That path is useful for
ADB experiments but not a production user flow.

## Runtime Boundary

MobileCode should expose a runtime abstraction before adding a concrete backend:

```text
LocalModelRuntime
  isAvailable()
  install(ModelManifestEntry)
  importFiles(modelPath, tokenizerPath)
  load(modelId)
  generate(prompt, options)
  stream(prompt, options)
  stats()
  unload()
```

Android can start with `ExecuTorchLocalModelRuntime`. iOS should use a separate
runtime path such as ExecuTorch iOS, Core ML, or MLX. The provider UI should not
assume Android and iOS use the same model artifact format.

## Product Guardrails

- Never auto-download a model during first launch.
- Ask before downloading large files, and show size before download starts.
- Offer a Wi-Fi-only toggle.
- Keep partial downloads as `*.tmp` and delete them on failure or cancel.
- Verify checksum before loading.
- Show a clear error for unsupported device RAM, missing tokenizer, checksum
  mismatch, or runtime load failure.
- Let users delete local models from the app.
- Keep remote providers available as the default fallback.

## First Product Target

Use the ExecuTorch phone deployment experiment as technical proof, but do not
ship the `stories110M` demo model as the product model.

Recommended first Android target:

- Runtime: ExecuTorch Android
- Model family: Qwen3 0.6B class
- Distribution: external `.pte` model plus tokenizer from the model manifest
- UI: local provider appears only after runtime support and model files are
  ready
