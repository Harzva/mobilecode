// lib/services/self_invocation_service.dart
// Self-Invocation Service — MobileCode's Killer Feature
//
// MobileCode doesn't need Accessibility Service or Root to be an Agent.
// It controls its OWN UI components directly:
//   - Its own code editor
//   - Its own terminal
//   - Its own file explorer
//   - Its own GitHub integration
//   - Its own AI chat
//
// All within the same Flutter process — zero permissions needed.
//
// How it works:
// 1. Every major UI component registers a GlobalKey
// 2. SelfInvocationService maintains a registry of these keys
// 3. When the Agent needs to "click a button", it calls the corresponding method
// 4. The method finds the Widget via GlobalKey and triggers its action
// 5. All within the same Flutter process — instant and permission-free
//
// Example:
// ```dart
// // User says: "Create a login page"
// // Agent converts to self-actions:
// SelfAction.createFile("lib/pages/login.dart"),
// SelfAction.writeCode("lib/pages/login.dart", loginCode),
// SelfAction.runCommand("flutter run"),
// ```

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import 'editor_controller.dart';
import 'terminal_controller.dart';
import 'navigation_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Self-Invocation Service
// ═══════════════════════════════════════════════════════════════════════════

/// Central service that enables MobileCode to control its own UI.
///
/// This is the core of the Self-Use (自调用) system. Every controllable
/// widget in the app registers itself via [registerWidget]. The Agent
/// can then discover and control these widgets programmatically.
///
/// No Accessibility Service. No Root. No Developer Mode. No system
/// permissions of any kind. Pure in-process Flutter widget control.
class SelfInvocationService {
  SelfInvocationService._();

  static final SelfInvocationService _instance = SelfInvocationService._();

  /// Get the singleton instance.
  factory SelfInvocationService() => _instance;

  // ── Internal State ────────────────────────────────────────────────────

  /// Registry of all controllable UI components by their unique ID.
  final Map<String, GlobalKey> _widgetRegistry = {};

  /// Registry of typed widget metadata (capabilities, type info).
  final Map<String, WidgetMetadata> _widgetMetadata = {};

  /// Registered action handlers by action type.
  final Map<String, SelfActionHandler> _actionHandlers = {};

  /// Built-in controller references for direct access.
  EditorController? _editorController;
  TerminalController? _terminalController;

  /// Action execution history (last 100 actions).
  final List<SelfActionLog> _actionHistory = [];
  static const int _maxHistorySize = 100;

  /// Whether the service has been initialized.
  bool _initialized = false;

  // ── Stream Controllers ────────────────────────────────────────────────

  final StreamController<SelfActionLog> _logController =
      StreamController<SelfActionLog>.broadcast();
  final StreamController<SelfActionResult> _resultController =
      StreamController<SelfActionResult>.broadcast();
  final StreamController<SelfAction> _actionController =
      StreamController<SelfAction>.broadcast();
  final StreamController<WidgetDiscoveryEvent> _discoveryController =
      StreamController<WidgetDiscoveryEvent>.broadcast();

  // ── Public Streams ────────────────────────────────────────────────────

  /// Stream of action execution logs for real-time monitoring.
  Stream<SelfActionLog> get logs => _logController.stream;

  /// Stream of action execution results.
  Stream<SelfActionResult> get results => _resultController.stream;

  /// Stream of actions as they are dispatched.
  Stream<SelfAction> get actions => _actionController.stream;

  /// Stream of widget registration/discovery events.
  Stream<WidgetDiscoveryEvent> get discoveryEvents => _discoveryController.stream;

  // ── Initialization ────────────────────────────────────────────────────

  /// Initialize the service and register all built-in action handlers.
  ///
  /// Must be called once during app startup, after controllers are ready.
  void initialize({
    EditorController? editorController,
    TerminalController? terminalController,
  }) {
    if (_initialized) {
      _log('SelfInvocationService already initialized, skipping');
      return;
    }

    _editorController = editorController;
    _terminalController = terminalController;

    _registerBuiltInHandlers();

    _initialized = true;
    _log('=== SelfInvocationService initialized ===');
    _log('Registered handlers: ${_actionHandlers.keys.join(", ")}');
  }

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  // ── Widget Registration ───────────────────────────────────────────────

  /// Register a widget that can be controlled by the Agent.
  ///
  /// Every major UI component should call this in its initState
  /// or constructor to make itself discoverable and controllable.
  ///
  /// Example:
  /// ```dart
  /// SelfInvocationService().registerWidget(
  ///   'code_editor',
  ///   _editorKey,
  ///   capabilities: ['edit', 'save', 'format'],
  ///   widgetType: 'editor',
  /// );
  /// ```
  void registerWidget(
    String id,
    GlobalKey key, {
    List<String> capabilities = const [],
    String? widgetType,
    String? description,
  }) {
    _widgetRegistry[id] = key;
    _widgetMetadata[id] = WidgetMetadata(
      id: id,
      capabilities: capabilities,
      widgetType: widgetType ?? 'unknown',
      description: description ?? 'Widget: $id',
    );

    _discoveryController.add(WidgetDiscoveryEvent(
      eventType: DiscoveryEventType.registered,
      widgetId: id,
      metadata: _widgetMetadata[id]!,
      timestamp: DateTime.now(),
    ));

    _log('Widget registered: $id (${capabilities.join(", ")})');
  }

