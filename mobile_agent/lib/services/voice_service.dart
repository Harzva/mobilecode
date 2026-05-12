// lib/services/voice_service.dart
//
// Voice Input System (语音->代码)
// Converts speech to structured code generation prompts.
// Uses the speech_to_text package with streaming partial results
// and smart intent detection for code-related voice commands.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums & Models
// ─────────────────────────────────────────────────────────────────────────────

/// Lifecycle states of the voice input system.
enum VoiceState {
  /// Initial / ready state.
  idle,

  /// Actively listening to microphone input.
  listening,

  /// Processing the final transcript (intent detection / prompt building).
  processing,

  /// Transcript ready and code prompt generated.
  done,

  /// An error occurred (permission denied, no speech, network, etc.).
  error,
}

/// Types of code-related intents that can be detected from voice input.
enum IntentType {
  /// Create a new file (e.g. "创建一个登录页面").
  createFile,

  /// Modify an existing file (e.g. "给登录页面添加密码验证").
  modifyFile,

  /// Delete a file (e.g. "删除那个测试文件").
  deleteFile,

  /// Search for code patterns (e.g. "查找所有异步函数").
  searchCode,

  /// Explain existing code (e.g. "解释这段代码是什么意思").
  explainCode,

  /// Generate a standalone code snippet (e.g. "写一个快速排序算法").
  generateSnippet,

  /// Run a command (e.g. "运行测试" / "构建项目").
  runCommand,

  /// General chat / non-code query.
  unknown,
}

/// Parsed intent extracted from a voice transcript.
class CodeIntent {
  /// The detected intent type.
  final IntentType type;

  /// Target file name, class name, or search pattern.
  final String target;

  /// Full voice transcript (raw user query).
  final String description;

  /// Detected programming language (nullable).
  final String? language;

  /// Confidence score 0.0 - 1.0.
  final double confidence;

  /// Optional extracted code snippet from transcript.
  final String? codeSnippet;

  const CodeIntent({
    required this.type,
    required this.target,
    required this.description,
    this.language,
    required this.confidence,
    this.codeSnippet,
  });

  /// Whether this intent is code-related (not unknown).
  bool get isCodeRelated => type != IntentType.unknown;

  @override
  String toString() {
    return 'CodeIntent(type: $type, target: $target, '
        'language: $language, confidence: ${confidence.toStringAsFixed(2)})';
  }
}

/// Audio level data point for waveform visualization.
class AudioLevel {
  /// Normalized amplitude 0.0 - 1.0.
  final double amplitude;

  /// Timestamp when this sample was captured.
  final DateTime timestamp;

  const AudioLevel({required this.amplitude, required this.timestamp});
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice Service
// ─────────────────────────────────────────────────────────────────────────────

/// Voice input service that converts speech to code generation prompts.
///
/// Uses the `speech_to_text` package with Chinese (zh_CN) locale support.
/// Provides streaming partial results, real-time audio level simulation,
/// smart code intent detection, and structured prompt generation for LLM.
///
/// ```dart
/// final voice = VoiceService();
/// await voice.initialize();
/// voice.onTranscriptUpdate.listen((text) => print(text));
/// await voice.startListening();
/// final transcript = await voice.stopListening();
/// final intent = voice.analyzeIntent(transcript);
/// final prompt = voice.buildCodePrompt(intent);
/// ```
class VoiceService {
  // ── Speech Engine ────────────────────────────────────────────────────
  final SpeechToText _speech = SpeechToText();

  // ── State ────────────────────────────────────────────────────────────
  VoiceState _state = VoiceState.idle;
  String _transcript = '';
  String _lastError = '';

  // ── Stream Controllers ───────────────────────────────────────────────
  StreamController<VoiceState>? _stateController;
  StreamController<String>? _transcriptController;
  StreamController<AudioLevel>? _audioLevelController;
  Timer? _audioLevelTimer;

  // ── Configuration ────────────────────────────────────────────────────

  /// Primary locale - Chinese Mandarin for code voice input.
  static const String defaultLocale = 'zh_CN';

  /// Fallback locale if zh_CN is unavailable.
  static const String fallbackLocale = 'en_US';

  /// Whether to emit partial (interim) recognition results.
  static const bool usePartialResults = true;

