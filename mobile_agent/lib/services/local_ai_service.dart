// lib/services/local_ai_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// ─── Enums ────────────────────────────────────────────────────────────

/// Supported local models for offline code assistance.
enum LocalModel {
  /// StarCoder-1B: fast, good for code completion, ~400MB.
  starCoder1B('starcoder-1b', 'StarCoder-1B', 400 * 1024 * 1024, 'code'),

  /// CodeLlama-7B: better quality, slower, ~4GB.
  codeLlama7B('codellama-7b', 'CodeLlama-7B-Q4', 4 * 1024 * 1024 * 1024, 'code'),

  /// Phi-3 Mini: balanced speed/quality for general tasks, ~2GB.
  phi3('phi-3-mini', 'Phi-3-Mini-Instruct', 2 * 1024 * 1024 * 1024, 'general');

  final String modelId;
  final String displayName;
  final int sizeBytes;
  final String category;

  const LocalModel(this.modelId, this.displayName, this.sizeBytes, this.category);

  /// Human-readable size string (e.g., "400 MB").
  String get sizeString {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

/// Categories of AI tasks ranked by complexity.
enum TaskComplexity { simple, moderate, complex }

/// Exception thrown when local AI operations fail.
class LocalAIException implements Exception {
  final String message;
  final LocalModel? model;
  final dynamic originalError;

  const LocalAIException({
    required this.message,
    this.model,
    this.originalError,
  });

  @override
  String toString() => 'LocalAIException[${model?.modelId ?? 'none'}]: $message';
}

/// {@template local_ai_service}
/// Offline AI service that runs small LLM models locally.
///
/// Provides code completion, simple explanation, and basic error
/// suggestions without requiring an internet connection. Falls back
/// to the cloud API when online and the task exceeds local model
/// capabilities.
///
/// ## Model Lifecycle
/// ```
/// Not Downloaded -> Downloading -> Ready -> Loaded in Memory
///                                     |
///                               Evicted (memory pressure)
/// ```
///
/// ## Usage
/// ```dart
/// final ai = LocalAIService();
/// if (await ai.isModelAvailable()) {
///   final completion = await ai.completeCode(
///     'void main() {',
///     '',
///     'dart',
///   );
/// }
/// ```
/// {@endtemplate}
class LocalAIService {
  /// Base URL for the local inference server (e.g., llama.cpp HTTP server).
  static const String _localServerUrl = 'http://localhost:8080';

  /// Directory where model files are stored.
  String? _modelsDir;

  /// Currently loaded model in memory.
  LocalModel? _loadedModel;

  /// Whether a download is in progress.
  bool _downloading = false;

  /// Download progress (0.0 to 1.0).
  double _downloadProgress = 0.0;

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Cached model availability check.
  final Map<LocalModel, bool> _modelAvailability = {};

  // ── Singleton ───────────────────────────────────────────────────────

  static final LocalAIService _instance = LocalAIService._internal();
  factory LocalAIService() => _instance;
  LocalAIService._internal();

  // ── Initialization ──────────────────────────────────────────────────

  /// Initialize the service and determine the models directory.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _modelsDir = '${appDir.path}/models';
      await Directory(_modelsDir!).create(recursive: true);
      _initialized = true;
      debugPrint('[LocalAIService] Initialized. Models dir: $_modelsDir');
    } catch (e) {
      throw LocalAIException(
        message: 'Failed to initialize: $e',
        originalError: e,
      );
    }
  }

  /// Dispose and release any loaded model from memory.
  Future<void> dispose() async {
    _loadedModel = null;
    debugPrint('[LocalAIService] Disposed');
  }

  // ── Model Availability ──────────────────────────────────────────────

  /// Check if any local model is downloaded and ready to use.
  Future<bool> isModelAvailable() async {
    _ensureInitialized();
    for (final model in LocalModel.values) {
      if (await isSpecificModelAvailable(model)) return true;
    }
    return false;
  }

  /// Check if a specific model is available locally.
  Future<bool> isSpecificModelAvailable(LocalModel model) async {
    _ensureInitialized();
    if (_modelAvailability.containsKey(model)) return _modelAvailability[model]!;

    final modelFile = File('$_modelsDir/${model.modelId}.gguf');
    final available = await modelFile.exists() && await modelFile.length() > 1024 * 1024;
    _modelAvailability[model] = available;
    return available;
  }

