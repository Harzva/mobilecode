// lib/services/llm_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/api_config.dart';
import '../models/chat_message.dart';
import 'api_service.dart';

/// Exception specific to LLM API failures.
class LLMException implements Exception {
  final String message;
  final String? provider;
  final String? model;
  final dynamic originalError;

  const LLMException({
    required this.message,
    this.provider,
    this.model,
    this.originalError,
  });

  @override
  String toString() => 'LLMException [$provider/$model]: $message';
}

/// System prompts for different LLM operations.
class SystemPrompts {
  const SystemPrompts._();

  static const String codeCompletion = '''
You are an expert code completion assistant. Given a code snippet and its programming language, 
provide ONLY the completion/ccontinuation code. Do not wrap in markdown code blocks unless 
the code itself requires it. Output only the code that should come next, nothing else.
'''.trim();

  static const String codeExplanation = '''
You are an expert programming tutor. Explain the provided code clearly and concisely.
Cover:
1. What the code does at a high level
2. Key functions, classes, or patterns used
3. Any important logic or edge cases

Be educational but concise. Use markdown formatting for readability.
'''.trim();

  static const String codeFix = '''
You are an expert debugger. Given code that contains errors and the error message,
provide the corrected version. 

Rules:
1. Return ONLY the corrected code inside a markdown code block with the language specified
2. Briefly explain what was wrong in 1-2 sentences after the code block
3. Preserve the original structure and style as much as possible
'''.trim();

  static const String generalAssistant = '''
You are Mobile Agent, an AI coding assistant integrated into a mobile code editor.
You help with:
- Writing and editing code
- Debugging and error fixing
- Explaining concepts and code
- General programming questions

Be concise, helpful, and code-focused. When providing code, always use markdown code blocks
with the correct language specified.
'''.trim();
}

/// Service for interacting with cloud LLM APIs.
///
/// Supports multiple providers (OpenAI, Claude, Gemini, and custom
/// OpenAI-compatible endpoints) with a unified interface for:
/// - Code completion
/// - Code explanation
/// - Error fixing
/// - General chat
/// - Streaming chat responses
///
/// All methods require an [ApiConfig] that specifies the provider,
/// model, API key, and endpoint URL.
///
/// ```dart
/// final llm = LLMService(api);
/// final result = await llm.explainCode(myCode, 'dart', config);
/// ```
class LLMService {
  final ApiService _api;

  /// Create an LLM service backed by an [ApiService] HTTP client.
  LLMService(this._api);

  // ─── Code Completion ───────────────────────────────────────────────

  /// Request a code completion for the given partial code.
  ///
  /// Returns the completion text (code only, no markdown wrapper).
  ///
  /// [code]     The partial code to complete.
  /// [language] The programming language (e.g., 'dart', 'python').
  /// [config]   The API configuration (provider, model, key).
  Future<String> completeCode(
    String code,
    String language,
    ApiConfig config,
  ) async {
    final prompt = '''Language: $language\n\nCode:\n```$language\n$code\n```\n\nComplete the code.'''.trim();

    return _sendSingleMessage(
      prompt: prompt,
      systemPrompt: SystemPrompts.codeCompletion,
      config: config,
      maxTokens: config.maxTokens ?? 2048,
      temperature: config.temperature ?? 0.2,
    );
  }

  // ─── Code Explanation ──────────────────────────────────────────────

  /// Request an explanation of the given code.
  ///
  /// Returns a markdown-formatted explanation.
  ///
  /// [code]     The code to explain.
  /// [language] The programming language.
  /// [config]   The API configuration.
  Future<String> explainCode(
    String code,
    String language,
    ApiConfig config,
  ) async {
    final prompt = '''Language: $language\n\nCode:\n```$language\n$code\n```\n\nExplain this code.'''.trim();

    return _sendSingleMessage(
      prompt: prompt,
      systemPrompt: SystemPrompts.codeExplanation,
      config: config,
      maxTokens: config.maxTokens ?? 2048,
      temperature: config.temperature ?? 0.3,
    );
  }

  // ─── Code Error Fixing ─────────────────────────────────────────────

