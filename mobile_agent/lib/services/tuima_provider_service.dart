import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'model_provider_preset_service.dart';

enum TuimaConnectionState {
  unavailable,
  serviceReady,
  modelReady,
}

class TuimaHealth {
  const TuimaHealth({
    required this.state,
    required this.version,
    required this.backend,
    required this.activeModel,
    this.failure,
  });

  final TuimaConnectionState state;
  final String version;
  final String backend;
  final String? activeModel;
  final String? failure;

  bool get canInfer => state == TuimaConnectionState.modelReady;

  factory TuimaHealth.unavailable(Object failure) => TuimaHealth(
        state: TuimaConnectionState.unavailable,
        version: '',
        backend: '',
        activeModel: null,
        failure: failure.toString(),
      );
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

class TuimaProviderService {
  TuimaProviderService({
    HttpClient? client,
    Uri? healthUri,
    Uri? chatUri,
  })  : _client = client ?? HttpClient(),
        healthUri = healthUri ?? Uri.parse('http://127.0.0.1:8080/health'),
        chatUri =
            chatUri ?? Uri.parse('http://127.0.0.1:8080/v1/chat/completions');

  final HttpClient _client;
  final Uri healthUri;
  final Uri chatUri;

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
      return TuimaHealth(
        state: modelLoaded
            ? TuimaConnectionState.modelReady
            : TuimaConnectionState.serviceReady,
        version: payload['version']?.toString() ?? '',
        backend: payload['backend']?.toString() ?? '',
        activeModel: payload['active_model']?.toString(),
      );
    } on Object catch (error) {
      return TuimaHealth.unavailable(error);
    }
  }

  Future<String> completeChat({
    required List<Map<String, dynamic>> messages,
    required String model,
    int maxTokens = 1024,
    Duration timeout = const Duration(minutes: 2),
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
      throw HttpException(
        'TuiMa HTTP ${response.statusCode}: ${_compact(body)}',
        uri: chatUri,
      );
    }
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
      throw HttpException(
        'TuiMa HTTP ${response.statusCode}: ${_compact(body)}',
        uri: chatUri,
      );
    }

    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    if (mimeType != 'text/event-stream') {
      final body = await utf8.decodeStream(response).timeout(timeout);
      final answer = _extractAssistantText(body);
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
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${ModelProviderPresetService.tuimaLocalToken}',
    );
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