  /// Get a list of all models and their download status.
  Future<List<Map<String, dynamic>>> getModelStatuses() async {
    final statuses = <Map<String, dynamic>>[];
    for (final model in LocalModel.values) {
      final available = await isSpecificModelAvailable(model);
      statuses.add({
        'model': model,
        'modelId': model.modelId,
        'displayName': model.displayName,
        'size': model.sizeString,
        'category': model.category,
        'isDownloaded': available,
        'isLoaded': _loadedModel == model,
      });
    }
    return statuses;
  }

  // ── Model Download ──────────────────────────────────────────────────

  /// Download a model file from the model repository.
  ///
  /// [modelName] must match one of the [LocalModel.modelId] values.
  /// [onProgress] is called with values from 0.0 to 1.0.
  /// [wifiOnly] when true prevents download on cellular networks.
  Future<void> downloadModel(
    String modelName, {
    void Function(double progress)? onProgress,
    bool wifiOnly = true,
  }) async {
    _ensureInitialized();

    final model = LocalModel.values.firstWhere(
      (m) => m.modelId == modelName,
      orElse: () => throw LocalAIException(message: 'Unknown model: $modelName'),
    );

    if (await isSpecificModelAvailable(model)) {
      debugPrint('[LocalAIService] Model ${model.displayName} already downloaded');
      return;
    }

    if (_downloading) {
      throw const LocalAIException(message: 'Another download is already in progress');
    }

    _downloading = true;
    _downloadProgress = 0.0;

    try {
      debugPrint('[LocalAIService] Downloading ${model.displayName} (${model.sizeString})...');

      final modelFile = File('$_modelsDir/${model.modelId}.gguf');
      final tempFile = File('${modelFile.path}.tmp');

      // Simulated download using HttpClient with progress tracking.
      // In production, replace with actual model download URL.
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
        'https://huggingface.co/TheBloke/${model.displayName}-GGUF/resolve/main/${model.modelId}.Q4_K_M.gguf',
      ));

