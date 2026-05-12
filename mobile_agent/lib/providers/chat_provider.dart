// lib/providers/chat_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/chat_message.dart';
import '../services/context_injector.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';
import 'api_config_provider.dart';
import 'llm_service_provider.dart';
import 'storage_provider.dart';

// ─── LLM Service Provider ──────────────────────────────────────────

/// Provider for the LLM service.
///
/// Depends on the shared [ApiService] from [apiServiceProvider].
// final llmServiceProvider = Provider<LLMService>((ref) {
//   final apiService = ref.watch(apiServiceProvider);
//   return LLMService(apiService);
// });

// ─── Chat Messages ─────────────────────────────────────────────────

/// Manages chat messages for the current conversation session.
///
/// Handles adding messages, streaming AI responses, clearing history,
/// and persisting to local storage.
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  LLMService get _llm => _ref.read(llmServiceProvider);
  StorageService get _storage => _ref.read(storageServiceProvider);

  /// Session identifier for this chat.
  final String _sessionId;

  /// Active stream subscription (for cancellation).
  StreamSubscription<String>? _activeStream;

  ChatNotifier(this._ref, {String? sessionId})
      : _sessionId = sessionId ?? 'default',
        super([]) {
    _loadHistory();
  }

  /// Load chat history from local storage.
  Future<void> _loadHistory() async {
    try {
      final messages = await _storage.getChatMessages(_sessionId);
      if (messages.isNotEmpty) {
        state = messages;
        debugPrint('[ChatNotifier] Loaded ${messages.length} messages for session $_sessionId');
      }
    } catch (e) {
      debugPrint('[ChatNotifier] Failed to load history: $e');
    }
  }

  /// Persist a message to local storage.
  Future<void> _saveMessage(ChatMessage message) async {
    try {
      await _storage.saveChatMessage(_sessionId, message);
    } catch (e) {
      debugPrint('[ChatNotifier] Failed to save message: $e');
    }
  }

  /// Add a user message to the chat.
  ///
  /// Does not send to the AI — use [sendMessage] for that.
  void addUserMessage(String content, {String? codeContext, String? language}) {
    final message = ChatMessage.user(content, codeContext: codeContext, language: language);
    state = [...state, message];
    _saveMessage(message);
  }

  /// Add a system message to the chat.
  void addSystemMessage(String content) {
    final message = ChatMessage.system(content);
    state = [...state, message];
    _saveMessage(message);
  }

  /// Send a message and receive a non-streaming AI response.
  ///
  /// This is the simplest way to chat — sends the message and
  /// waits for the complete response.
  ///
  /// [content]     The user's message text.
  /// [codeContext] Optional code snippet to include with the message.
  /// [language]    Programming language of the code context.
  Future<void> sendMessage(
    String content, {
    String? codeContext,
    String? language,
    ApiConfig? overrideConfig,
  }) async {
    // Add user message.
    final userMessage = ChatMessage.user(content, codeContext: codeContext, language: language);
    state = [...state, userMessage];
    await _saveMessage(userMessage);

    // Get active config.
    final config = overrideConfig ?? _ref.read(activeApiConfigProvider);
    if (config == null) {
      _addErrorMessage('No API configuration selected. Please add one in Settings.');
      return;
    }

    if (config.apiKey.isEmpty) {
      _addErrorMessage('API key is empty. Please configure your API key in Settings.');
      return;
    }

    // Mark AI as responding.
    _ref.read(isAiRespondingProvider.notifier).state = true;

    try {
      // Get history (exclude system messages from display).
      final history = state.where((m) => m.role != MessageRole.system).toList();

      // Build context prompt from project code.
      String? contextPrompt;
      try {
        final injector = ContextInjector();
        if (_sessionId.isNotEmpty) {
          contextPrompt = await injector.buildContextPrompt(_sessionId, content);
        }
      } catch (e) {
        debugPrint('[ChatNotifier] Context injection skipped: $e');
      }

      // Send to LLM.
      final responseText = await _llm.chat(content, history, config, contextPrompt: contextPrompt);

      // Add assistant message.
      final assistantMessage = ChatMessage.assistant(responseText);
      state = [...state, assistantMessage];
      await _saveMessage(assistantMessage);
    } catch (e) {
      debugPrint('[ChatNotifier] Chat error: $e');
      _addErrorMessage('Error: $e');
    } finally {
      _ref.read(isAiRespondingProvider.notifier).state = false;
    }
  }

  /// Send a message and stream the AI response in real-time.
  ///
  /// Yields partial content chunks as they arrive, updating the
  /// UI for a fluid typing effect.
  ///
  /// [content]     The user's message text.
  /// [codeContext] Optional code snippet to include with the message.
  /// [language]    Programming language of the code context.
  Future<void> sendMessageStream(
    String content, {
    String? codeContext,
    String? language,
    ApiConfig? overrideConfig,
  }) async {
    // Cancel any active stream.
    await _activeStream?.cancel();

    // Add user message.
    final userMessage = ChatMessage.user(content, codeContext: codeContext, language: language);
    state = [...state, userMessage];
    await _saveMessage(userMessage);

    // Get active config.
    final config = overrideConfig ?? _ref.read(activeApiConfigProvider);
    if (config == null) {
      _addErrorMessage('No API configuration selected. Please add one in Settings.');
      return;
    }

    if (config.apiKey.isEmpty) {
      _addErrorMessage('API key is empty. Please configure your API key in Settings.');
      return;
    }

    // Create streaming assistant message.
    final streamingMessage = ChatMessage.assistant('', isStreaming: true);
    state = [...state, streamingMessage];

    // Mark AI as responding.
    _ref.read(isAiRespondingProvider.notifier).state = true;

    // Get history.
    final history = state.where((m) => m.role != MessageRole.system && !m.isStreaming).toList();

    String accumulatedContent = '';

    try {
      // Build context prompt from project code.
      String? contextPrompt;
      try {
        final injector = ContextInjector();
        if (_sessionId.isNotEmpty) {
          contextPrompt = await injector.buildContextPrompt(_sessionId, content);
        }
      } catch (e) {
        debugPrint('[ChatNotifier] Context injection skipped: $e');
      }

      _activeStream = _llm.chatStream(content, history, config, contextPrompt: contextPrompt).listen(
        (chunk) {
          accumulatedContent += chunk;
          final updatedMessage = streamingMessage.copyWith(
            content: accumulatedContent,
          );
          state = [...state.sublist(0, state.length - 1), updatedMessage];
        },
        onError: (e) {
          debugPrint('[ChatNotifier] Stream error: $e');
          final errorMessage = streamingMessage.copyWith(
            content: '${accumulatedContent.isNotEmpty ? "$accumulatedContent\n\n---\n\n" : ""}Error: $e',
            isStreaming: false,
            isComplete: true,
          );
          state = [...state.sublist(0, state.length - 1), errorMessage];
          _ref.read(isAiRespondingProvider.notifier).state = false;
        },
        onDone: () {
          // Mark stream complete.
          final completedMessage = streamingMessage.copyWith(
            content: accumulatedContent,
            isStreaming: false,
            isComplete: true,
          );
          state = [...state.sublist(0, state.length - 1), completedMessage];
          _saveMessage(completedMessage);
          _ref.read(isAiRespondingProvider.notifier).state = false;
          _activeStream = null;
        },
      );
    } catch (e) {
      debugPrint('[ChatNotifier] Stream setup error: $e');
      _addErrorMessage('Error: $e');
      _ref.read(isAiRespondingProvider.notifier).state = false;
    }
  }

  /// Cancel the active streaming response.
  Future<void> cancelStream() async {
    await _activeStream?.cancel();
    _activeStream = null;

    // Mark the last message as complete if it was streaming.
    if (state.isNotEmpty && state.last.isStreaming) {
      final updated = state.last.copyWith(isStreaming: false, isComplete: true);
      state = [...state.sublist(0, state.length - 1), updated];
    }

    _ref.read(isAiRespondingProvider.notifier).state = false;
  }

  /// Clear all messages in the current session.
  Future<void> clearMessages() async {
    await cancelStream();
    state = [];

    try {
      await _storage.clearChatHistory(_sessionId);
    } catch (e) {
      debugPrint('[ChatNotifier] Failed to clear history: $e');
    }
  }

  /// Delete a specific message by ID.
  void deleteMessage(String id) {
    state = state.where((m) => m.id != id).toList();
  }

  /// Regenerate (re-request) the last AI response.
  ///
  /// Removes the last assistant message and re-sends the last
  /// user message to the AI.
  Future<void> regenerateLastResponse() async {
    if (state.length < 2) return;

    // Find last user message.
    int lastUserIndex = -1;
    for (var i = state.length - 1; i >= 0; i--) {
      if (state[i].role == MessageRole.user) {
        lastUserIndex = i;
        break;
      }
    }

    if (lastUserIndex == -1) return;

    final lastUserMessage = state[lastUserIndex];

    // Remove all messages after the last user message.
    state = state.sublist(0, lastUserIndex + 1);

    // Re-send.
    await sendMessageStream(
      lastUserMessage.content,
      codeContext: lastUserMessage.codeContext,
      language: lastUserMessage.language,
    );
  }

  /// Add an error message to the chat.
  void _addErrorMessage(String error) {
    final errorMsg = ChatMessage.assistant(error);
    state = [...state, errorMsg];
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    super.dispose();
  }
}