  /// Maximum listening duration per session in milliseconds.
  static const int maxListenDurationMs = 30000;

  /// Pause duration that triggers end-of-speech.
  static const int listenModePauseMs = 3000;

  // ── Intent Detection Keywords ────────────────────────────────────────

  /// Chinese keywords mapped to intent types.
  static const Map<IntentType, List<String>> _intentKeywords = {
    IntentType.createFile: [
      '创建', '新建', '生成', '写一个', '新建一个', '创建一个新的',
      '写一个', '写个', '给我写一个', '帮我写一个', '新建文件',
      'create', 'generate', 'write a', 'new file',
    ],
    IntentType.modifyFile: [
      '修改', '更新', '编辑', '更改', '改一下', '调整', '优化一下',
      '添加', '加上', '插入', '补充',
      'modify', 'update', 'edit', 'change', 'add to', 'refactor',
    ],
    IntentType.deleteFile: [
      '删除', '移除', '删掉', '去掉',
      'delete', 'remove',
    ],
    IntentType.searchCode: [
      '查找', '搜索', '找出', '定位', '在哪里',
      'search', 'find', 'locate',
    ],
    IntentType.explainCode: [
      '解释', '说明', '讲解', '什么意思', '什么作用', '有什么用',
      'explain', 'what does', 'how does',
    ],
    IntentType.generateSnippet: [
      '代码片段', '函数', '方法', '算法', '实现一个', '写个函数',
      'snippet', 'function', 'algorithm', 'implement',
    ],
    IntentType.runCommand: [
      '运行', '执行', '构建', '测试', '编译', 'build', '跑一下',
      'run', 'execute', 'build', 'test', 'compile',
    ],
  };

  /// Programming language keywords for auto-detection.
  static const Map<String, List<String>> _languageKeywords = {
    'dart': ['dart', 'flutter', 'widget', 'stateless', 'stateful'],
    'javascript': ['javascript', 'js', 'node', 'react', 'vue'],
    'typescript': ['typescript', 'ts', 'angular', 'nestjs'],
    'python': ['python', 'py', 'django', 'flask', 'pandas'],
    'go': ['go', 'golang', 'goroutine'],
    'rust': ['rust', 'cargo', 'rustlang'],
    'java': ['java', 'spring', 'android'],
    'kotlin': ['kotlin', 'kt', 'android'],
    'swift': ['swift', 'ios', 'swiftui'],
    'php': ['php', 'laravel', 'wordpress'],
    'ruby': ['ruby', 'rails', 'rb'],
    'c': ['c语言', 'c '],
    'cpp': ['c++', 'cpp', 'cplusplus'],
    'csharp': ['c#', 'csharp', '.net'],
    'html': ['html', '网页', '页面'],
    'css': ['css', '样式', 'style'],
    'sql': ['sql', '数据库', 'database'],
    'shell': ['shell', 'bash', '脚本', 'script'],
    'json': ['json', '配置'],
    'yaml': ['yaml', 'yml'],
    'markdown': ['markdown', 'md', '文档'],
  };

  /// File extension pattern for extracting target filenames.
  static final RegExp _fileNamePattern = RegExp(
    r'[\w\-]+\.(dart|js|ts|py|go|rs|java|kt|swift|php|rb|'
    r'cpp|c|cs|html|css|json|yaml|yml|md|sql|sh)',
    caseSensitive: false,
  );

  // ── Initialization ───────────────────────────────────────────────────

  /// Initialize the speech recognition engine.
  ///
  /// Requests microphone permission and sets up the speech engine.
  /// Returns `true` if initialization succeeded and speech is available.
  Future<bool> initialize() async {
    try {
      _stateController ??= StreamController<VoiceState>.broadcast();
      _transcriptController ??= StreamController<String>.broadcast();
      _audioLevelController ??= StreamController<AudioLevel>.broadcast();

      final available = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
        debugLogging: kDebugMode,
      );

      if (!available) {
        _lastError = 'Speech recognition not available on this device';
        _setState(VoiceState.error);
      }

      return available;
    } catch (e) {
      _lastError = 'Failed to initialize speech: $e';
      _setState(VoiceState.error);
      debugPrint('[VoiceService] $_lastError');
      return false;
    }
  }