  /// Request a fix for code that produces errors.
  ///
  /// Returns the corrected code wrapped in a markdown code block,
  /// followed by a brief explanation.
  ///
  /// [code]     The code with errors.
  /// [error]    The error message or stack trace.
  /// [language] The programming language.
  /// [config]   The API configuration.
  Future<String> fixCode(
    String code,
    String error,
    String language,
    ApiConfig config,
  ) async {
    final prompt = '''Language: $language\n\nCode:\n```$language\n$code\n```\n\nError:\n```\n$error\n```\n\nFix the code.'''.trim();

    return _sendSingleMessage(
      prompt: prompt,
      systemPrompt: SystemPrompts.codeFix,
      config: config,
      maxTokens: config.maxTokens ?? 2048,
      temperature: config.temperature ?? 0.2,
    );
  }

  // ─── General Chat ──────────────────────────────────────────────────

  /// Send a general chat message with conversation history.
  ///
  /// Returns the AI assistant's response text.
  ///
  /// [message] The current user message.
  /// [history] Previous messages in the conversation.
  /// [config]  The API configuration.
  Future<String> chat(
    String message,
    List<ChatMessage> history,
    ApiConfig config, {
    String? contextPrompt,
  }) async {
    final effectiveSystemPrompt = contextPrompt != null
        ? '${SystemPrompts.generalAssistant}\n\n$contextPrompt'
        : SystemPrompts.generalAssistant;

    return _sendConversation(
      userMessage: message,
      history: history,
      systemPrompt: effectiveSystemPrompt,
      config: config,
      maxTokens: config.maxTokens ?? 4096,
      temperature: config.temperature ?? 0.7,
    );
  }

  // ─── Streaming Chat ────────────────────────────────────────────────

  /// Stream a chat response in real-time.
  ///
  /// Yields partial response chunks as they arrive from the API.
  /// Useful for showing AI responses as they are generated.
  ///
  /// ```dart
  /// final stream = llm.chatStream('Hello', [], config);
  /// await for (final chunk in stream) {
  ///   print(chunk); // Append to UI in real-time
  /// }
  /// ```
  Stream<String> chatStream(
    String message,
    List<ChatMessage> history,
    ApiConfig config, {
    String? contextPrompt,
  }) {
    final effectiveSystemPrompt = contextPrompt != null
        ? '${SystemPrompts.generalAssistant}\n\n$contextPrompt'
        : SystemPrompts.generalAssistant;

    final messages = _buildMessages(
      systemPrompt: effectiveSystemPrompt,
      history: history,
      userMessage: message,
      provider: config.provider,
    );

    final body = _buildRequestBody(
      config: config,
      messages: messages,
      maxTokens: config.maxTokens ?? 4096,
      temperature: config.temperature ?? 0.7,
      stream: true,
    );

    if (config.isGemini) {
      return _streamGemini(message, history, config);
    }

    return _streamOpenAiCompatible(config, body);
  }

  // ─── Provider-Specific Streaming ───────────────────────────────────

