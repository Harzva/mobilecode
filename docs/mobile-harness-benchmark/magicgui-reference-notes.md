# MagicGUI Reference Notes for MobileHarnessBench

MagicGUI is useful as a reference model for GUI-agent perception and action
evaluation, but it should not change MobileCode's core framing. MobileCode is a
phone-native coding harness: it evaluates whether an agent can close loops on
files, previews, runtime providers, GitHub delivery, Lark/relay evidence, and
mobile build artifacts. MagicGUI mainly strengthens the mobile GUI perception
and action-control side of that story.

## Useful Ideas to Adopt

- **Normalized action schema.** MagicGUI uses a compact single-action output with
  coordinates normalized to a 0-1000 screen space. MobileHarnessBench can adopt a
  similar optional adapter for mobile UI action traces so Android and iOS actions
  are easier to compare across screen sizes.
- **Separate grounding from task success.** MagicGUI reports grounding-oriented
  metrics alongside success-rate style metrics. MobileHarnessBench should keep
  its end-to-end verifier, but can add secondary labels for action targeting,
  UI state recognition, and recovery quality.
- **Explicit status actions.** MagicGUI-style statuses such as finish,
  impossible, interrupt, and need_feedback map well to MobileCode evidence
  states like action_completed, verifier_failed, user_takeover_required, and
  runtime_blocked.
- **Exception handling as a first-class split.** MagicGUI's Handling_Exception
  category suggests a dedicated MobileHarnessBench slice for permission prompts,
  network failures, missing scopes, flaky emulators, and relay/event-consumer
  downtime.
- **Evaluation adapters for external GUI benchmarks.** MagicGUI evaluates across
  ScreenQA, ScreenSpot, AndroidControl, OS-Atlas, and GUI-Odyssey style tasks.
  MobileHarnessBench should not become only a GUI benchmark, but it can include
  an adapter layer that imports GUI grounding tasks as a perception sub-benchmark.

## What Not to Copy Directly

- **Do not collapse MobileHarnessBench into screen tapping.** MobileCode's
  distinctive evidence is the coding harness loop: file state, preview state,
  tool traces, runtime-provider state, release artifacts, and verifier output.
- **Do not require a large local VLM as the default benchmark participant.**
  MagicGUI is model-centric; MobileCode should remain model-agnostic and measure
  the harness contract that any remote or local agent can use.
- **Do not treat coordinate accuracy as enough.** A correct tap is only useful if
  it advances the phone-native coding workflow and produces auditable evidence.

## Paper Framing

MagicGUI can be cited as adjacent work on mobile GUI agents with scalable data,
visual grounding, unified action spaces, and reinforcement fine-tuning. The
contrast for the Mobile Harness paper is:

- MagicGUI asks whether a model can perceive and act on mobile screens.
- MobileHarnessBench asks whether an agent running through a phone-native
  harness can complete software-development loops with verifiable mobile
  evidence.

This makes MagicGUI a strong related-work anchor for the GUI-agent layer, while
MobileCode's novelty should remain the phone-native coding-harness layer.
