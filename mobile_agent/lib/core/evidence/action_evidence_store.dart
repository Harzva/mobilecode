// lib/core/evidence/action_evidence_store.dart
// In-memory store for ActionEvidence records.
//
// Dependency-free: no SharedPreferences, no database, no IO.
// Designed for H02 scope; persistence can be added later.

import 'evidence_model.dart';

/// In-memory store for [ActionEvidence] records.
///
/// Provides add, getById, recent, clear, and JSON roundtrip.
/// Thread-safe for single-isolate Flutter usage.
class ActionEvidenceStore {
  static final shared = ActionEvidenceStore._internal();

  ActionEvidenceStore();

  ActionEvidenceStore._internal();

  final List<ActionEvidence> _records = [];

  /// All stored evidence records (insertion order).
  List<ActionEvidence> get records => List.unmodifiable(_records);

  /// Number of stored records.
  int get length => _records.length;

  /// Whether the store is empty.
  bool get isEmpty => _records.isEmpty;

  /// Whether the store has records.
  bool get isNotEmpty => _records.isNotEmpty;

  /// Add an evidence record. Overwrites if same evidenceId exists.
  void add(ActionEvidence evidence) {
    _records.removeWhere((r) => r.evidenceId == evidence.evidenceId);
    _records.add(evidence);
  }

  /// Get evidence by its unique id, or null if not found.
  ActionEvidence? getById(String evidenceId) {
    for (final r in _records) {
      if (r.evidenceId == evidenceId) return r;
    }
    return null;
  }

  /// Link one MobileCore inference record to the Phone Use operation that it
  /// informed. The relation is bidirectional and stores identifiers only.
  /// Raw prompts, screenshots, media, and credential values are never copied.
  bool linkMobileCoreInferenceToDeviceOperation({
    required String inferenceEvidenceId,
    required String deviceOperationEvidenceId,
  }) {
    if (!_isSafeEvidenceId(inferenceEvidenceId) ||
        !_isSafeEvidenceId(deviceOperationEvidenceId)) {
      return false;
    }
    final inferenceIndex = _records.indexWhere(
      (record) => record.evidenceId == inferenceEvidenceId,
    );
    final deviceIndex = _records.indexWhere(
      (record) => record.evidenceId == deviceOperationEvidenceId,
    );
    if (inferenceIndex == -1 || deviceIndex == -1) return false;

    final inference = _records[inferenceIndex];
    final device = _records[deviceIndex];
    if (inference.actionName != MobileCodeAction.traceCallProvider ||
        inference.metadata['inferenceProvider'] != 'mobilecore' ||
        inference.metadata['inferenceLocation'] != 'on_device' ||
        !{
          MobileCodeAction.phoneUseObserve,
          MobileCodeAction.phoneUseAct,
          MobileCodeAction.phoneUseCapture,
          MobileCodeAction.phoneUseReplay,
        }.contains(device.actionName)) {
      return false;
    }

    _records[inferenceIndex] = _withEvidenceRelation(
      inference,
      key: 'deviceOperationEvidenceIds',
      relatedEvidenceId: deviceOperationEvidenceId,
    );
    _records[deviceIndex] = _withEvidenceRelation(
      device,
      key: 'mobileCoreInferenceEvidenceIds',
      relatedEvidenceId: inferenceEvidenceId,
    );
    return true;
  }

  /// Return the most recent [count] records (newest first).
  List<ActionEvidence> recent({int count = 10}) {
    final sorted = List<ActionEvidence>.of(_records)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.take(count).toList();
  }

  /// Return all records for a given action name.
  List<ActionEvidence> byAction(MobileCodeAction action) {
    return _records.where((r) => r.actionName == action).toList();
  }

  /// Return all failed records.
  List<ActionEvidence> failures() {
    return _records.where((r) => !r.success).toList();
  }

  /// Clear all stored records.
  void clear() {
    _records.clear();
  }

  /// Serialize the entire store to a JSON-encodable list.
  List<Map<String, dynamic>> toJson() {
    return _records.map((r) => r.toJson()).toList();
  }

  /// Load records from a JSON list, replacing current contents.
  void loadFromJson(List<dynamic> jsonList) {
    _records.clear();
    for (final item in jsonList) {
      if (item is Map<String, dynamic>) {
        _records.add(ActionEvidence.fromJson(item));
      }
    }
  }

  ActionEvidence _withEvidenceRelation(
    ActionEvidence evidence, {
    required String key,
    required String relatedEvidenceId,
  }) {
    final existingRelations = evidence.metadata[key];
    final relations = <String>{
      if (existingRelations is List)
        ...existingRelations
            .map((value) => value.toString().trim())
            .where(_isSafeEvidenceId),
      relatedEvidenceId,
    }.toList(growable: false);
    return ActionEvidence(
      evidenceId: evidence.evidenceId,
      actionName: evidence.actionName,
      paramsSummary: evidence.paramsSummary,
      startedAt: evidence.startedAt,
      endedAt: evidence.endedAt,
      success: evidence.success,
      artifactPaths: evidence.artifactPaths,
      urls: evidence.urls,
      logs: evidence.logs,
      exitCode: evidence.exitCode,
      failureKind: evidence.failureKind,
      recoveryActions: evidence.recoveryActions,
      metadata: {
        ...evidence.metadata,
        key: relations,
      },
    );
  }
}

bool _isSafeEvidenceId(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value);