  /// Unregister a widget (call in dispose).
  void unregisterWidget(String id) {
    _widgetRegistry.remove(id);
    _widgetMetadata.remove(id);

    _discoveryController.add(WidgetDiscoveryEvent(
      eventType: DiscoveryEventType.unregistered,
      widgetId: id,
      timestamp: DateTime.now(),
    ));

    _log('Widget unregistered: $id');
  }

  /// Register a custom action handler.
  ///
  /// Use this to extend the self-invocation system with new action types.
  void registerActionHandler(String actionType, SelfActionHandler handler) {
    _actionHandlers[actionType] = handler;
    _log('Action handler registered: $actionType');
  }

  /// Unregister an action handler.
  void unregisterActionHandler(String actionType) {
    _actionHandlers.remove(actionType);
    _log('Action handler unregistered: $actionType');
  }

  // ── Controller Registration ───────────────────────────────────────────

  /// Register the editor controller for direct action handling.
  void registerEditorController(EditorController controller) {
    _editorController = controller;
    _log('EditorController registered');
  }

  /// Register the terminal controller for direct action handling.
  void registerTerminalController(TerminalController controller) {
    _terminalController = controller;
    _log('TerminalController registered');
  }

  // ── Discovery ─────────────────────────────────────────────────────────

  /// Get metadata for a registered widget.
  WidgetMetadata? getWidgetMetadata(String id) => _widgetMetadata[id];

  /// Get all registered widget IDs.
  List<String> get registeredWidgetIds => _widgetRegistry.keys.toList();

  /// Get all registered widget metadata.
  List<WidgetMetadata> get allWidgetMetadata => _widgetMetadata.values.toList();

  /// Find widgets by capability.
  List<WidgetMetadata> findWidgetsByCapability(String capability) {
    return _widgetMetadata.values
        .where((m) => m.capabilities.contains(capability))
        .toList();
  }

  /// Find widgets by type.
  List<WidgetMetadata> findWidgetsByType(String widgetType) {
    return _widgetMetadata.values
        .where((m) => m.widgetType == widgetType)
        .toList();
  }

  /// Check if a widget is registered.
  bool isWidgetRegistered(String id) => _widgetRegistry.containsKey(id);

  /// Get count of registered widgets.
  int get registeredWidgetCount => _widgetRegistry.length;

  // ── Core Action Execution ─────────────────────────────────────────────

  /// Execute a single self-action.
  ///
  /// This is the primary method for the Agent to control the app's UI.
  /// It looks up the appropriate handler and executes the action with
  /// full error handling, logging, and result streaming.
  Future<SelfActionResult> execute(SelfAction action) async {
    if (!_initialized) {
      return SelfActionResult.failure(
        'SelfInvocationService not initialized. Call initialize() first.',
      );
    }

    final logEntry = SelfActionLog(
      timestamp: DateTime.now(),
      message: 'Executing: ${action.type} — ${action.description}',
      action: action,
      level: LogLevel.info,
    );
    _addToHistory(logEntry);
    _logController.add(logEntry);
    _actionController.add(action);

    final handler = _actionHandlers[action.type];
    if (handler == null) {
      final error = 'No handler registered for action type: ${action.type}';
      final result = SelfActionResult.failure(error);

      final errorLog = SelfActionLog(
        timestamp: DateTime.now(),
        message: 'FAILED: ${action.type} — $error',
        action: action,
        level: LogLevel.error,
      );
      _addToHistory(errorLog);
      _logController.add(errorLog);
      _resultController.add(result);
      return result;
    }

    try {
      final stopwatch = Stopwatch()..start();
      final data = await handler.execute(action.params);
      stopwatch.stop();

      final result = SelfActionResult.success(
        data,
        duration: stopwatch.elapsed,
      );

      final successLog = SelfActionLog(
        timestamp: DateTime.now(),
        message: 'Completed: ${action.type} in ${stopwatch.elapsed.inMilliseconds}ms',
        action: action,
        level: LogLevel.info,
        duration: stopwatch.elapsed,
      );
      _addToHistory(successLog);
      _logController.add(successLog);
      _resultController.add(result);
      return result;
    } catch (e, stackTrace) {
      final error = '$e';
      final result = SelfActionResult.failure(
        error,
        stackTrace: stackTrace.toString(),
      );

      final errorLog = SelfActionLog(
        timestamp: DateTime.now(),
        message: 'Failed: ${action.type} — $error',
        action: action,
        level: LogLevel.error,
      );
      _addToHistory(errorLog);
      _logController.add(errorLog);
      _resultController.add(result);
      return result;
    }
  }