/// Provider for chat messages in the current session.
///
/// Returns the current list of messages. Use the notifier
/// for sending messages, clearing history, etc.
///
/// ```dart
/// final messages = ref.watch(chatMessagesProvider);
/// ref.read(chatMessagesProvider.notifier).sendMessage('Hello!');
/// ```
final chatMessagesProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>(
  (ref) => ChatNotifier(ref),
);

/// Provider for chat messages scoped to a specific session.
///
/// Use this for project-specific or file-specific chat sessions.
final chatMessagesForSessionProvider = StateNotifierProvider.family<
    ChatNotifier, List<ChatMessage>, String>(
  (ref, sessionId) => ChatNotifier(ref, sessionId: sessionId),
);

// ─── AI Response State ─────────────────────────────────────────────

/// Whether the AI is currently generating a response.
///
/// Used to show a loading indicator and disable the send button.
///
/// ```dart
/// final isResponding = ref.watch(isAiRespondingProvider);
/// if (isResponding) { ... }
/// ```
final isAiRespondingProvider = StateProvider<bool>((ref) => false);

/// Whether the current AI response is being streamed.
///
/// Distinct from [isAiRespondingProvider] — this is true only
/// during active streaming (not during the initial request phase).
final isStreamingResponseProvider = Provider<bool>((ref) {
  final messages = ref.watch(chatMessagesProvider);
  if (messages.isEmpty) return false;
  return messages.last.isStreaming;
});