  /// Stream from OpenAI-compatible endpoints (SSE).
  Stream<String> _streamOpenAiCompatible(
    ApiConfig config,
    Map<String, dynamic> body,
  ) async* {
    _api.setBaseUrl(config.baseUrl);
    _api.setAuthHeader(config.apiKey);

    final endpoint = _getChatEndpoint(config);

    try {
      await for (final line in _api.sseStream(endpoint, data: body)) {
        if (line.isEmpty) continue;
        if (line == 'data: [DONE]') break;

        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6);
          try {
            final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
            final content = _extractStreamContent(jsonData, config.provider);
            if (content != null && content.isNotEmpty) {
              yield content;
            }
          } catch (e) {
            // Skip malformed JSON lines in the stream.
            debugPrint('[LLMService] Skipped malformed stream line: $e');
          }
        }
      }
    } on ApiException catch (e) {
      throw LLMException(
        message: 'Streaming error: ${e.message}',
        provider: config.provider,
        model: config.model,
        originalError: e,
      );
    } finally {
      // Don't clear headers — may interfere with concurrent requests.
    }
  }

  /// Stream from Google Gemini API.
  Stream<String> _streamGemini(
    String message,
    List<ChatMessage> history,
    ApiConfig config,
  ) async* {
    // Build Gemini-specific request.
    final contents = <Map<String, dynamic>>[];

    for (final msg in history.where((m) => !m.isStreaming)) {
      contents.add({
        'role': msg.role == MessageRole.user ? 'user' : 'model',
        'parts': [{'text': msg.content}],
      });
    }

    contents.add({
      'role': 'user',
      'parts': [{'text': message}],
    });

    final body = {
      'contents': contents,
      'generationConfig': {
        'maxOutputTokens': config.maxTokens ?? 4096,
        'temperature': config.temperature ?? 0.7,
      },
    };

    final url = '${config.baseUrl}/${config.model}:streamGenerateContent?key=${config.apiKey}';
    _api.setBaseUrl(''); // Use full URL directly.

    try {
      await for (final line in _api.sseStream(url, data: body)) {
        if (line.isEmpty) continue;

        try {
          // Gemini streaming uses JSON objects separated by commas.
          final cleanLine = line.startsWith(',') ? line.substring(1) : line;
          if (cleanLine.trim().isEmpty) continue;

          final jsonData = jsonDecode(cleanLine) as Map<String, dynamic>;
          final candidates = jsonData['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.isNotEmpty) {
                yield text;
              }
            }
          }
        } catch (e) {
          debugPrint('[LLMService] Skipped malformed Gemini line: $e');
        }
      }
    } on ApiException catch (e) {
      throw LLMException(
        message: 'Gemini streaming error: ${e.message}',
        provider: 'gemini',
        model: config.model,
        originalError: e,
      );
    }
  }

  // ─── Unified Single-Message Sender ─────────────────────────────────

  /// Send a single-turn message and return the complete response.
  Future<String> _sendSingleMessage({
    required String prompt,
    required String systemPrompt,
    required ApiConfig config,
    required int maxTokens,
    required double temperature,
  }) async {
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    return _sendRequest(
      config: config,
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  /// Send a multi-turn conversation and return the response.
  Future<String> _sendConversation({
    required String userMessage,
    required List<ChatMessage> history,
    required String systemPrompt,
    required ApiConfig config,
    required int maxTokens,
    required double temperature,
  }) async {
    final messages = _buildMessages(
      systemPrompt: systemPrompt,
      history: history,
      userMessage: userMessage,
      provider: config.provider,
    );

    return _sendRequest(
      config: config,
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  // ─── Core Request Builder ──────────────────────────────────────────

  /// Build the messages array for the API request.
  ///
  /// Handles provider-specific message formatting:
  /// - OpenAI/custom: standard role/content format.
  /// - Claude: requires 'system' as a top-level parameter (not in messages).
  List<Map<String, dynamic>> _buildMessages({
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userMessage,
    required String provider,
  }) {
    final messages = <Map<String, dynamic>>[];

    if (provider != 'claude') {
      // OpenAI/Gemini/custom: system message in the array.
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    // Add conversation history (last 20 messages to stay within token limits).
    final recentHistory = history.length > 20 ? history.sublist(history.length - 20) : history;

    for (final msg in recentHistory) {
      if (msg.role == MessageRole.system) continue; // Skip existing system messages.

      final role = msg.role == MessageRole.user ? 'user' : 'assistant';

      // Include code context if present.
      if (msg.codeContext != null && msg.codeContext!.isNotEmpty) {
        final lang = msg.language ?? 'code';
        messages.add({
          'role': role,
          'content': '${msg.content}\n\n```$lang\n${msg.codeContext}\n```',
        });
      } else {
        messages.add({'role': role, 'content': msg.content});
      }
    }

    // Add current user message.
    messages.add({'role': 'user', 'content': userMessage});

    return messages;
  }

  /// Build the API request body.
  Map<String, dynamic> _buildRequestBody({
    required ApiConfig config,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
    bool stream = false,
  }) {
    if (config.isClaude) {
      // Anthropic format.
      return {
        'model': config.model,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'stream': stream,
        'messages': messages.where((m) => m['role'] != 'system').toList(),
      };
    }

    if (config.isGemini) {
      // Gemini format is handled separately in _streamGemini.
      // For non-streaming, convert to Gemini format.
      final contents = <Map<String, dynamic>>[];

      for (final msg in messages) {
        final role = msg['role'] == 'user' ? 'user' : 'model';
        contents.add({
          'role': role,
          'parts': [{'text': msg['content']}],
        });
      }

      return {
        'contents': contents,
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          'temperature': temperature,
        },
      };
    }

    // OpenAI / custom OpenAI-compatible format.
    return {
      'model': config.model,
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': stream,
    };
  }

  /// Get the chat completions endpoint for the provider.
  String _getChatEndpoint(ApiConfig config) {
    if (config.isClaude) {
      return '/v1/messages';
    }
    // OpenAI-compatible (includes custom).
    return '/v1/chat/completions';
  }

  /// Send the HTTP request and extract the response text.
  Future<String> _sendRequest({
    required ApiConfig config,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
  }) async {
    _api.setBaseUrl(config.baseUrl);

    if (config.isClaude) {
      _api.setHeader('x-api-key', config.apiKey);
      _api.setHeader('anthropic-version', '2023-06-01');
    } else if (config.isGemini) {
      // Gemini uses query param for key; handled below.
    } else {
      _api.setAuthHeader(config.apiKey);
    }

    try {
      if (config.isGemini) {
        return await _sendGeminiRequest(config, messages, maxTokens, temperature);
      }

      final body = _buildRequestBody(
        config: config,
        messages: messages,
        maxTokens: maxTokens,
        temperature: temperature,
      );

      final endpoint = _getChatEndpoint(config);
      final response = await _api.post(endpoint, data: body);

      return _extractContent(response.data, config.provider);
    } on ApiException catch (e) {
      throw LLMException(
        message: e.message,
        provider: config.provider,
        model: config.model,
        originalError: e,
      );
    } catch (e) {
      throw LLMException(
        message: 'Unexpected error: $e',
        provider: config.provider,
        model: config.model,
        originalError: e,
      );
    }
  }

  /// Send a request to the Gemini API.
  Future<String> _sendGeminiRequest(
    ApiConfig config,
    List<Map<String, dynamic>> messages,
    int maxTokens,
    double temperature,
  ) async {
    final contents = <Map<String, dynamic>>[];

    for (final msg in messages) {
      final role = msg['role'] == 'user' ? 'user' : 'model';
      contents.add({
        'role': role,
        'parts': [{'text': msg['content']}],
      });
    }

    final body = {
      'contents': contents,
      'generationConfig': {
        'maxOutputTokens': maxTokens,
        'temperature': temperature,
      },
    };

    final url = '/${config.model}:generateContent?key=${config.apiKey}';
    final response = await _api.post(url, data: body);

    final candidates = response.data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const LLMException(message: 'No response from Gemini API');
    }

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw const LLMException(message: 'Empty response from Gemini API');
    }

    return parts[0]['text'] as String? ?? '';
  }

  // ─── Response Extraction ───────────────────────────────────────────

  /// Extract content text from a non-streaming API response.
  String _extractContent(dynamic responseData, String provider) {
    try {
      final data = responseData as Map<String, dynamic>;

      if (provider == 'claude') {
        // Anthropic format.
        final content = data['content'] as List<dynamic>?;
        if (content != null && content.isNotEmpty) {
          return content[0]['text'] as String? ?? '';
        }
        return data['completion'] as String? ?? '';
      }

      // OpenAI-compatible format.
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final choice = choices[0] as Map<String, dynamic>;
        final message = choice['message'] as Map<String, dynamic>?;
        if (message != null) {
          return message['content'] as String? ?? '';
        }
        // Fallback for older completions API.
        return choice['text'] as String? ?? '';
      }

      return '';
    } catch (e) {
      debugPrint('[LLMService] Error extracting content: $e');
      debugPrint('[LLMService] Response data: $responseData');
      throw LLMException(
        message: 'Failed to parse API response: $e',
        provider: provider,
        originalError: e,
      );
    }
  }

  /// Extract content delta from a streaming SSE chunk.
  String? _extractStreamContent(Map<String, dynamic> data, String provider) {
    try {
      if (provider == 'claude') {
        // Anthropic streaming format.
        final delta = data['delta'] as Map<String, dynamic>?;
        if (delta != null) {
          return delta['text'] as String?;
        }
        final contentBlock = data['content_block'] as Map<String, dynamic>?;
        if (contentBlock != null) {
          return contentBlock['text'] as String?;
        }
        return null;
      }

      // OpenAI-compatible streaming format.
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;

      final choice = choices[0] as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>?;
      if (delta != null) {
        return delta['content'] as String?;
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