      final response = await request.close();
      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      final sink = tempFile.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = receivedBytes / totalBytes;
          onProgress?.call(_downloadProgress);
        }
      }
      await sink.close();
      client.close();

      // Atomic rename once download completes.
      await tempFile.rename(modelFile.path);
      _modelAvailability[model] = true;
      _downloadProgress = 1.0;
      onProgress?.call(1.0);

      debugPrint('[LocalAIService] Downloaded ${model.displayName}');
    } catch (e) {
      // Clean up partial download.
      final tempFile = File('$_modelsDir/${model.modelId}.gguf.tmp');
      if (await tempFile.exists()) await tempFile.delete();
      throw LocalAIException(
        message: 'Failed to download ${model.displayName}: $e',
        model: model,
        originalError: e,
      );
    } finally {
      _downloading = false;
    }
  }

  /// Cancel an in-progress download.
  void cancelDownload() {
    if (_downloading) {
      _downloading = false;
      debugPrint('[LocalAIService] Download cancelled');
    }
  }

  /// Get the current download progress (0.0 to 1.0).
  double get downloadProgress => _downloadProgress;

  /// Whether a download is currently in progress.
  bool get isDownloading => _downloading;

  /// Delete a downloaded model to free disk space.
  Future<void> deleteModel(String modelName) async {
    _ensureInitialized();

    final model = LocalModel.values.firstWhere(
      (m) => m.modelId == modelName,
      orElse: () => throw LocalAIException(message: 'Unknown model: $modelName'),
    );

    final modelFile = File('$_modelsDir/${model.modelId}.gguf');
    if (await modelFile.exists()) {
      await modelFile.delete();
      _modelAvailability[model] = false;
      if (_loadedModel == model) _loadedModel = null;
      debugPrint('[LocalAIService] Deleted ${model.displayName}');
    }
  }

  /// Get the total disk space used by all downloaded models.
  Future<int> getTotalDiskUsage() async {
    _ensureInitialized();
    int total = 0;
    for (final model in LocalModel.values) {
      final file = File('$_modelsDir/${model.modelId}.gguf');
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  // ── Core AI Operations ──────────────────────────────────────────────

  /// Generate code completion given prefix and suffix context.
  ///
  /// [prefix] is the code before the cursor.
  /// [suffix] is the code after the cursor (optional).
  /// [language] hints the model for syntax awareness ('dart', 'python', etc.)
  ///
  /// Returns the generated completion string, or empty string on failure.
  Future<String> completeCode(
    String prefix,
    String suffix,
    String language,
  ) async {
    _ensureInitialized();

    if (!await isModelAvailable()) {
      throw const LocalAIException(
        message: 'No local model available. Download a model first.',
      );
    }

    final model = _selectBestModel('code');
    await _loadModel(model);

    try {
      // FIM (Fill-In-the-Middle) prompt format used by StarCoder/CodeLlama.
      final prompt = _buildFimPrompt(prefix, suffix, language);
      final result = await _inference(prompt, maxTokens: 128, temperature: 0.2);

      // Extract just the generated portion between prefix and suffix.
      return _extractCompletion(result, prefix, suffix);
    } catch (e) {
      debugPrint('[LocalAIService] completeCode error: $e');
      return '';
    }
  }

  /// Provide a simple explanation of what the given code does.
  ///
  /// Best suited for short snippets (< 50 lines). Falls back to
  /// cloud API for longer or more complex explanation requests.
  Future<String> explainCodeSimple(
    String code,
    String language,
  ) async {
    _ensureInitialized();

    if (!await isModelAvailable()) {
      throw const LocalAIException(
        message: 'No local model available. Download a model first.',
      );
    }

    final model = _selectBestModel('general');
    await _loadModel(model);

    try {
      final prompt = '''Explain this $language code concisely:
```$language
$code
```

Brief explanation:''';

      final result = await _inference(prompt, maxTokens: 256, temperature: 0.3);
      return result.trim();
    } catch (e) {
      debugPrint('[LocalAIService] explainCodeSimple error: $e');
      return 'Unable to explain: ${e.toString()}';
    }
  }

  /// Suggest fixes for a simple compilation/runtime error.
  ///
  /// [errorMessage] is the compiler or runtime error string.
  /// [codeContext] is the surrounding code where the error occurred.
  Future<String> suggestFix(
    String errorMessage,
    String codeContext,
    String language,
  ) async {
    _ensureInitialized();

    if (!await isModelAvailable()) return '';

    final model = _selectBestModel('code');
    await _loadModel(model);

    try {
      final prompt = '''Language: $language
Error: $errorMessage
Code:
```$language
$codeContext
```
Suggested fix:''';

      final result = await _inference(prompt, maxTokens: 200, temperature: 0.2);
      return result.trim();
    } catch (e) {
      debugPrint('[LocalAIService] suggestFix error: $e');
      return '';
    }
  }

  // ── Local vs Cloud Decision ─────────────────────────────────────────

  /// Determine whether the local model should be used for a given task.
  ///
  /// Returns `false` (use cloud) when:
  /// - The device is online AND the task is complex.
  /// - No local model is downloaded.
  /// - The input exceeds local model context limits.
  ///
  /// Returns `true` (use local) when:
  /// - The device is offline.
  /// - The task is simple (completion, short explanation).
  /// - User has enabled "prefer local" in settings.
  bool shouldUseLocal({
    required bool isOnline,
    String taskComplexity = 'simple',
    int inputLength = 0,
    bool preferLocal = false,
  }) {
    // Offline: must use local.
    if (!isOnline) return true;

    // User preference overrides.
    if (preferLocal) return true;

    // Complex tasks benefit from cloud models.
    final complexity = _parseComplexity(taskComplexity);
    if (complexity == TaskComplexity.complex) return false;

    // Large inputs exceed local context window.
    if (inputLength > 4000) return false;

    // No model available.
    if (!isModelAvailableSync()) return false;

    // Moderate tasks: use local if online is slow/expensive.
    if (complexity == TaskComplexity.moderate) {
      // Default to local for code completion, cloud for explanations.
      return taskComplexity == 'completion';
    }

    return true;
  }

  /// Non-blocking check for model availability (uses cached state).
  bool isModelAvailableSync() {
    return _modelAvailability.values.any((available) => available);
  }

  /// Get the currently loaded model.
  LocalModel? get loadedModel => _loadedModel;

  // ── Private ─────────────────────────────────────────────────────────

  LocalModel _selectBestModel(String category) {
    // Prefer a loaded model to avoid switch overhead.
    if (_loadedModel != null) return _loadedModel!;

    // Choose the smallest available model for the category.
    final candidates = LocalModel.values.where((m) => m.category == category).toList();
    candidates.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));

    for (final model in candidates) {
      if (_modelAvailability[model] == true) return model;
    }

    // Fallback to any available model.
    for (final model in LocalModel.values) {
      if (_modelAvailability[model] == true) return model;
    }

    // Ultimate fallback: smallest model (will fail gracefully if not downloaded).
    return LocalModel.starCoder1B;
  }

  Future<void> _loadModel(LocalModel model) async {
    if (_loadedModel == model) return;

    debugPrint('[LocalAIService] Loading model: ${model.displayName}');
    _loadedModel = model;

    // In production, this would start the llama.cpp / mlc-llm server
    // with the specified model weights.
    //
    // Example:
    // final process = await Process.start(
    //   'llama-server',
    //   ['-m', '$_modelsDir/${model.modelId}.gguf', '--port', '8080'],
    // );
    // await _waitForServer();
  }

  Future<String> _inference(
    String prompt, {
    required int maxTokens,
    double temperature = 0.2,
  }) async {
    // Production implementation calls the local inference server.
    //
    // Example using the llama.cpp HTTP API:
    // final response = await _api.post(
    //   '$_localServerUrl/completion',
    //   data: {
    //     'prompt': prompt,
    //     'n_predict': maxTokens,
    //     'temperature': temperature,
    //     'stop': ['<|endoftext|>', '<|fim_prefix|>', '<|fim_suffix|>', '<|fim_middle|>'],
    //   },
    // );
    // return response.data['content'] as String;

    // Placeholder: return a mock response for development.
    await Future.delayed(const Duration(milliseconds: 200));

    // Generate a context-aware mock response based on prompt type.
    if (prompt.contains('Explain this')) {
      return 'This code defines a function that processes input data and returns a transformed result. It handles edge cases like null values and empty collections.';
    }
    if (prompt.contains('Suggested fix')) {
      return 'Check for null before accessing the property. Add a null-check or use the null-aware operator `?.`.';
    }

    // Code completion mock.
    return '\n  print("Hello, World!");\n}';
  }

  String _buildFimPrompt(String prefix, String suffix, String language) {
    // StarCoder / CodeLlama FIM format.
    return '<|fim_prefix|$language>\n$prefix<|fim_suffix|>$suffix<|fim_middle|>';
  }

  String _extractCompletion(String raw, String prefix, String suffix) {
    var result = raw;

    // Remove the prompt echo if present.
    if (result.contains('<|fim_middle|>')) {
      result = result.split('<|fim_middle|>').last;
    }
    if (result.contains('<|fim_prefix|>')) {
      result = result.split('<|fim_prefix|>').last;
      if (result.contains('\n')) {
        result = result.substring(result.indexOf('\n'));
      }
    }

    // Trim leading newline.
    result = result.trimLeft();

    // Stop at common stop tokens.
    for (final stop in ['<|endoftext|>', '<|file_separator|>', '<|eos|>']) {
      if (result.contains(stop)) {
        result = result.substring(0, result.indexOf(stop));
      }
    }

    return result;
  }

  TaskComplexity _parseComplexity(String value) {
    switch (value.toLowerCase()) {
      case 'simple':
      case 'completion':
        return TaskComplexity.simple;
      case 'moderate':
      case 'explanation':
        return TaskComplexity.moderate;
      case 'complex':
      case 'generation':
      case 'refactoring':
        return TaskComplexity.complex;
      default:
        return TaskComplexity.moderate;
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('LocalAIService not initialized. Call initialize() first.');
    }
  }
}
