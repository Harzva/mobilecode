// lib/services/logger_service.dart
// Production Logging Service for Mobile Agent

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/error_handler.dart';

// ---------------------------------------------------------------------------
// LogEntry - Individual Log Record
// ---------------------------------------------------------------------------

/// A single log entry with full structured context.
///
/// Each entry captures:
/// - [timestamp]: When the event occurred
/// - [level]: Severity of the event
/// - [tag]: Logical component that emitted the log (e.g., "API", "LLM")
/// - [message]: Human-readable description
/// - [error]: Optional error object or string
/// - [stackTrace]: Optional stack trace for errors
/// - [context]: Optional key-value pairs for structured data
/// - [operationDuration]: Optional timing information
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;
  final Duration? operationDuration;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    this.context,
    this.operationDuration,
  });

  /// Convert to a structured JSON map.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'level': level.name.toUpperCase(),
      'tag': tag,
      'message': message,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      if (context != null) 'context': context,
      if (operationDuration != null)
        'durationMs': operationDuration!.inMilliseconds,
    };
  }

  /// Create a [LogEntry] from a JSON map (for reading persisted logs).
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: LogLevel.values.byName((json['level'] as String).toLowerCase()),
      tag: json['tag'] as String,
      message: json['message'] as String,
      error: json['error'],
      stackTrace: json['stackTrace'] != null
          ? StackTrace.fromString(json['stackTrace'] as String)
          : null,
      context: json['context'] as Map<String, dynamic>?,
      operationDuration: json['durationMs'] != null
          ? Duration(milliseconds: json['durationMs'] as int)
          : null,
    );
  }

  /// Formatted string for console output.
  String get formatted {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:''
        '${timestamp.minute.toString().padLeft(2, '0')}:''
        '${timestamp.second.toString().padLeft(2, '0')}.'''
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    final levelStr = level.name.toUpperCase().padLeft(7);
    final tagStr = tag.padRight(12);
    var line = '\$time \$levelStr \$tagStr \$message';
    if (error != null) {
      line += ' | ERROR: \${error.toString().replaceAll(RegExp(r'\s+'), ' ')}';
    }
    if (operationDuration != null) {
      line += ' (\${operationDuration!.inMilliseconds}ms)';
    }
    return line;
  }

  @override
  String toString() => formatted;
}

// ---------------------------------------------------------------------------
// LoggerService - Production Logging
// ---------------------------------------------------------------------------

/// Production-grade logging service with structured output, file rotation,
/// in-memory buffering, and performance tracking.
///
/// ## Features
/// - Six log levels from verbose to fatal
/// - Structured JSON logs with timestamps, tags, and context
/// - File-based rotating log storage (7-day retention)
/// - In-memory ring buffer (last 1000 entries) for quick access
/// - Log export as JSON or plain text
/// - Operation timing for performance tracking
/// - Thread-safe async writes
///
/// ## Usage
///
/// ```dart
/// final logger = LoggerService();
/// await logger.init();
///
/// logger.i('API', 'Request completed');
/// logger.e('LLM', 'Stream failed', error, stackTrace);
/// ```
class LoggerService {
  // -- Configuration Constants --

  static const int _maxFileSize = 5 * 1024 * 1024; // 5 MB per log file
  static const int _maxFiles = 7; // Keep 7 days of logs
  static const int _memoryBufferSize = 1000; // In-memory ring buffer
  static const String _logDirName = 'logs';
  static const String _logFileName = 'app_log';

  // -- State --

  LogLevel _minLevel = kDebugMode ? LogLevel.verbose : LogLevel.info;

  /// The in-memory ring buffer of recent log entries.
  final List<LogEntry> _memoryBuffer = [];

  /// Active file sink for persistent logging.
  IOSink? _fileSink;

  /// Whether the logger has been initialized.
  bool _initialized = false;

  /// Whether the logger has been disposed.
  bool _disposed = false;

  /// Internal queue to serialize async writes.
  final _writeQueue = <_WriteTask>[];

