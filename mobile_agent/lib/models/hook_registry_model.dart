// lib/models/hook_registry_model.dart
// Read-only hook registry model for MobileCode extension management.

enum HookPhase {
  chat,
  runtime,
  files,
  preview,
  release,
  memory,
}

extension HookPhaseLabel on HookPhase {
  String get label {
    switch (this) {
      case HookPhase.chat:
        return 'Chat';
      case HookPhase.runtime:
        return 'Runtime';
      case HookPhase.files:
        return 'Files';
      case HookPhase.preview:
        return 'Preview';
      case HookPhase.release:
        return 'Release';
      case HookPhase.memory:
        return 'Memory';
    }
  }
}

enum HookSafetyLevel {
  readOnly,
  gated,
  deferred,
}

extension HookSafetyLevelLabel on HookSafetyLevel {
  String get label {
    switch (this) {
      case HookSafetyLevel.readOnly:
        return 'Read-only';
      case HookSafetyLevel.gated:
        return 'Runtime-gated';
      case HookSafetyLevel.deferred:
        return 'Deferred';
    }
  }
}

class HookRegistryEntry {
  const HookRegistryEntry({
    required this.id,
    required this.name,
    required this.phase,
    required this.enabled,
    required this.owner,
    required this.description,
    required this.safetyLevel,
  });

  final String id;
  final String name;
  final HookPhase phase;
  final bool enabled;
  final String owner;
  final String description;
  final HookSafetyLevel safetyLevel;
}

class HookRegistrySnapshot {
  const HookRegistrySnapshot({required this.entries});

  final List<HookRegistryEntry> entries;

  int get enabledCount => entries.where((entry) => entry.enabled).length;
  int get deferredCount =>
      entries.where((entry) => entry.safetyLevel == HookSafetyLevel.deferred).length;

  static const HookRegistrySnapshot v1 = HookRegistrySnapshot(
    entries: [
      HookRegistryEntry(
        id: 'chat.before_model_call',
        name: 'Before model call',
        phase: HookPhase.chat,
        enabled: true,
        owner: 'Model provider guard',
        description: 'Validate provider, base URL, model, timeout, and cancellation state before a request starts.',
        safetyLevel: HookSafetyLevel.readOnly,
      ),
      HookRegistryEntry(
        id: 'chat.after_model_response',
        name: 'After model response',
        phase: HookPhase.chat,
        enabled: true,
        owner: 'Agent process trace',
        description: 'Record response status, generated artifact path, and user-visible recovery details.',
        safetyLevel: HookSafetyLevel.readOnly,
      ),
      HookRegistryEntry(
        id: 'runtime.before_execute',
        name: 'Before runtime execute',
        phase: HookPhase.runtime,
        enabled: true,
        owner: 'RuntimeProvider policy',
        description: 'Check workspace bounds, timeout, command policy, and selected runtime capabilities.',
        safetyLevel: HookSafetyLevel.gated,
      ),
      HookRegistryEntry(
        id: 'runtime.after_execute',
        name: 'After runtime execute',
        phase: HookPhase.runtime,
        enabled: true,
        owner: 'Runtime task reporter',
        description: 'Capture exit code, failure kind, recent logs, duration, and retry suggestion.',
        safetyLevel: HookSafetyLevel.readOnly,
      ),
      HookRegistryEntry(
        id: 'files.before_write',
        name: 'Before file write',
        phase: HookPhase.files,
        enabled: true,
        owner: 'Artifact writer',
        description: 'Normalize artifact paths and keep writes inside the MobileCode workspace.',
        safetyLevel: HookSafetyLevel.gated,
      ),
      HookRegistryEntry(
        id: 'preview.after_open',
        name: 'After preview open',
        phase: HookPhase.preview,
        enabled: true,
        owner: 'Preview surface',
        description: 'Expose code file, WebView preview, external browser link, and phone file location.',
        safetyLevel: HookSafetyLevel.readOnly,
      ),
      HookRegistryEntry(
        id: 'release.before_publish',
        name: 'Before release publish',
        phase: HookPhase.release,
        enabled: false,
        owner: 'Release QA',
        description: 'Reserved for CI evidence, version rule, artifact hash, and manual install gate checks.',
        safetyLevel: HookSafetyLevel.deferred,
      ),
      HookRegistryEntry(
        id: 'memory.before_write',
        name: 'Before memory write',
        phase: HookPhase.memory,
        enabled: false,
        owner: 'Memory manager',
        description: 'Reserved for user approval and redaction before durable memory is stored.',
        safetyLevel: HookSafetyLevel.deferred,
      ),
    ],
  );
}
