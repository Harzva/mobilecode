import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'model_provider_preset_service.dart';

enum TuimaConnectionState {
  unavailable,
  serviceReady,
  modelReady,
}

class MobileCoreCapabilities {
  const MobileCoreCapabilities({
    this.textInput = false,
    this.imageInput = false,
    this.audioInput = false,
    this.videoInput = false,
    this.textOutput = false,
    this.audioOutput = false,
  });

  final bool textInput;
  final bool imageInput;
  final bool audioInput;
  final bool videoInput;
  final bool textOutput;
  final bool audioOutput;

  bool supports(MobileCoreAttachmentKind kind) => switch (kind) {
        MobileCoreAttachmentKind.image => imageInput,
        MobileCoreAttachmentKind.audio => audioInput,
      };

  Map<String, Object> get evidenceSnapshot => {
        'textInput': textInput,
        'imageInput': imageInput,
        'audioInput': audioInput,
        'videoInput': videoInput,
        'textOutput': textOutput,
        'audioOutput': audioOutput,
      };

  factory MobileCoreCapabilities.fromJson(Object? value) {
    final map = _stringMap(value);
    return MobileCoreCapabilities(
      textInput: map['text_input'] == true,
      imageInput: map['image_input'] == true,
      audioInput: map['audio_input'] == true,
      videoInput: map['video_input'] == true,
      textOutput: map['text_output'] == true,
      audioOutput: map['audio_output'] == true,
    );
  }
}

class MobileCoreArtifactHealth {
  const MobileCoreArtifactHealth({
    this.fileName = '',
    this.digestAlgorithm = '',
    this.expectedDigest = '',
    this.expectedBytes = 0,
    this.present = false,
    this.verified = false,
  });

  final String fileName;
  final String digestAlgorithm;
  final String expectedDigest;
  final int expectedBytes;
  final bool present;
  final bool verified;

  factory MobileCoreArtifactHealth.fromJson(Object? value) {
    final map = _stringMap(value);
    return MobileCoreArtifactHealth(
      fileName: map['file_name']?.toString() ?? '',
      digestAlgorithm: map['digest_algorithm']?.toString() ?? '',
      expectedDigest: map['digest']?.toString() ?? '',
      expectedBytes: _asInt(map['expected_bytes']),
      present: map['present'] == true || map['installed'] == true,
      verified: map['verified'] == true,
    );
  }
}

class MobileCoreResourceHealth {
  const MobileCoreResourceHealth({
    this.availableBytes = 0,
    this.requiredBytes = 0,
    this.ok = false,
  });

  final int availableBytes;
  final int requiredBytes;
  final bool ok;

  double get pressure => availableBytes <= 0 || requiredBytes <= 0
      ? 0
      : requiredBytes / availableBytes;

  factory MobileCoreResourceHealth.fromJson(Object? value) {
    final map = _stringMap(value);
    return MobileCoreResourceHealth(
      availableBytes: _asInt(map['available_bytes']),
      requiredBytes: _asInt(map['required_bytes']),
      ok: map['ok'] == true,
    );
  }
}

class MobileCorePreflight {
  const MobileCorePreflight({
    this.memory = const MobileCoreResourceHealth(),
    this.storage = const MobileCoreResourceHealth(),
    this.ok = false,
    this.failureCode,
  });

  final MobileCoreResourceHealth memory;
  final MobileCoreResourceHealth storage;
  final bool ok;
  final String? failureCode;

  factory MobileCorePreflight.fromJson(Object? value) {
    final map = _stringMap(value);
    return MobileCorePreflight(
      memory: MobileCoreResourceHealth.fromJson(map['memory']),
      storage: MobileCoreResourceHealth.fromJson(map['storage']),
      ok: map['ok'] == true,
      failureCode: _nullableString(map['failure_code']),
    );
  }
}