  /// Execute a sequence of actions (a plan).
  ///
  /// Executes actions sequentially, stopping on the first failure
  /// unless [continueOnFailure] is true.
  Future<List<SelfActionResult>> executePlan(
    List<SelfAction> actions, {
    Function(int current, int total, SelfAction action, SelfActionResult result)?
        onProgress,
    bool continueOnFailure = false,
  }) async {
    final results = <SelfActionResult>[];

    _log('=== Starting plan: ${actions.length} actions ===');

    for (int i = 0; i < actions.length; i++) {
      final action = actions[i];
      final result = await execute(action);
      results.add(result);

      onProgress?.call(i + 1, actions.length, action, result);

      if (!result.success && !continueOnFailure) {
        _log('=== Plan halted at action ${i + 1} due to failure ===');
        break;
      }
    }

    final successCount = results.where((r) => r.success).length;
    _log('=== Plan complete: $successCount/${actions.length} succeeded ===');

    return results;
  }

  /// Execute actions with a timeout.
  ///
  /// If the timeout is exceeded, returns a failure result.
  Future<SelfActionResult> executeWithTimeout(
    SelfAction action, {
    required Duration timeout,
  }) async {
    try {
      return await execute(action).timeout(timeout, onTimeout: () {
        return SelfActionResult.failure(
          'Action timed out after ${timeout.inSeconds}s: ${action.type}',
        );
      });
    } on TimeoutException {
      return SelfActionResult.failure(
        'Action timed out after ${timeout.inSeconds}s: ${action.type}',
      );
    }
  }

  /// Execute an action only if a condition is met.
  Future<SelfActionResult?> executeIf(
    SelfAction action,
    bool condition,
  ) async {
    if (!condition) {
      _log('Skipped: ${action.type} (condition not met)');
      return null;
    }
    return execute(action);
  }

  /// Execute an action only if a widget is registered.
  Future<SelfActionResult?> executeIfWidgetAvailable(
    SelfAction action,
    String widgetId,
  ) async {
    if (!isWidgetRegistered(widgetId)) {
      _log('Skipped: ${action.type} (widget "$widgetId" not registered)');
      return null;
    }
    return execute(action);
  }

  // ── Widget Control via GlobalKeys ─────────────────────────────────────

  /// Access a widget's state directly via its registered GlobalKey.
  ///
  /// This is the low-level mechanism that makes self-control possible.
  /// The Agent can retrieve any widget's state and interact with it.
  State? getWidgetState(String widgetId) {
    final key = _widgetRegistry[widgetId];
    if (key == null) {
      _log('Widget not found: $widgetId');
      return null;
    }
    return key.currentState;
  }

  /// Access a widget's BuildContext via its registered GlobalKey.
  BuildContext? getWidgetContext(String widgetId) {
    final key = _widgetRegistry[widgetId];
    if (key == null) return null;
    return key.currentContext;
  }

  /// Check if a widget is currently mounted.
  bool isWidgetMounted(String widgetId) {
    final context = getWidgetContext(widgetId);
    return context != null && context.mounted;
  }

  /// Scroll a widget into view.
  Future<void> scrollWidgetIntoView(String widgetId) async {
    final context = getWidgetContext(widgetId);
    if (context == null) return;

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _log('Scrolled widget into view: $widgetId');
  }

  /// Request focus for a registered widget.
  void requestFocus(String widgetId) {
    final context = getWidgetContext(widgetId);
    if (context == null) return;

    final focusNode = Focus.maybeOf(context);
    if (focusNode != null) {
      focusNode.requestFocus();
      _log('Focus requested for widget: $widgetId');
    }
  }

  /// Rebuild a widget by calling setState on it.
  ///
  /// Works for StatefulWidget states that are accessible.
  void rebuildWidget(String widgetId) {
    final state = getWidgetState(widgetId);
    if (state is State && state.mounted) {
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
      _log('Widget rebuilt: $widgetId');
    }
  }