  /// Timer for flushing queued writes.
  Timer? _flushTimer;

  /// Active operation timers for performance tracking.
  final Map<String, Stopwatch> _activeTimers = {};

  /// Get/set the minimum log level. Messages below this level are ignored.
  LogLevel get minLevel => _minLevel;

  set minLevel(LogLevel value) {
    _minLevel = value;
    i('Logger', 'Min log level set to \${value.name}');
  }

  /// Whether the logger is initialized and ready.
  bool get isInitialized => _initialized;

  // -- Initialization --

  /// Initialize the logger service.
  ///
  /// Sets up the log directory, opens the current log file, and
  /// starts the flush timer. Must be called before any logging.
  Future<void> init() async {
    if (_initialized) return;

    try {
      final logDir = await _getLogDirectory();
      await logDir.create(recursive: true);

      // Rotate files if needed.
      await _rotateFilesIfNeeded(logDir);

      // Open the current log file in append mode.
      final logFile = File('${logDir.path}/\$_logFileName.0.log');
      _fileSink = logFile.openWrite(mode: FileMode.append);

      // Start flush timer (every 5 seconds).
      _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flushQueue());

      _initialized = true;
      i('Logger', 'LoggerService initialized. Log dir: \${logDir.path}');
    } catch (e, st) {
      // Fallback: log to console only.
      _initialized = true; // Allow console logging.
      _consolePrint('Logger init failed: \$e');
      if (kDebugMode) _consolePrint(st.toString());
    }
  }

  /// Dispose of resources and close file handles.
  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    await _flushQueue();
    await _fileSink?.close();
    _fileSink = null;
    _initialized = false;
  }

  // -- Core Logging Methods --

  /// Log a verbose message (debug builds only, extremely detailed).
  void v(String tag, String message, {Map<String, dynamic>? context}) {
    _log(LogLevel.verbose, tag, message, null, null, context);
  }

  /// Log a debug message (development diagnostics).
  void d(String tag, String message, {Map<String, dynamic>? context}) {
    _log(LogLevel.debug, tag, message, null, null, context);
  }

  /// Log an informational message (normal operation).
  void i(String tag, String message, {Map<String, dynamic>? context}) {
    _log(LogLevel.info, tag, message, null, null, context);
  }

  /// Log a warning (recoverable issue, degraded functionality).
  void w(String tag, String message, [dynamic error, StackTrace? stackTrace, Map<String, dynamic>? context]) {
    _log(LogLevel.warning, tag, message, error, stackTrace, context);
  }

  /// Log an error (operation failure requiring attention).
  void e(String tag, String message, dynamic error, StackTrace stackTrace, {Map<String, dynamic>? context}) {
    _log(LogLevel.error, tag, message, error, stackTrace, context);
  }

  /// Log a fatal error (crash-level, unrecoverable).
  void f(String tag, String message, dynamic error, StackTrace stackTrace, {Map<String, dynamic>? context}) {
    _log(LogLevel.fatal, tag, message, error, stackTrace, context);
  }

  // -- Performance Tracking --

  /// Start a performance timer for an operation.
  ///
  /// ```dart
  /// final timer = logger.startTimer('apiRequest');
  /// final result = await api.fetch();
  /// logger.endTimer('apiRequest', timer);
  /// ```
  Stopwatch startTimer(String operation) {
    final sw = Stopwatch()..start();
    _activeTimers[operation] = sw;
    d('Perf', 'Timer started: \$operation');
    return sw;
  }

  /// End a performance timer and log the duration.
  void endTimer(String operation, Stopwatch timer) {
    timer.stop();
    _activeTimers.remove(operation);
    i('Perf', 'Timer ended: \$operation', context: {
      'durationMs': timer.elapsedMilliseconds,
      'operation': operation,
    });
  }

  /// End a timer with the given result context.
  void endTimerWithContext(
    String operation,
    Stopwatch timer, {
    Map<String, dynamic>? context,
  }) {
    timer.stop();
    _activeTimers.remove(operation);
    final mergedContext = <String, dynamic>{
      'durationMs': timer.elapsedMilliseconds,
      'operation': operation,
      if (context != null) ...context,
    };
    i('Perf', 'Timer ended: \$operation', context: mergedContext);
  }

  // -- Log Query --

  /// Get the most recent [count] log entries from the in-memory buffer.
  ///
  /// Optionally filter to a minimum log level.
  List<LogEntry> getRecentLogs({int count = 100, LogLevel? minLevel}) {
    var logs = List<LogEntry>.from(_memoryBuffer);
    if (minLevel != null) {
      logs = logs.where((e) => e.level.index >= minLevel.index).toList();
    }
    if (logs.length > count) {
      logs = logs.sublist(logs.length - count);
    }
    return logs;
  }

  /// Get log entries for a specific date from file storage.
  Future<List<LogEntry>> getLogsForDate(DateTime date) async {
    final entries = <LogEntry>[];
    final logDir = await _getLogDirectory();

    // Try all rotated files for this date.
    for (var i = 0; i < _maxFiles; i++) {
      final file = File('${logDir.path}/\$_logFileName.\$i.log');
      if (!await file.exists()) continue;

      try {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final entry = LogEntry.fromJson(json);
            if (entry.timestamp.year == date.year &&
                entry.timestamp.month == date.month &&
                entry.timestamp.day == date.day) {
              entries.add(entry);
            }
          } catch (_) {
            // Skip malformed lines.
          }
        }
      } catch (_) {
        // Skip unreadable files.
      }
    }

    return entries;
  }

  // -- Export & Cleanup --

  /// Export logs as formatted text.
  ///
  /// Optionally filter by date range. Returns the full text content.
  Future<String> exportLogs({DateTime? startDate, DateTime? endDate}) async {
    final buffer = StringBuffer();
    buffer.writeln('=== Mobile Agent Log Export ===');
    buffer.writeln('Generated: \${DateTime.now().toUtc().toIso8601String()}');
    if (startDate != null) buffer.writeln('From: \${startDate.toIso8601String()}');
    if (endDate != null) buffer.writeln('To: \${endDate.toIso8601String()}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    // Export in-memory logs.
    final memoryLogs = getRecentLogs(count: _memoryBufferSize);
    for (final entry in memoryLogs) {
      if (_isInDateRange(entry.timestamp, startDate, endDate)) {
        buffer.writeln(entry.formatted);
      }
    }

    // Export file logs.
    final logDir = await _getLogDirectory();
    for (var i = 0; i < _maxFiles; i++) {
      final file = File('${logDir.path}/\$_logFileName.\$i.log');
      if (!await file.exists()) continue;

      try {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final entry = LogEntry.fromJson(json);
            if (_isInDateRange(entry.timestamp, startDate, endDate)) {
              buffer.writeln(entry.formatted);
            }
          } catch (_) {
            buffer.writeln('[PARSE_ERROR] \$line');
          }
        }
      } catch (_) {
        buffer.writeln('[FILE_READ_ERROR] \${file.path}');
      }
    }

    return buffer.toString();
  }

  /// Export logs as JSON string.
  Future<String> exportLogsAsJson({DateTime? startDate, DateTime? endDate}) async {
    final allEntries = <LogEntry>[];

    // Collect from memory.
    allEntries.addAll(getRecentLogs(count: _memoryBufferSize));

    // Collect from files.
    final logDir = await _getLogDirectory();
    for (var i = 0; i < _maxFiles; i++) {
      final file = File('${logDir.path}/\$_logFileName.\$i.log');
      if (!await file.exists()) continue;

      try {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final entry = LogEntry.fromJson(json);
            allEntries.add(entry);
          } catch (_) {
            // Skip malformed.
          }
        }
      } catch (_) {
        // Skip unreadable.
      }
    }

    // Sort and filter.
    allEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final filtered = allEntries.where((e) => _isInDateRange(e.timestamp, startDate, endDate)).toList();

    return jsonEncode(filtered.map((e) => e.toJson()).toList());
  }

  /// Clear all log files and the in-memory buffer.
  Future<void> clearLogs() async {
    _memoryBuffer.clear();

    final logDir = await _getLogDirectory();
    for (var i = 0; i < _maxFiles; i++) {
      final file = File('${logDir.path}/\$_logFileName.\$i.log');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Best effort.
        }
      }
    }

    // Re-open the log file.
    await _fileSink?.close();
    final logFile = File('${logDir.path}/\$_logFileName.0.log');
    _fileSink = logFile.openWrite(mode: FileMode.append);

    i('Logger', 'All logs cleared');
  }

  // -- Private Methods --

  void _log(
    LogLevel level,
    String tag,
    String message,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ) {
    if (_disposed) return;
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
      operationDuration: context?['durationMs'] != null
          ? Duration(milliseconds: context!['durationMs'] as int)
          : null,
    );

    // Add to in-memory ring buffer.
    _memoryBuffer.add(entry);
    if (_memoryBuffer.length > _memoryBufferSize) {
      _memoryBuffer.removeAt(0);
    }

    // Always print to console in debug mode.
    if (kDebugMode) {
      _consolePrint(entry.formatted);
      if (stackTrace != null) {
        _consolePrint(stackTrace.toString().split('\n').take(10).join('\n'));
      }
    }

    // Queue for file write.
    _writeQueue.add(_WriteTask(jsonEncode(entry.toJson())));
  }

  Future<void> _flushQueue() async {
    if (_fileSink == null || _writeQueue.isEmpty) return;

    final tasks = List<_WriteTask>.from(_writeQueue);
    _writeQueue.clear();

    for (final task in tasks) {
      try {
        _fileSink!.writeln(task.jsonLine);
      } catch (e) {
        _consolePrint('Log write error: \$e');
      }
    }

    try {
      await _fileSink!.flush();
    } catch (e) {
      _consolePrint('Log flush error: \$e');
    }
  }

  Future<Directory> _getLogDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/\$_logDirName');
  }

  Future<void> _rotateFilesIfNeeded(Directory logDir) async {
    final currentFile = File('${logDir.path}/\$_logFileName.0.log');

    // Check if current file exceeds max size.
    if (await currentFile.exists()) {
      final size = await currentFile.length();
      if (size < _maxFileSize) return;
    } else {
      return; // No file yet, nothing to rotate.
    }

    // Rotate: shift all files up by one index.
    for (var i = _maxFiles - 1; i > 0; i--) {
      final olderFile = File('${logDir.path}/\$_logFileName.\${i - 1}.log');
      final newerFile = File('${logDir.path}/\$_logFileName.\$i.log');
      if (await olderFile.exists()) {
        try {
          if (await newerFile.exists()) await newerFile.delete();
          await olderFile.copy(newerFile.path);
        } catch (_) {
          // Best effort rotation.
        }
      }
    }

    // Clear the current file (it's now backed up as .1).
    try {
      await currentFile.delete();
    } catch (_) {
      // Best effort.
    }
  }

  bool _isInDateRange(DateTime ts, DateTime? start, DateTime? end) {
    if (start != null && ts.isBefore(start)) return false;
    if (end != null && ts.isAfter(end)) return false;
    return true;
  }

  void _consolePrint(String message) {
    // ignore: avoid_print
    debugPrint('[Logger] \$message');
  }
}

// ---------------------------------------------------------------------------
// _WriteTask - Internal queue item
// ---------------------------------------------------------------------------

class _WriteTask {
  final String jsonLine;
  _WriteTask(this.jsonLine);
}

// ---------------------------------------------------------------------------
// Logger Provider - Global singleton accessor
// ---------------------------------------------------------------------------

/// Global [LoggerService] instance.
///
/// Initialize once in main:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await loggerProvider.init();
///   // ...
/// }
/// ```
final loggerProvider = LoggerService();