class MobileCoreMetrics {
  const MobileCoreMetrics({
    this.activeModel,
    this.backend = '',
    this.decodeTokensPerSecond = 0,
    this.firstTokenMs = 0,
    this.totalMs = 0,
    this.memoryPeakMb = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final String? activeModel;
  final String backend;
  final double decodeTokensPerSecond;
  final int firstTokenMs;
  final int totalMs;
  final int memoryPeakMb;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  Map<String, Object?> get evidenceMetadata => {
        'activeModel': activeModel,
        'backend': backend,
        'decodeTokensPerSecond': decodeTokensPerSecond,
        'firstTokenMs': firstTokenMs,
        'totalMs': totalMs,
        'memoryPeakMb': memoryPeakMb,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'totalTokens': totalTokens,
      };

  factory MobileCoreMetrics.fromJson(Object? value) {
    final map = _stringMap(value);
    return MobileCoreMetrics(
      activeModel: _nullableString(map['active_model']),
      backend: map['backend']?.toString() ?? '',
      decodeTokensPerSecond: _asDouble(map['last_decode_tokens_per_second'] ??
          map['decode_tokens_per_second']),
      firstTokenMs: _asInt(map['last_first_token_ms'] ?? map['first_token_ms']),
      totalMs: _asInt(map['last_total_ms'] ?? map['total_ms']),
      memoryPeakMb: _asInt(map['memory_peak_mb']),
      promptTokens: _asInt(map['last_prompt_tokens'] ?? map['prompt_tokens']),
      completionTokens:
          _asInt(map['last_completion_tokens'] ?? map['completion_tokens']),
      totalTokens: _asInt(map['last_total_tokens'] ?? map['total_tokens']),
    );
  }
}

class MobileCoreModel {
  const MobileCoreModel({
    required this.id,
    this.quantization = 'unknown',
    this.contextLength = 0,
    this.sizeBytes = 0,
    this.loaded = false,
    this.architecture = 'unknown',
    this.parameterLabel,
    this.projectorId,
    this.projectorSizeBytes = 0,
    this.capabilities = const MobileCoreCapabilities(),
    this.benchmark,
  });

  final String id;
  final String quantization;
  final int contextLength;
  final int sizeBytes;
  final bool loaded;
  final String architecture;
  final String? parameterLabel;
  final String? projectorId;
  final int projectorSizeBytes;
  final MobileCoreCapabilities capabilities;
  final MobileCoreMetrics? benchmark;

  factory MobileCoreModel.fromJson(Object? value) {
    final map = _stringMap(value);
    final details = _stringMap(map['mobilecore']);
    return MobileCoreModel(
      id: map['id']?.toString() ?? '',
      quantization: details['quantization']?.toString() ?? 'unknown',
      contextLength: _asInt(details['context_length']),
      sizeBytes: _asInt(details['size_bytes']),
      loaded: details['loaded'] == true,
      architecture: details['architecture']?.toString() ?? 'unknown',
      parameterLabel: _nullableString(details['parameter_label']),
      projectorId: _nullableString(details['projector_id']),
      projectorSizeBytes: _asInt(details['projector_size_bytes']),
      capabilities: MobileCoreCapabilities.fromJson(details['capabilities']),
      benchmark: details['benchmark'] == null
          ? null
          : MobileCoreMetrics.fromJson(details['benchmark']),
    );
  }
}

class MobileCoreRecommendation {
  const MobileCoreRecommendation({
    required this.modelId,
    required this.fit,
    required this.score,
    this.expectedTokensPerSecond = 0,
    this.estimatedMemoryMb = 0,
    this.loaded = false,
    this.quantization = 'unknown',
    this.contextLength = 0,
    this.projectorId,
    this.projectorSizeBytes = 0,
    this.capabilities = const MobileCoreCapabilities(),
    this.reasons = const [],
  });

  final String modelId;
  final String fit;
  final double score;
  final double expectedTokensPerSecond;
  final int estimatedMemoryMb;
  final bool loaded;
  final String quantization;
  final int contextLength;
  final String? projectorId;
  final int projectorSizeBytes;
  final MobileCoreCapabilities capabilities;
  final List<String> reasons;

  factory MobileCoreRecommendation.fromJson(Object? value) {
    final map = _stringMap(value);
    return MobileCoreRecommendation(
      modelId: map['model_id']?.toString() ?? '',
      fit: map['fit']?.toString() ?? 'unknown',
      score: _asDouble(map['score']),
      expectedTokensPerSecond: _asDouble(map['expected_tokens_per_second']),
      estimatedMemoryMb: _asInt(map['estimated_memory_mb']),
      loaded: map['loaded'] == true,
      quantization: map['quantization']?.toString() ?? 'unknown',
      contextLength: _asInt(map['context_length']),
      projectorId: _nullableString(map['projector_id']),
      projectorSizeBytes: _asInt(map['projector_size_bytes']),
      capabilities: MobileCoreCapabilities.fromJson(map['capabilities']),
      reasons: _stringList(map['reasons']),
    );
  }
}

class MobileCoreRecommendations {
  const MobileCoreRecommendations({
    this.availableRamMb = 0,
    this.lowRamDevice = false,
    this.internalStorageFreeMb = 0,
    this.recommendations = const [],
  });

  final int availableRamMb;
  final bool lowRamDevice;
  final int internalStorageFreeMb;
  final List<MobileCoreRecommendation> recommendations;

  factory MobileCoreRecommendations.fromJson(Object? value) {
    final map = _stringMap(value);
    final device = _stringMap(map['device']);
    return MobileCoreRecommendations(
      availableRamMb: _asInt(device['available_ram_mb']),
      lowRamDevice: device['low_ram_device'] == true,
      internalStorageFreeMb: _asInt(device['internal_storage_free_mb']),
      recommendations: _objectList(map['recommendations'])
          .map(MobileCoreRecommendation.fromJson)
          .where((item) => item.modelId.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class MobileCoreRuntimeSnapshot {
  const MobileCoreRuntimeSnapshot({
    required this.health,
    required this.capturedAt,
    this.models = const [],
    this.metrics = const MobileCoreMetrics(),
    this.recommendations = const MobileCoreRecommendations(),
  });

  final TuimaHealth health;
  final List<MobileCoreModel> models;
  final MobileCoreMetrics metrics;
  final MobileCoreRecommendations recommendations;
  final DateTime capturedAt;
}

enum MobileCoreAttachmentKind { image, audio }

class MobileCoreAttachment {
  MobileCoreAttachment({
    required this.kind,
    required this.bytes,
    required this.mimeType,
    required this.displayName,
    this.audioFormat,
  }) {
    final limit =
        kind == MobileCoreAttachmentKind.image ? maxImageBytes : maxAudioBytes;
    if (bytes.isEmpty || bytes.length > limit) {
      throw ArgumentError('Attachment exceeds MobileCore local media limits.');
    }
  }

  static const int maxImageBytes = 20 * 1024 * 1024;
  static const int maxAudioBytes = 25 * 1024 * 1024;

  final MobileCoreAttachmentKind kind;
  final Uint8List bytes;
  final String mimeType;
  final String displayName;
  final String? audioFormat;

  Map<String, dynamic> toContentPart() {
    final encoded = base64Encode(bytes);
    return switch (kind) {
      MobileCoreAttachmentKind.image => {
          'type': 'image_url',
          'image_url': {'url': 'data:$mimeType;base64,$encoded'},
        },
      MobileCoreAttachmentKind.audio => {
          'type': 'input_audio',
          'input_audio': {
            'data': encoded,
            'format': audioFormat ?? _audioFormatForMime(mimeType),
          },
        },
    };
  }

  Map<String, Object> get evidenceMetadata => {
        'kind': kind.name,
        'mimeType': mimeType,
        'bytes': bytes.length,
        'redaction': 'payload_omitted',
      };
}

class MobileCoreProviderException implements Exception {
  const MobileCoreProviderException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'MobileCoreProviderException($code): $message';
}

class TuimaHealth {
  const TuimaHealth({
    required this.state,
    required this.version,
    required this.backend,
    required this.activeModel,
    this.runtime = '',
    this.runtimeRevision = '',
    this.quantization = 'unknown',
    this.capabilities = const MobileCoreCapabilities(),
    this.mainArtifact = const MobileCoreArtifactHealth(),
    this.projectorArtifact = const MobileCoreArtifactHealth(),
    this.preflight = const MobileCorePreflight(),
    this.audioSampleRateHz = 0,
    this.failure,
  });

  final TuimaConnectionState state;
  final String version;
  final String backend;
  final String? activeModel;
  final String runtime;
  final String runtimeRevision;
  final String quantization;
  final MobileCoreCapabilities capabilities;
  final MobileCoreArtifactHealth mainArtifact;
  final MobileCoreArtifactHealth projectorArtifact;
  final MobileCorePreflight preflight;
  final int audioSampleRateHz;
  final String? failure;

  bool get canInfer => state == TuimaConnectionState.modelReady;

  factory TuimaHealth.unavailable(Object failure) => TuimaHealth(
        state: TuimaConnectionState.unavailable,
        version: '',
        backend: '',
        activeModel: null,
        capabilities: const MobileCoreCapabilities(),
        failure: failure.toString(),
      );

  Map<String, Object?> get evidenceMetadata => {
        'serviceVersion': version,
        'activeModel': activeModel,
        'backend': backend,
        'runtime': runtime,
        'runtimeRevision': runtimeRevision,
        'quantization': quantization,
        'modelLoaded': canInfer,
        'capabilities': capabilities.evidenceSnapshot,
        'preflightOk': preflight.ok,
        'preflightFailure': preflight.failureCode,
        'mainArtifactPresent': mainArtifact.present,
        'mainArtifactVerified': mainArtifact.verified,
        'projectorArtifactPresent': projectorArtifact.present,
        'projectorArtifactVerified': projectorArtifact.verified,
        'redaction': 'prompt_and_media_omitted',
      };
}

enum HybridModelPreference {
  localPreferred,
  cloudPreferred,
  localOnly,
}

enum HybridModelTarget {
  tuimaLocal,
  cloud,
  unavailable,
}

enum HybridModelRouteReason {
  localModelReady,
  cloudPreferredAndConfigured,
  localUnavailableCloudFallback,
  localOnlyUnavailable,
  noProviderAvailable,
}

class HybridModelRouteDecision {
  const HybridModelRouteDecision({
    required this.target,
    required this.reason,
    required this.canRetryOnCloud,
  });

  final HybridModelTarget target;
  final HybridModelRouteReason reason;
  final bool canRetryOnCloud;
}

class MobileCoreClient {
  MobileCoreClient({
    HttpClient? client,
    Uri? healthUri,
    Uri? chatUri,
    Uri? modelsUri,
    Uri? metricsUri,
    Uri? recommendationsUri,
    Uri? modelLoadUri,
    Uri? modelUnloadUri,
    Uri? omniStatusUri,
  })  : _client = client ?? HttpClient(),
        healthUri = healthUri ?? Uri.parse('http://127.0.0.1:8080/health'),
        chatUri =
            chatUri ?? Uri.parse('http://127.0.0.1:8080/v1/chat/completions'),
        modelsUri = modelsUri ?? Uri.parse('http://127.0.0.1:8080/v1/models'),
        metricsUri = metricsUri ?? Uri.parse('http://127.0.0.1:8080/metrics'),
        recommendationsUri = recommendationsUri ??
            Uri.parse('http://127.0.0.1:8080/v1/recommendations'),
        modelLoadUri = modelLoadUri ??
            Uri.parse('http://127.0.0.1:8080/mobilecore/model/load'),
        modelUnloadUri = modelUnloadUri ??
            Uri.parse('http://127.0.0.1:8080/mobilecore/model/unload'),
        omniStatusUri = omniStatusUri ??
            Uri.parse('http://127.0.0.1:8080/mobilecore/omni/status');

  final HttpClient _client;
  final Uri healthUri;
  final Uri chatUri;
  final Uri modelsUri;
  final Uri metricsUri;
  final Uri recommendationsUri;
  final Uri modelLoadUri;
  final Uri modelUnloadUri;
  final Uri omniStatusUri;

  Future<TuimaHealth> probe({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final request = await _client.getUrl(healthUri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return TuimaHealth.unavailable('HTTP ${response.statusCode}');
      }
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
        return TuimaHealth.unavailable('Invalid TuiMa health payload');
      }
      final modelLoaded = payload['model_loaded'] == true;
      final artifacts = _stringMap(payload['artifacts']);
      return TuimaHealth(
        state: modelLoaded
            ? TuimaConnectionState.modelReady
            : TuimaConnectionState.serviceReady,
        version: payload['version']?.toString() ?? '',
        backend: payload['backend']?.toString() ?? '',
        activeModel: _nullableString(payload['active_model']),
        runtime: payload['runtime']?.toString() ?? '',
        runtimeRevision: payload['llama_cpp_revision']?.toString() ?? '',
        quantization: payload['quantization']?.toString() ?? 'unknown',
        capabilities: MobileCoreCapabilities.fromJson(payload['capabilities']),
        mainArtifact: MobileCoreArtifactHealth.fromJson(artifacts['main']),
        projectorArtifact:
            MobileCoreArtifactHealth.fromJson(artifacts['mmproj']),
        preflight: MobileCorePreflight.fromJson(payload['preflight']),
        audioSampleRateHz: _asInt(payload['audio_sample_rate_hz']),
      );
    } on Object catch (error) {
      return TuimaHealth.unavailable(error);
    }
  }

  Future<List<MobileCoreModel>> listModels({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final payload = await _getJson(modelsUri, timeout: timeout);
    return _objectList(payload['data'])
        .map(MobileCoreModel.fromJson)
        .where((model) => model.id.isNotEmpty && model.sizeBytes > 0)
        .toList(growable: false);
  }

  Future<MobileCoreMetrics> metrics({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      MobileCoreMetrics.fromJson(
        await _getJson(metricsUri, timeout: timeout),
      );

  Future<MobileCoreRecommendations> recommendations({
    String preference = 'stability',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final safePreference = switch (preference) {
      'speed' => 'speed',
      'small' || 'small_model' => 'small',
      _ => 'stability',
    };
    final uri = recommendationsUri.replace(
      queryParameters: {
        ...recommendationsUri.queryParameters,
        'preference': safePreference,
      },
    );
    return MobileCoreRecommendations.fromJson(
      await _getJson(uri, timeout: timeout),
    );
  }

  Future<Map<String, dynamic>> omniStatus({
    Duration timeout = const Duration(seconds: 5),
  }) =>
      _getJson(omniStatusUri, timeout: timeout);

  /// Reads one coherent control-plane view of the active MobileCore runtime.
  ///
  /// Model switches can happen in the MobileCore app while MobileCode is
  /// fetching models, metrics, and recommendations. Health is sampled on both
  /// sides and a changed runtime is retried once so the UI never combines
  /// capabilities from one model with metrics from another.
  Future<MobileCoreRuntimeSnapshot> runtimeSnapshot({
    Duration timeout = const Duration(seconds: 5),
    int consistencyRetries = 1,
  }) async {
    var before = await probe(timeout: timeout);
    if (before.state == TuimaConnectionState.unavailable) {
      return MobileCoreRuntimeSnapshot(
        health: before,
        capturedAt: DateTime.now(),
      );
    }

    final retries = consistencyRetries.clamp(0, 3);
    for (var attempt = 0; attempt <= retries; attempt += 1) {
      final results = await Future.wait<Object?>([
        listModels(timeout: timeout),
        metrics(timeout: timeout),
        recommendations(timeout: timeout),
      ]);
      final models = results[0] as List<MobileCoreModel>;
      final runtimeMetrics = results[1] as MobileCoreMetrics;
      final deviceRecommendations = results[2] as MobileCoreRecommendations;
      final after = await probe(timeout: timeout);
      if (after.state == TuimaConnectionState.unavailable) {
        return MobileCoreRuntimeSnapshot(
          health: after,
          capturedAt: DateTime.now(),
        );
      }
      if (_isConsistentRuntimeSnapshot(
        before: before,
        after: after,
        models: models,
        metrics: runtimeMetrics,
      )) {
        return MobileCoreRuntimeSnapshot(
          health: after,
          models: models,
          metrics: runtimeMetrics,
          recommendations: deviceRecommendations,
          capturedAt: DateTime.now(),
        );
      }
      before = after;
    }

    throw const MobileCoreProviderException(
      code: 'runtime_snapshot_changed',
      message: 'MobileCore changed state while the runtime snapshot was read.',
    );
  }

  Future<TuimaHealth> loadModel(
    String modelId, {
    String? projectorId,
    int contextLength = 4096,
    int threads = 4,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final normalized = _validatedPublicArtifactId(
      modelId,
      code: 'invalid_model_id',
      label: 'model',
    );
    final normalizedProjector = projectorId == null
        ? null
        : _validatedPublicArtifactId(
            projectorId,
            code: 'invalid_projector_id',
            label: 'projector',
          );
    await _postJson(
      modelLoadUri,
      {
        'model_id': normalized,
        if (normalizedProjector != null)
          'projector_id': normalizedProjector,
        'context_length': contextLength.clamp(128, 32768),
        'threads': threads.clamp(1, 16),
        'gpu_layers': 0,
      },
      timeout: timeout,
    );
    final health = await probe(timeout: const Duration(seconds: 5));
    if (!health.canInfer || health.activeModel != normalized) {
      throw const MobileCoreProviderException(
        code: 'model_state_mismatch',
        message: 'MobileCore did not confirm the requested active model.',
      );
    }
    return health;
  }

  /// Switches the active runtime using public artifact identifiers only.
  ///
  /// MobileCore uses the authenticated load route for both initial loading and
  /// cross-model switching. This dedicated method makes the control intent
  /// explicit and keeps lifecycle payload construction inside the v2 client.
  Future<TuimaHealth> switchModel(
    String modelId, {
    String? projectorId,
    int contextLength = 4096,
    int threads = 4,
    Duration timeout = const Duration(minutes: 2),
  }) =>
      loadModel(
        modelId,
        projectorId: projectorId,
        contextLength: contextLength,
        threads: threads,
        timeout: timeout,
      );

  Future<TuimaHealth> unloadModel({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await _postJson(modelUnloadUri, const {}, timeout: timeout);
    final health = await probe(timeout: const Duration(seconds: 5));
    if (health.canInfer) {
      throw const MobileCoreProviderException(
        code: 'model_state_mismatch',
        message: 'MobileCore still reports a loaded model after unload.',
      );
    }
    return health;
  }

  String resolveActiveModel(TuimaHealth health) {
    final model = health.activeModel?.trim() ?? '';
    if (!health.canInfer || model.isEmpty) {
      throw const MobileCoreProviderException(
        code: 'model_not_loaded',
        message: 'MobileCore is running but no local model is loaded.',
      );
    }
    return model;
  }

  Future<String> completeChat({
    required List<Map<String, dynamic>> messages,
    required String model,
    int maxTokens = 1024,
    Duration timeout = const Duration(minutes: 2),
    void Function(MobileCoreMetrics metrics)? onMetrics,
  }) async {
    final response = await _postChat(
      messages: messages,
      model: model,
      maxTokens: maxTokens,
      stream: false,
      timeout: timeout,
    );
    final body = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _providerError(response.statusCode, body);
    }
    final responsePayload = _decodedMap(body);
    onMetrics?.call(_inferenceMetrics(responsePayload));
    final answer = _extractAssistantText(body);
    if (answer.isEmpty) {
      throw const FormatException('TuiMa returned an empty response');
    }
    return answer;
  }

  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    required String model,
    int maxTokens = 1024,
    Duration timeout = const Duration(minutes: 3),
    void Function(MobileCoreMetrics metrics)? onMetrics,
  }) async* {
    final response = await _postChat(
      messages: messages,
      model: model,
      maxTokens: maxTokens,
      stream: true,
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decodeStream(response).timeout(timeout);
      throw _providerError(response.statusCode, body);
    }

    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    if (mimeType != 'text/event-stream') {
      final body = await utf8.decodeStream(response).timeout(timeout);
      final answer = _extractAssistantText(body);
      onMetrics?.call(_inferenceMetrics(_decodedMap(body)));
      if (answer.isEmpty) {
        throw const FormatException('TuiMa returned an empty response');
      }
      yield answer;
      return;
    }

    var emitted = false;
    await for (final line in response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(timeout)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith(':') ||
          trimmed.startsWith('event:')) {
        continue;
      }
      final payload =
          trimmed.startsWith('data:') ? trimmed.substring(5).trim() : trimmed;
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) continue;
      if (decoded['mobilecore'] != null || decoded['usage'] != null) {
        onMetrics?.call(_inferenceMetrics(decoded));
      }
      final delta = _extractDelta(decoded);
      if (delta.isNotEmpty) {
        emitted = true;
        yield delta;
      }
    }
    if (!emitted) {
      throw const FormatException('TuiMa stream completed without text');
    }
  }

  Future<HttpClientResponse> _postChat({
    required List<Map<String, dynamic>> messages,
    required String model,
    required int maxTokens,
    required bool stream,
    required Duration timeout,
  }) async {
    final request = await _client.postUrl(chatUri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      stream ? 'text/event-stream' : ContentType.json.mimeType,
    );
    _authorize(request);
    final body = utf8.encode(jsonEncode({
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'stream': stream,
    }));
    // NanoHTTPD 2.3.1 does not reliably decode Dart's default chunked request
    // bodies. A fixed content length keeps the loopback OpenAI request portable.
    request.contentLength = body.length;
    request.add(body);
    return request.close().timeout(timeout);
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required Duration timeout,
  }) async {
    final request = await _client.getUrl(uri).timeout(timeout);
    _authorize(request);
    final response = await request.close().timeout(timeout);
    final body = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _providerError(response.statusCode, body);
    }
    return _decodedMap(body);
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    required Duration timeout,
  }) async {
    final request = await _client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    _authorize(request);
    final bytes = utf8.encode(jsonEncode(payload));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(timeout);
    final body = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _providerError(response.statusCode, body);
    }
    return _decodedMap(body);
  }

  void _authorize(HttpClientRequest request) {
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${ModelProviderPresetService.tuimaLocalToken}',
    );
    request.headers.set('X-MobileCore-Client', 'mobilecode-v2');
  }

  static Map<String, dynamic> _decodedMap(String body) {
    final value = jsonDecode(body);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const MobileCoreProviderException(
      code: 'invalid_response',
      message: 'MobileCore returned an invalid JSON response.',
    );
  }

  static MobileCoreProviderException _providerError(
    int statusCode,
    String body,
  ) {
    try {
      final payload = _decodedMap(body);
      final error = _stringMap(payload['error']);
      final code = error['code']?.toString().trim();
      final message = error['message']?.toString().trim();
      return MobileCoreProviderException(
        code: code == null || code.isEmpty ? 'http_error' : code,
        message: message == null || message.isEmpty
            ? 'MobileCore request failed with HTTP $statusCode.'
            : _compact(message),
        statusCode: statusCode,
      );
    } on Object {
      return MobileCoreProviderException(
        code: 'http_error',
        message: 'MobileCore request failed with HTTP $statusCode.',
        statusCode: statusCode,
      );
    }
  }

  static MobileCoreMetrics _inferenceMetrics(Map<String, dynamic> payload) {
    final metrics =
        Map<String, dynamic>.from(_stringMap(payload['mobilecore']));
    final usage = _stringMap(payload['usage']);
    metrics
      ..['active_model'] = payload['model']
      ..['prompt_tokens'] = usage['prompt_tokens']
      ..['completion_tokens'] = usage['completion_tokens']
      ..['total_tokens'] = usage['total_tokens'];
    return MobileCoreMetrics.fromJson(metrics);
  }

  static String _extractAssistantText(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return '';
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    return message['content']?.toString().trim() ?? '';
  }

  static String _extractDelta(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final delta = first['delta'];
    if (delta is Map && delta['content'] != null) {
      return delta['content'].toString();
    }
    final message = first['message'];
    if (message is Map && message['content'] != null) {
      return message['content'].toString();
    }
    return '';
  }

  static String _compact(String value, {int limit = 240}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= limit
        ? normalized
        : '${normalized.substring(0, limit)}...';
  }

  static String _validatedPublicArtifactId(
    String value, {
    required String code,
    required String label,
  }) {
    final normalized = value.trim();
    final hasControlCharacter = normalized.runes.any(
      (rune) => rune < 0x20 || rune == 0x7f,
    );
    if (normalized.isEmpty ||
        normalized.length > 240 ||
        hasControlCharacter ||
        normalized.contains('/') ||
        normalized.contains('\\') ||
        normalized == '.' ||
        normalized == '..') {
      throw MobileCoreProviderException(
        code: code,
        message: 'A valid public MobileCore $label id is required.',
      );
    }
    return normalized;
  }

  static bool _isConsistentRuntimeSnapshot({
    required TuimaHealth before,
    required TuimaHealth after,
    required List<MobileCoreModel> models,
    required MobileCoreMetrics metrics,
  }) {
    if (before.state != after.state ||
        before.activeModel != after.activeModel ||
        before.runtime != after.runtime ||
        before.runtimeRevision != after.runtimeRevision ||
        before.backend != after.backend ||
        before.quantization != after.quantization ||
        before.projectorArtifact.fileName != after.projectorArtifact.fileName ||
        before.capabilities.textInput != after.capabilities.textInput ||
        before.capabilities.imageInput != after.capabilities.imageInput ||
        before.capabilities.audioInput != after.capabilities.audioInput ||
        before.capabilities.videoInput != after.capabilities.videoInput ||
        before.capabilities.textOutput != after.capabilities.textOutput ||
        before.capabilities.audioOutput != after.capabilities.audioOutput) {
      return false;
    }
    final metricsModel = metrics.activeModel?.trim() ?? '';
    if (metricsModel.isNotEmpty && metricsModel != after.activeModel) {
      return false;
    }
    final loadedModels = models.where((model) => model.loaded).toList();
    if (!after.canInfer) return loadedModels.isEmpty;
    return loadedModels.length <= 1 &&
        (loadedModels.isEmpty || loadedModels.single.id == after.activeModel);
  }

  void close() => _client.close(force: true);

  static HybridModelRouteDecision route({
    required HybridModelPreference preference,
    required TuimaConnectionState localState,
    required bool cloudConfigured,
  }) {
    final localReady = localState == TuimaConnectionState.modelReady;
    if (preference == HybridModelPreference.cloudPreferred && cloudConfigured) {
      return const HybridModelRouteDecision(
        target: HybridModelTarget.cloud,
        reason: HybridModelRouteReason.cloudPreferredAndConfigured,
        canRetryOnCloud: false,
      );
    }
    if (localReady) {
      return HybridModelRouteDecision(
        target: HybridModelTarget.tuimaLocal,
        reason: HybridModelRouteReason.localModelReady,
        canRetryOnCloud: cloudConfigured,
      );
    }
    if (preference == HybridModelPreference.localOnly) {
      return const HybridModelRouteDecision(
        target: HybridModelTarget.unavailable,
        reason: HybridModelRouteReason.localOnlyUnavailable,
        canRetryOnCloud: false,
      );
    }
    if (cloudConfigured) {
      return const HybridModelRouteDecision(
        target: HybridModelTarget.cloud,
        reason: HybridModelRouteReason.localUnavailableCloudFallback,
        canRetryOnCloud: false,
      );
    }
    return const HybridModelRouteDecision(
      target: HybridModelTarget.unavailable,
      reason: HybridModelRouteReason.noProviderAvailable,
      canRetryOnCloud: false,
    );
  }

  static HybridModelRouteDecision fallbackAfterCloudFailure({
    required TuimaConnectionState localState,
    required bool emittedCloudText,
  }) {
    if (!emittedCloudText && localState == TuimaConnectionState.modelReady) {
      return const HybridModelRouteDecision(
        target: HybridModelTarget.tuimaLocal,
        reason: HybridModelRouteReason.localModelReady,
        canRetryOnCloud: false,
      );
    }
    return const HybridModelRouteDecision(
      target: HybridModelTarget.unavailable,
      reason: HybridModelRouteReason.noProviderAvailable,
      canRetryOnCloud: false,
    );
  }

  static Map<String, String> localOpenAiConfig() => const {
        'provider': 'custom',
        'baseUrl': ModelProviderPresetService.tuimaBaseUrl,
        'model': ModelProviderPresetService.tuimaModel,
        'apiKey': ModelProviderPresetService.tuimaLocalToken,
      };
}

/// Backward-compatible name while callers migrate to [MobileCoreClient].
class TuimaProviderService extends MobileCoreClient {
  TuimaProviderService({
    super.client,
    super.healthUri,
    super.chatUri,
    super.modelsUri,
    super.metricsUri,
    super.recommendationsUri,
    super.modelLoadUri,
    super.modelUnloadUri,
    super.omniStatusUri,
  });