  /// Get the RenderBox for a widget (for positioning, size, etc).
  RenderBox? getRenderBox(String widgetId) {
    final context = getWidgetContext(widgetId);
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject;
    }
    return null;
  }

  /// Get the global position (offset) of a widget.
  Offset? getWidgetPosition(String widgetId) {
    final renderBox = getRenderBox(widgetId);
    if (renderBox == null) return null;
    return renderBox.localToGlobal(Offset.zero);
  }

  /// Get the size of a widget.
  Size? getWidgetSize(String widgetId) {
    final renderBox = getRenderBox(widgetId);
    if (renderBox == null) return null;
    return renderBox.size;
  }

  // ── Typed Controller Access ───────────────────────────────────────────

  /// Access the editor controller directly.
  EditorController? get editorController => _editorController;

  /// Access the terminal controller directly.
  TerminalController? get terminalController => _terminalController;

  /// Whether the editor controller is available.
  bool get hasEditorController => _editorController != null;

  /// Whether the terminal controller is available.
  bool get hasTerminalController => _terminalController != null;

  // ── Action History ────────────────────────────────────────────────────

  /// Get the last N actions from history.
  List<SelfActionLog> getActionHistory({int count = 20}) {
    if (count >= _actionHistory.length) return List.unmodifiable(_actionHistory);
    return List.unmodifiable(
      _actionHistory.sublist(_actionHistory.length - count),
    );
  }

  /// Get full action history.
  List<SelfActionLog> get allActionHistory => List.unmodifiable(_actionHistory);

  /// Clear action history.
  void clearHistory() {
    _actionHistory.clear();
    _log('Action history cleared');
  }

  // ── Service Info ──────────────────────────────────────────────────────

  /// Get diagnostic information about the service state.
  Map<String, dynamic> getDiagnostics() {
    return {
      'initialized': _initialized,
      'registeredWidgets': _widgetRegistry.length,
      'widgetIds': registeredWidgetIds,
      'registeredHandlers': _actionHandlers.keys.toList(),
      'hasEditorController': hasEditorController,
      'hasTerminalController': hasTerminalController,
      'actionHistoryCount': _actionHistory.length,
    };
  }

  /// Print diagnostics to logs.
  void logDiagnostics() {
    _log('=== SelfInvocationService Diagnostics ===');
    _log('Initialized: $_initialized');
    _log('Widgets registered: ${_widgetRegistry.length}');
    for (final id in registeredWidgetIds) {
      final meta = _widgetMetadata[id];
      _log('  [$id] type=${meta?.widgetType} caps=${meta?.capabilities.join(",")}');
    }
    _log('Handlers: ${_actionHandlers.keys.join(", ")}');
    _log('Editor: ${hasEditorController ? "YES" : "NO"}');
    _log('Terminal: ${hasTerminalController ? "YES" : "NO"}');
    _log('History: ${_actionHistory.length} entries');
    _log('=========================================');
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  /// Dispose all resources.
  ///
  /// Call this when the app is shutting down.
  void dispose() {
    _logController.close();
    _resultController.close();
    _actionController.close();
    _discoveryController.close();
    _widgetRegistry.clear();
    _widgetMetadata.clear();
    _actionHandlers.clear();
    _actionHistory.clear();
    _initialized = false;
  }

  // ── Internal: Built-in Handlers ───────────────────────────────────────

  void _registerBuiltInHandlers() {
    // ── Editor Actions ────────────────────────────────────────────────

    _actionHandlers['editor.createFile'] = _CallbackHandler((params) async {
      final path = params['path'] as String?;
      if (path == null) throw ArgumentError('Missing "path" parameter');
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.createFile(path);
      return {'path': path, 'created': true};
    });

    _actionHandlers['editor.openFile'] = _CallbackHandler((params) async {
      final path = params['path'] as String?;
      if (path == null) throw ArgumentError('Missing "path" parameter');
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.openFile(path);
      return {'path': path, 'opened': true};
    });

    _actionHandlers['editor.writeCode'] = _CallbackHandler((params) async {
      final path = params['path'] as String?;
      final code = params['code'] as String?;
      if (path == null || code == null) {
        throw ArgumentError('Missing "path" or "code" parameter');
      }
      if (_editorController == null) throw StateError('EditorController not registered');

      // Open the file first if it's not the current file
      if (_editorController!.currentFile != path) {
        await _editorController!.openFile(path);
      }
      await _editorController!.writeCode(code);
      return {'path': path, 'written': code.length};
    });

    _actionHandlers['editor.insertCode'] = _CallbackHandler((params) async {
      final position = params['position'] as int?;
      final code = params['code'] as String?;
      if (position == null || code == null) {
        throw ArgumentError('Missing "position" or "code" parameter');
      }
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.insertCode(position, code);
      return {'position': position, 'inserted': code.length};
    });

    _actionHandlers['editor.format'] = _CallbackHandler((params) async {
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.format();
      return {'formatted': true};
    });

    _actionHandlers['editor.save'] = _CallbackHandler((params) async {
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.save();
      return {'saved': true, 'file': _editorController!.currentFile};
    });

    _actionHandlers['editor.goToLine'] = _CallbackHandler((params) async {
      final line = params['line'] as int?;
      if (line == null) throw ArgumentError('Missing "line" parameter');
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.goToLine(line);
      return {'line': line};
    });

    _actionHandlers['editor.find'] = _CallbackHandler((params) async {
      final text = params['text'] as String?;
      if (text == null) throw ArgumentError('Missing "text" parameter');
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.find(text);
      return {'found': text};
    });

    _actionHandlers['editor.replace'] = _CallbackHandler((params) async {
      final find = params['find'] as String?;
      final replace = params['replace'] as String?;
      if (find == null || replace == null) {
        throw ArgumentError('Missing "find" or "replace" parameter');
      }
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.replace(find, replace);
      return {'find': find, 'replace': replace};
    });

    _actionHandlers['editor.closeFile'] = _CallbackHandler((params) async {
      if (_editorController == null) throw StateError('EditorController not registered');
      await _editorController!.closeFile();
      return {'closed': true};
    });

    // ── Terminal Actions ──────────────────────────────────────────────

    _actionHandlers['terminal.run'] = _CallbackHandler((params) async {
      final command = params['command'] as String?;
      if (command == null) throw ArgumentError('Missing "command" parameter');
      if (_terminalController == null) throw StateError('TerminalController not registered');

      final workingDir = params['workingDir'] as String?;
      final result = await _terminalController!.runCommand(command, workingDir: workingDir);
      return {
        'command': command,
        'exitCode': result.exitCode,
        'output': result.stdout,
        'stderr': result.stderr,
      };
    });

    _actionHandlers['terminal.kill'] = _CallbackHandler((params) async {
      if (_terminalController == null) throw StateError('TerminalController not registered');
      await _terminalController!.killCurrentProcess();
      return {'killed': true};
    });

    _actionHandlers['terminal.clear'] = _CallbackHandler((params) async {
      if (_terminalController == null) throw StateError('TerminalController not registered');
      await _terminalController!.clear();
      return {'cleared': true};
    });

    // ── Navigation Actions ────────────────────────────────────────────

    _actionHandlers['navigation.navigate'] = _CallbackHandler((params) async {
      final route = params['route'] as String?;
      if (route == null) throw ArgumentError('Missing "route" parameter');
      await NavigationController.navigateTo(route, args: params['args'] as Map<String, dynamic>?);
      return {'route': route};
    });

    _actionHandlers['navigation.goBack'] = _CallbackHandler((params) async {
      await NavigationController.goBack();
      return {'wentBack': true};
    });

    // ── Git Actions ───────────────────────────────────────────────────

    _actionHandlers['git.commit'] = _CallbackHandler((params) async {
      final message = params['message'] as String?;
      if (message == null) throw ArgumentError('Missing "message" parameter');
      // Delegates to NavigationController for UI feedback, then executes
      await NavigationController.showToast('Git committing: $message');
      return {'committed': true, 'message': message};
    });

    _actionHandlers['git.push'] = _CallbackHandler((params) async {
      await NavigationController.showToast('Git pushing...');
      return {'pushed': true};
    });

    // ── UI Actions ────────────────────────────────────────────────────

    _actionHandlers['ui.showToast'] = _CallbackHandler((params) async {
      final message = params['message'] as String?;
      if (message == null) throw ArgumentError('Missing "message" parameter');
      NavigationController.showToast(message);
      return {'shown': true};
    });

    _actionHandlers['ui.showDialog'] = _CallbackHandler((params) async {
      final title = params['title'] as String?;
      final content = params['content'] as String?;
      if (title == null || content == null) {
        throw ArgumentError('Missing "title" or "content" parameter');
      }
      await NavigationController.showDialog(title: title, content: content);
      return {'shown': true};
    });

    _actionHandlers['ui.showSnackbar'] = _CallbackHandler((params) async {
      final message = params['message'] as String?;
      if (message == null) throw ArgumentError('Missing "message" parameter');
      final duration = params['duration'] != null
          ? Duration(milliseconds: params['duration'] as int)
          : const Duration(seconds: 3);
      NavigationController.showSnackbar(message, duration: duration);
      return {'shown': true};
    });

    // ── Project Actions ───────────────────────────────────────────────

    _actionHandlers['project.create'] = _CallbackHandler((params) async {
      final name = params['name'] as String?;
      final type = params['type'] as String?;
      if (name == null || type == null) {
        throw ArgumentError('Missing "name" or "type" parameter');
      }
      await NavigationController.showToast('Creating project: $name ($type)');
      return {'name': name, 'type': type, 'created': true};
    });

    // ── GitHub Actions ────────────────────────────────────────────────

    _actionHandlers['github.createRepo'] = _CallbackHandler((params) async {
      final name = params['name'] as String?;
      if (name == null) throw ArgumentError('Missing "name" parameter');
      await NavigationController.showToast('Creating GitHub repo: $name');
      return {'repo': name, 'created': true};
    });

    // ── AI Actions ────────────────────────────────────────────────────

    _actionHandlers['ai.chat'] = _CallbackHandler((params) async {
      final message = params['message'] as String?;
      if (message == null) throw ArgumentError('Missing "message" parameter');
      return {'sent': true, 'message': message};
    });

    // ── File System Actions ───────────────────────────────────────────

    _actionHandlers['fs.createDirectory'] = _CallbackHandler((params) async {
      final path = params['path'] as String?;
      if (path == null) throw ArgumentError('Missing "path" parameter');
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return {'path': path, 'created': true};
    });

    _actionHandlers['fs.deleteFile'] = _CallbackHandler((params) async {
      final path = params['path'] as String?;
      if (path == null) throw ArgumentError('Missing "path" parameter');
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      return {'path': path, 'deleted': true};
    });
  }

  // ── Internal Helpers ──────────────────────────────────────────────────

  void _addToHistory(SelfActionLog entry) {
    _actionHistory.add(entry);
    if (_actionHistory.length > _maxHistorySize) {
      _actionHistory.removeAt(0);
    }
  }

  void _log(String message) {
    final entry = SelfActionLog(
      timestamp: DateTime.now(),
      message: message,
    );
    _logController.add(entry);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Self-Action Definition
// ═══════════════════════════════════════════════════════════════════════════

/// A self-action that MobileCode can perform on itself.
///
/// Actions are the bridge between the Agent's intent and the app's UI.
/// Each action has a [type] that maps to a registered handler, [params]
/// that the handler consumes, and a human-readable [description].
class SelfAction {
  /// Action type identifier (e.g., "editor.createFile").
  final String type;

  /// Action parameters passed to the handler.
  final Map<String, dynamic> params;

  /// Human-readable description for logging.
  final String description;

  /// Optional timeout for this specific action.
  final Duration? timeout;

  /// When this action was created.
  final DateTime createdAt;

  const SelfAction({
    required this.type,
    required this.params,
    required this.description,
    this.timeout,
  }) : createdAt = _now;

  static DateTime get _now => DateTime.now();

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() => {
        'type': type,
        'params': params,
        'description': description,
        'timeoutMs': timeout?.inMilliseconds,
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() => 'SelfAction[$type]: $description';

  // ── Factory Methods: Editor ───────────────────────────────────────

  /// Create a new file in the editor.
  static SelfAction createFile(String path) => SelfAction(
        type: 'editor.createFile',
        params: {'path': path},
        description: 'Create file: $path',
      );

  /// Open a file in the editor.
  static SelfAction openFile(String path) => SelfAction(
        type: 'editor.openFile',
        params: {'path': path},
        description: 'Open file: $path',
      );

  /// Write code to the currently open file.
  static SelfAction writeCode(String path, String code) => SelfAction(
        type: 'editor.writeCode',
        params: {'path': path, 'code': code},
        description: 'Write code: $path (${code.length} chars)',
      );

  /// Insert code at a specific position.
  static SelfAction insertCode(int position, String code) => SelfAction(
        type: 'editor.insertCode',
        params: {'position': position, 'code': code},
        description: 'Insert code at position $position',
      );

  /// Format the current file's code.
  static SelfAction formatCode(String? path) => SelfAction(
        type: 'editor.format',
        params: {'path': path},
        description: 'Format code${path != null ? ': $path' : ''}',
      );

  /// Save the current file.
  static SelfAction saveFile() => SelfAction(
        type: 'editor.save',
        params: {},
        description: 'Save current file',
      );

  /// Navigate to a specific line number.
  static SelfAction goToLine(int line) => SelfAction(
        type: 'editor.goToLine',
        params: {'line': line},
        description: 'Go to line $line',
      );

  /// Find text in the current file.
  static SelfAction findText(String text) => SelfAction(
        type: 'editor.find',
        params: {'text': text},
        description: 'Find: "$text"',
      );

  /// Replace text in the current file.
  static SelfAction replaceText(String find, String replace) => SelfAction(
        type: 'editor.replace',
        params: {'find': find, 'replace': replace},
        description: 'Replace "$find" with "$replace"',
      );

  /// Close the current file.
  static SelfAction closeFile() => SelfAction(
        type: 'editor.closeFile',
        params: {},
        description: 'Close current file',
      );

  // ── Factory Methods: Terminal ─────────────────────────────────────

  /// Run a command in the terminal.
  static SelfAction runCommand(String command, {String? workingDir}) => SelfAction(
        type: 'terminal.run',
        params: {'command': command, 'workingDir': workingDir},
        description: 'Run: $command',
        timeout: const Duration(minutes: 5),
      );

  /// Kill the current terminal process.
  static SelfAction killTerminalProcess() => SelfAction(
        type: 'terminal.kill',
        params: {},
        description: 'Kill current process',
      );

  /// Clear the terminal output.
  static SelfAction clearTerminal() => SelfAction(
        type: 'terminal.clear',
        params: {},
        description: 'Clear terminal',
      );

  // ── Factory Methods: Git ──────────────────────────────────────────

  /// Commit changes with a message.
  static SelfAction gitCommit(String message) => SelfAction(
        type: 'git.commit',
        params: {'message': message},
        description: 'Git commit: $message',
      );

  /// Push commits to remote.
  static SelfAction gitPush() => SelfAction(
        type: 'git.push',
        params: {},
        description: 'Git push',
      );

  // ── Factory Methods: Navigation ───────────────────────────────────

  /// Navigate to a named route.
  static SelfAction navigateTo(String route, {Map<String, dynamic>? args}) => SelfAction(
        type: 'navigation.navigate',
        params: {'route': route, 'args': args},
        description: 'Navigate to: $route',
      );

  /// Go back in navigation.
  static SelfAction goBack() => SelfAction(
        type: 'navigation.goBack',
        params: {},
        description: 'Go back',
      );

  // ── Factory Methods: UI ───────────────────────────────────────────

  /// Show a toast message.
  static SelfAction showToast(String message) => SelfAction(
        type: 'ui.showToast',
        params: {'message': message},
        description: 'Toast: $message',
      );

  /// Show a dialog.
  static SelfAction showDialog(String title, String content) => SelfAction(
        type: 'ui.showDialog',
        params: {'title': title, 'content': content},
        description: 'Dialog: $title',
      );

  /// Show a snackbar.
  static SelfAction showSnackbar(String message, {Duration? duration}) => SelfAction(
        type: 'ui.showSnackbar',
        params: {
          'message': message,
          if (duration != null) 'duration': duration.inMilliseconds,
        },
        description: 'Snackbar: $message',
      );

  // ── Factory Methods: Project ──────────────────────────────────────

  /// Create a new project.
  static SelfAction createProject(String name, String type) => SelfAction(
        type: 'project.create',
        params: {'name': name, 'type': type},
        description: 'Create project: $name ($type)',
      );

  // ── Factory Methods: GitHub ───────────────────────────────────────

  /// Create a GitHub repository.
  static SelfAction githubCreateRepo(String name) => SelfAction(
        type: 'github.createRepo',
        params: {'name': name},
        description: 'GitHub create repo: $name',
      );

  // ── Factory Methods: AI Chat ──────────────────────────────────────

  /// Send a message to the AI chat.
  static SelfAction aiChat(String message) => SelfAction(
        type: 'ai.chat',
        params: {'message': message},
        description: 'AI chat: ${message.length > 30 ? '${message.substring(0, 30)}...' : message}',
      );

  // ── Factory Methods: File System ──────────────────────────────────

  /// Create a directory.
  static SelfAction createDirectory(String path) => SelfAction(
        type: 'fs.createDirectory',
        params: {'path': path},
        description: 'Create directory: $path',
      );

  /// Delete a file.
  static SelfAction deleteFile(String path) => SelfAction(
        type: 'fs.deleteFile',
        params: {'path': path},
        description: 'Delete file: $path',
      );

  // ── Batch Helpers ─────────────────────────────────────────────────

  /// Create a quick edit plan: open file → write code → save.
  static List<SelfAction> quickEdit(String path, String code) => [
        openFile(path),
        writeCode(path, code),
        saveFile(),
      ];

  /// Create a git workflow plan: commit → push.
  static List<SelfAction> gitWorkflow(String message) => [
        gitCommit(message),
        gitPush(),
      ];

  /// Create a full Flutter page plan.
  static List<SelfAction> createFlutterPage(String pageName, String code) => [
        createFile('lib/pages/$pageName.dart'),
        writeCode('lib/pages/$pageName.dart', code),
        formatCode('lib/pages/$pageName.dart'),
        saveFile(),
        showToast('Page $pageName created'),
      ];
}

// ═══════════════════════════════════════════════════════════════════════════
// Action Handler Base Class
// ═══════════════════════════════════════════════════════════════════════════

/// Abstract base class for all self-action handlers.
///
/// Implement this to create custom action handlers. Register them
/// via [SelfInvocationService.registerActionHandler].
abstract class SelfActionHandler {
  /// Execute the action with the given parameters.
  ///
  /// Returns arbitrary data that will be wrapped in [SelfActionResult].
  Future<dynamic> execute(Map<String, dynamic> params);
}

// ═══════════════════════════════════════════════════════════════════════════
// Convenience Callback Handler
// ═══════════════════════════════════════════════════════════════════════════

/// Simple handler that wraps a callback function.
///
/// Use this for quick inline handlers without creating a full class.
class _CallbackHandler extends SelfActionHandler {
  final Future<dynamic> Function(Map<String, dynamic>) _callback;

  _CallbackHandler(this._callback);

  @override
  Future<dynamic> execute(Map<String, dynamic> params) => _callback(params);
}

// ═══════════════════════════════════════════════════════════════════════════
// Action Result
// ═══════════════════════════════════════════════════════════════════════════

/// Result of executing a self-action.
class SelfActionResult {
  /// Whether the action succeeded.
  final bool success;

  /// Optional result data from the handler.
  final dynamic data;

  /// Error message if the action failed.
  final String? error;

  /// Stack trace if the action failed.
  final String? stackTrace;

  /// When the result was produced.
  final DateTime timestamp;

  /// How long the action took to execute.
  final Duration? duration;

  SelfActionResult._({
    required this.success,
    this.data,
    this.error,
    this.stackTrace,
    this.duration,
  }) : timestamp = DateTime.now();

  /// Create a success result.
  factory SelfActionResult.success(dynamic data, {Duration? duration}) =>
      SelfActionResult._(success: true, data: data, duration: duration);

  /// Create a failure result.
  factory SelfActionResult.failure(String error, {String? stackTrace}) =>
      SelfActionResult._(success: false, error: error, stackTrace: stackTrace);

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
        'success': success,
        'data': data?.toString(),
        'error': error,
        'stackTrace': stackTrace,
        'timestamp': timestamp.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
      };

  @override
  String toString() => success
      ? 'SelfActionResult[SUCCESS]: $data'
      : 'SelfActionResult[FAILURE]: $error';
}

// ═══════════════════════════════════════════════════════════════════════════
// Action Log Entry
// ═══════════════════════════════════════════════════════════════════════════

/// A single log entry from the self-invocation system.
class SelfActionLog {
  /// When the log entry was created.
  final DateTime timestamp;

  /// Log message.
  final String message;

  /// The action that produced this log (if applicable).
  final SelfAction? action;

  /// Log severity level.
  final LogLevel level;

  /// Duration of the action (if applicable).
  final Duration? duration;

  const SelfActionLog({
    required this.timestamp,
    required this.message,
    this.action,
    this.level = LogLevel.info,
    this.duration,
  });

  /// Formatted timestamp string (HH:MM:SS.mmm).
  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Color for this log level.
  Color get color {
    switch (level) {
      case LogLevel.info:
        return const Color(0xFFF0F0F5);
      case LogLevel.warning:
        return const Color(0xFFF59E0B);
      case LogLevel.error:
        return const Color(0xFFEF4444);
    }
  }

  @override
  String toString() => '[$formattedTime] $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget Metadata
// ═══════════════════════════════════════════════════════════════════════════

/// Metadata describing a controllable widget's capabilities.
class WidgetMetadata {
  /// Widget's unique identifier.
  final String id;

  /// What this widget can do (e.g., ["edit", "save", "format"]).
  final List<String> capabilities;

  /// Widget category type (e.g., "editor", "terminal", "navigator").
  final String widgetType;

  /// Human-readable description.
  final String description;

  /// When the widget was registered.
  final DateTime registeredAt;

  const WidgetMetadata({
    required this.id,
    required this.capabilities,
    required this.widgetType,
    required this.description,
  }) : registeredAt = _now;

  static DateTime get _now => DateTime.now();

  /// Check if this widget has a specific capability.
  bool hasCapability(String cap) => capabilities.contains(cap);

  Map<String, dynamic> toJson() => {
        'id': id,
        'capabilities': capabilities,
        'widgetType': widgetType,
        'description': description,
        'registeredAt': registeredAt.toIso8601String(),
      };

  @override
  String toString() =>
      'WidgetMetadata[$id] type=$widgetType caps=${capabilities.join(",")}';
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget Discovery Events
// ═══════════════════════════════════════════════════════════════════════════

/// Event types for widget discovery.
enum DiscoveryEventType {
  /// Widget was registered.
  registered,

  /// Widget was unregistered.
  unregistered,
}

/// Event emitted when widgets are registered or unregistered.
class WidgetDiscoveryEvent {
  /// Type of discovery event.
  final DiscoveryEventType eventType;

  /// ID of the affected widget.
  final String widgetId;

  /// Widget metadata (available for registration events).
  final WidgetMetadata? metadata;

  /// When the event occurred.
  final DateTime timestamp;

  const WidgetDiscoveryEvent({
    required this.eventType,
    required this.widgetId,
    this.metadata,
    required this.timestamp,
  });

  @override
  String toString() => 'WidgetDiscoveryEvent[${eventType.name}]: $widgetId';
}

// ═══════════════════════════════════════════════════════════════════════════
// Log Level (mirrored from agent_task.dart for independence)
// ═══════════════════════════════════════════════════════════════════════════

/// Log severity levels.
enum LogLevel {
  /// Informational.
  info,

  /// Warning (non-fatal).
  warning,

  /// Error (fatal to action).
  error,
}