// ─── Chat Input State ──────────────────────────────────────────────

/// Current text in the chat input field.
///
/// Used to persist input across rebuilds.
final chatInputProvider = StateProvider<String>((ref) => '');

/// Whether the chat panel is visible.
final chatPanelVisibleProvider = StateProvider<bool>((ref) => true);

// ─── Quick Actions ─────────────────────────────────────────────────

/// Predefined quick action prompts for the chat interface.
final quickActionsProvider = Provider<List<QuickAction>>((ref) => [
      QuickAction(
        label: 'Explain',
        icon: 'lightbulb',
        prompt: 'Explain this code in detail:',
      ),
      QuickAction(
        label: 'Refactor',
        icon: 'auto_fix_high',
        prompt: 'Refactor this code to improve readability and performance:',
      ),
      QuickAction(
        label: 'Add Tests',
        icon: 'check_circle',
        prompt: 'Write comprehensive unit tests for this code:',
      ),
      QuickAction(
        label: 'Document',
        icon: 'description',
        prompt: 'Add documentation comments to this code:',
      ),
      QuickAction(
        label: 'Debug',
        icon: 'bug_report',
        prompt: 'Find and fix any bugs in this code:',
      ),
      QuickAction(
        label: 'Optimize',
        icon: 'speed',
        prompt: 'Optimize this code for better performance:',
      ),
    ]);

/// A quick action button in the chat interface.
class QuickAction {
  final String label;
  final String icon;
  final String prompt;

  const QuickAction({
    required this.label,
    required this.icon,
    required this.prompt,
  });
}