  static HybridModelRouteDecision route({
    required HybridModelPreference preference,
    required TuimaConnectionState localState,
    required bool cloudConfigured,
  }) =>
      MobileCoreClient.route(
        preference: preference,
        localState: localState,
        cloudConfigured: cloudConfigured,
      );

  static HybridModelRouteDecision fallbackAfterCloudFailure({
    required TuimaConnectionState localState,
    required bool emittedCloudText,
  }) =>
      MobileCoreClient.fallbackAfterCloudFailure(
        localState: localState,
        emittedCloudText: emittedCloudText,
      );

  static Map<String, String> localOpenAiConfig() =>
      MobileCoreClient.localOpenAiConfig();
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Object?> _objectList(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

List<String> _stringList(Object? value) => _objectList(value)
    .map((item) => item?.toString().trim() ?? '')
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

String? _nullableString(Object? value) {
  if (value == null) return null;
  final result = value.toString().trim();
  if (result.isEmpty || result.toLowerCase() == 'null') return null;
  return result;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _audioFormatForMime(String mimeType) =>
    switch (mimeType.toLowerCase().split(';').first) {
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      'audio/mpeg' => 'mp3',
      'audio/flac' || 'audio/x-flac' => 'flac',
      'audio/ogg' => 'ogg',
      'audio/mp4' || 'audio/x-m4a' || 'audio/aac' => 'm4a',
      _ => throw ArgumentError('Unsupported MobileCore audio MIME type.'),
    };