  /// Check if speech recognition is currently available.
  bool get isAvailable => _speech.isAvailable;

  /// Check if the engine is currently listening.
  bool get isListening => _speech.isListening;

  /// Current transcript (accumulated from partial results).
  String get transcript => _transcript;

  /// Last error message.
  String get lastError => _lastError;

  /// Current voice state.
  VoiceState get currentState => _state;

  // ── Start Listening ──────────────────────────────────────────────────

  /// Start listening for voice input with streaming partial results.
  ///
  /// Emits state changes via [onStateChange] and transcript updates
  /// via [onTranscriptUpdate]. Also emits simulated audio levels
  /// via [onAudioLevel] for waveform visualization.
  ///
  /// Throws [StateError] if already listening.
  Future<void> startListening() async {
    if (_speech.isListening) {
      throw StateError('Already listening. Call stopListening() first.');
    }

    _transcript = '';
    _lastError = '';
    _setState(VoiceState.listening);

    // Start simulated audio level stream for waveform.
    _startAudioLevelSimulation();

    // Determine available locale.
    final localeId = await _resolveLocale();

    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        localeId: localeId,
        partialResults: usePartialResults,
        listenMode: ListenMode.confirmation,
        pauseFor: const Duration(milliseconds: listenModePauseMs),
        listenFor: const Duration(milliseconds: maxListenDurationMs),
        cancelOnError: false,
        onSoundLevelChange: _onSoundLevelChange,
      );
    } catch (e) {
      _lastError = 'Failed to start listening: $e';
      _setState(VoiceState.error);
      _stopAudioLevelSimulation();
      debugPrint('[VoiceService] $_lastError');
    }
  }

  // ── Stop Listening ───────────────────────────────────────────────────

  /// Stop listening and return the final transcript.
  ///
  /// Returns the accumulated transcript. If no speech was recognized,
  /// returns an empty string.
  ///
  /// Emits [VoiceState.processing] briefly, then [VoiceState.done].
  Future<String> stopListening() async {
    if (!_speech.isListening) return _transcript;

    _stopAudioLevelSimulation();
    await _speech.stop();

    _setState(VoiceState.processing);

    // Brief processing delay for intent analysis.
    await Future.delayed(const Duration(milliseconds: 200));

    if (_transcript.isNotEmpty) {
      _setState(VoiceState.done);
    } else {
      _setState(VoiceState.idle);
    }

    return _transcript;
  }

  // ── Cancel ───────────────────────────────────────────────────────────

  /// Cancel listening without returning results.
  ///
  /// Discards any partial transcript and resets to idle state.
  Future<void> cancel() async {
    _stopAudioLevelSimulation();
    if (_speech.isListening) {
      await _speech.cancel();
    }
    _transcript = '';
    _setState(VoiceState.idle);
  }

  // ── Speech Callbacks ─────────────────────────────────────────────────

  /// Handle speech recognition result (partial or final).
  void _onSpeechResult(SpeechRecognitionResult result) {
    _transcript = result.recognizedWords;
    _transcriptController?.add(_transcript);

    if (result.finalResult) {
      // Final result received - auto-stop.
      _stopAudioLevelSimulation();
      _setState(VoiceState.processing);

      Future.delayed(const Duration(milliseconds: 300), () {
        if (_transcript.isNotEmpty) {
          _setState(VoiceState.done);
        } else {
          _setState(VoiceState.idle);
        }
      });
    }
  }

  /// Handle speech engine status changes.
  void _onSpeechStatus(String status) {
    debugPrint('[VoiceService] Speech status: $status');

    switch (status) {
      case 'listening':
        _setState(VoiceState.listening);
      case 'notListening':
        _stopAudioLevelSimulation();
      case 'done':
        // Final result already handled in _onSpeechResult.
        break;
      default:
        break;
    }
  }

  /// Handle speech recognition errors.
  void _onSpeechError(SpeechRecognitionError error) {
    debugPrint('[VoiceService] Speech error: ${error.errorMsg} '
        '(permanent: ${error.permanent})');

    _lastError = error.errorMsg;

    if (error.permanent) {
      _stopAudioLevelSimulation();
      _setState(VoiceState.error);
    }
  }

  /// Handle sound level changes from the speech engine (0.0 - 1.0).
  void _onSoundLevelChange(double level) {
    // speech_to_text reports level in dB (typically -2.12 = max).
    // Normalize to 0.0 - 1.0 range.
    final normalized = _normalizeSoundLevel(level);
    _audioLevelController?.add(
      AudioLevel(
        amplitude: normalized,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ── Audio Level Simulation ──────────────────────────────────────────

  /// Fallback: simulate audio levels when platform doesn't provide them.
  void _startAudioLevelSimulation() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (timer) {
        // Generate a natural-looking waveform pattern.
        final time = timer.tick * 0.15;
        final base = 0.15 + 0.1 * math.sin(time * 2.3);
        final variation = 0.15 * math.sin(time * 7.1) * math.cos(time * 3.7);
        final noise = 0.05 * (math.Random().nextDouble() - 0.5);
        final amplitude = (base + variation + noise).clamp(0.05, 0.8);

        _audioLevelController?.add(
          AudioLevel(
            amplitude: amplitude,
            timestamp: DateTime.now(),
          ),
        );
      },
    );
  }

  void _stopAudioLevelSimulation() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
  }

  /// Normalize sound level from speech_to_text to 0.0 - 1.0.
  double _normalizeSoundLevel(double level) {
    // speech_to_text typically returns -2.12 at max, lower values for silence.
    const minDb = -10.0;
    const maxDb = -2.0;
    if (level <= minDb) return 0.05;
    if (level >= maxDb) return 1.0;
    return ((level - minDb) / (maxDb - minDb)).clamp(0.05, 1.0);
  }

  // ── Locale Resolution ────────────────────────────────────────────────

  /// Resolve the best available locale for speech recognition.
  Future<String> _resolveLocale() async {
    try {
      final locales = await _speech.locales();
      final hasChinese = locales.any(
        (l) => l.localeId.startsWith('zh') || l.localeId == defaultLocale,
      );
      return hasChinese ? defaultLocale : fallbackLocale;
    } catch (_) {
      return fallbackLocale;
    }
  }

  // ── Smart Code Intent Detection ──────────────────────────────────────

  /// Analyze a transcript to detect code-related intent.
  ///
  /// Uses keyword matching for Chinese and English commands to determine
  /// the user's intent (create file, modify, delete, search, etc.).
  /// Also extracts target filenames and programming languages.
  ///
  /// Examples:
  /// - "创建一个登录页面" -> createFile intent, target: "login_page"
  /// - "给main.dart添加注释" -> modifyFile intent, target: "main.dart"
  /// - "写一个快速排序" -> generateSnippet intent
  CodeIntent analyzeIntent(String transcript) {
    if (transcript.trim().isEmpty) {
      return const CodeIntent(
        type: IntentType.unknown,
        target: '',
        description: '',
        confidence: 0.0,
      );
    }

    final lowerTranscript = transcript.toLowerCase();

    // Step 1: Detect intent type via keyword matching.
    IntentType detectedType = IntentType.unknown;
    double highestScore = 0.0;

    for (final entry in _intentKeywords.entries) {
      final score = _calculateKeywordScore(lowerTranscript, entry.value);
      if (score > highestScore) {
        highestScore = score;
        detectedType = entry.key;
      }
    }

    // Step 2: Extract target filename or class name.
    final target = _extractTarget(lowerTranscript, transcript);

    // Step 3: Detect programming language.
    final language = _detectLanguage(lowerTranscript);

    // Step 4: Calculate overall confidence.
    final confidence = _calculateConfidence(
      keywordScore: highestScore,
      hasTarget: target.isNotEmpty,
      hasLanguage: language != null,
      transcriptLength: transcript.length,
    );

    return CodeIntent(
      type: detectedType,
      target: target,
      description: transcript,
      language: language,
      confidence: confidence,
    );
  }

  /// Calculate how many keywords match the transcript.
  double _calculateKeywordScore(String transcript, List<String> keywords) {
    int matches = 0;
    for (final kw in keywords) {
      if (transcript.contains(kw.toLowerCase())) {
        matches++;
      }
    }
    // Score based on keyword density and match count.
    if (matches == 0) return 0.0;
    return (matches / math.sqrt(keywords.length)).clamp(0.0, 1.0);
  }

  /// Extract target filename, class name, or pattern from transcript.
  String _extractTarget(String lowerTranscript, String originalTranscript) {
    // Try to find explicit filename references.
    final fileMatch = _fileNamePattern.firstMatch(originalTranscript);
    if (fileMatch != null) {
      return fileMatch.group(0)!;
    }

    // Try to extract descriptive names (e.g. "登录页面" -> "login_page").
    final namePatterns = [
      RegExp(r'(?:叫做?|名为?|叫|名字是?)\s*["\']?([\w\u4e00-\u9fff]+)["\']?'),
      RegExp(r'(?:文件|页面|类|组件)\s*["\']?([\w\u4e00-\u9fff]+)["\']?'),
    ];

    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(originalTranscript);
      if (match != null) {
        return _transliterateToFileName(match.group(1) ?? '');
      }
    }

    // Fallback: extract the noun phrase after the action verb.
    final actionPattern = RegExp(
      r'(?:创建|新建|生成|写一个|修改|更新|删除|查找|解释|写个|实现)'
      r'\s*["\']?([\w\u4e00-\u9fff\s]+?)["\']?'
      r'(?:\s*(?:文件|页面|类|组件|函数|方法|\.|,|，|。|$))',
    );
    final actionMatch = actionPattern.firstMatch(originalTranscript);
    if (actionMatch != null) {
      return _transliterateToFileName(actionMatch.group(1)?.trim() ?? '');
    }

    // If still no target, use the first few words as a hint.
    final words = originalTranscript.split(RegExp(r'\s+|，|,'));
    if (words.length >= 2) {
      return _transliterateToFileName(words.sublist(1).join('_'));
    }

    return '';
  }

  /// Convert Chinese description to snake_case filename suggestion.
  String _transliterateToFileName(String text) {
    if (text.isEmpty) return '';

    // Common Chinese -> English mappings for code naming.
    final translations = <String, String>{
      '登录': 'login',
      '注册': 'register',
      '首页': 'home',
      '主页': 'home',
      '用户': 'user',
      '设置': 'settings',
      '配置': 'config',
      '搜索': 'search',
      '导航': 'navigation',
      '页面': 'page',
      '组件': 'widget',
      '按钮': 'button',
      '表单': 'form',
      '列表': 'list',
      '详情': 'detail',
      '网络': 'network',
      '数据': 'data',
      '缓存': 'cache',
      '工具': 'utils',
      '服务': 'service',
      '模型': 'model',
      '控制器': 'controller',
      '提供器': 'provider',
      '主题': 'theme',
      '国际化': 'i18n',
      '状态': 'state',
      '路由': 'router',
      '中间件': 'middleware',
    };

    var result = text.toLowerCase().trim();

    // Apply translations.
    for (final entry in translations.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // Clean up: replace spaces and special chars with underscores.
    result = result
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAll(RegExp(r'[^\w_]'), '');

    // Remove consecutive underscores.
    result = result.replaceAll(RegExp(r'_+'), '_').trim();

    return result;
  }

  /// Detect programming language from transcript keywords.
  String? _detectLanguage(String lowerTranscript) {
    for (final entry in _languageKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerTranscript.contains(keyword.toLowerCase())) {
          return entry.key;
        }
      }
    }
    // Default to dart for Flutter projects.
    if (lowerTranscript.contains('flutter') ||
        lowerTranscript.contains('widget')) {
      return 'dart';
    }
    return null;
  }

  /// Calculate overall intent detection confidence.
  double _calculateConfidence({
    required double keywordScore,
    required bool hasTarget,
    required bool hasLanguage,
    required int transcriptLength,
  }) {
    double confidence = keywordScore * 0.5;
    if (hasTarget) confidence += 0.25;
    if (hasLanguage) confidence += 0.15;
    // Longer transcripts have more context = slightly higher confidence.
    if (transcriptLength > 10) confidence += 0.1;
    return confidence.clamp(0.0, 1.0);
  }

  // ── Transcript -> Code Prompt ────────────────────────────────────────

  /// Build an optimized code generation prompt from a detected intent.
  ///
  /// Creates a structured prompt suitable for the LLM service.
  /// The prompt includes context about the intent type, target,
  /// language, and any code snippets extracted from the transcript.
  String buildCodePrompt(CodeIntent intent) {
    final buffer = StringBuffer();

    switch (intent.type) {
      case IntentType.createFile:
        buffer.writeln('Create a new file: `${intent.target}`');
        if (intent.language != null) {
          buffer.writeln('Language: ${intent.language}');
        }
        buffer.writeln();
        buffer.writeln('Requirements:');
        buffer.writeln(intent.description);
        buffer.writeln();
        buffer.writeln('Please provide the complete file content. '
            'Include proper imports, documentation comments, '
            'and follow best practices.');

      case IntentType.modifyFile:
        buffer.writeln('Modify file: `${intent.target}`');
        if (intent.language != null) {
          buffer.writeln('Language: ${intent.language}');
        }
        buffer.writeln();
        buffer.writeln('Modification request:');
        buffer.writeln(intent.description);
        buffer.writeln();
        buffer.writeln('Please provide the modified code. Show the complete '
            'relevant sections with clear comments marking what changed.');

      case IntentType.deleteFile:
        buffer.writeln('Delete/remove: `${intent.target}`');
        buffer.writeln();
        buffer.writeln('User request: ${intent.description}');
        buffer.writeln();
        buffer.writeln('Confirm the deletion and suggest any cleanup '
            'needed (imports, references, etc.).');

      case IntentType.searchCode:
        buffer.writeln('Search request: ${intent.description}');
        buffer.writeln();
        buffer.writeln('Identify all locations matching the search criteria. '
            'Show file paths, line numbers, and relevant code snippets.');

      case IntentType.explainCode:
        buffer.writeln('Explain the following code:');
        buffer.writeln();
        if (intent.codeSnippet != null && intent.codeSnippet!.isNotEmpty) {
          buffer.writeln('```${intent.language ?? 'code'}');
          buffer.writeln(intent.codeSnippet);
          buffer.writeln('```');
        } else {
          buffer.writeln(intent.description);
        }
        buffer.writeln();
        buffer.writeln('Provide a clear explanation covering:');
        buffer.writeln('1. What the code does at a high level');
        buffer.writeln('2. Key functions, classes, or patterns');
        buffer.writeln('3. Any important logic or edge cases');

      case IntentType.generateSnippet:
        buffer.writeln('Generate a code snippet:');
        buffer.writeln();
        buffer.writeln('Request: ${intent.description}');
        if (intent.language != null) {
          buffer.writeln('Language: ${intent.language}');
        }
        buffer.writeln();
        buffer.writeln('Provide a clean, well-documented implementation. '
            'Include usage examples if helpful.');

      case IntentType.runCommand:
        buffer.writeln('Execute command: ${intent.description}');
        buffer.writeln();
        buffer.writeln('Provide the exact command(s) to run and explain '
            'what each does. Include any prerequisites.');

      case IntentType.unknown:
        buffer.writeln(intent.description);
    }

    return buffer.toString().trim();
  }

  // ── Streams ──────────────────────────────────────────────────────────

  /// Stream of voice state changes.
  Stream<VoiceState> get onStateChange {
    _stateController ??= StreamController<VoiceState>.broadcast();
    return _stateController!.stream;
  }

  /// Stream of transcript updates (partial and final).
  Stream<String> get onTranscriptUpdate {
    _transcriptController ??= StreamController<String>.broadcast();
    return _transcriptController!.stream;
  }

  /// Stream of audio level data for waveform visualization.
  Stream<AudioLevel> get onAudioLevel {
    _audioLevelController ??= StreamController<AudioLevel>.broadcast();
    return _audioLevelController!.stream;
  }

  // ── Internal ─────────────────────────────────────────────────────────

  void _setState(VoiceState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController?.add(newState);
      debugPrint('[VoiceService] State: $newState');
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────

  /// Dispose all resources and stream controllers.
  void dispose() {
    _stopAudioLevelSimulation();
    _speech.cancel();

    _stateController?.close();
    _transcriptController?.close();
    _audioLevelController?.close();

    _stateController = null;
    _transcriptController = null;
    _audioLevelController = null;
  }
}
