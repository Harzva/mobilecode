import 'dart:async';
import 'dart:convert';

import 'github_deep_service.dart';
import 'mobile_code_helper_provider.dart';
import 'subscription_usage_service.dart';

class ProviderCredential {
  const ProviderCredential({
    required this.providerId,
    required this.accountLabel,
    required this.location,
    this.secret,
  });

  final String providerId;
  final String accountLabel;
  final String location;
  final String? secret;

  bool get hasSecret => secret != null && secret!.trim().isNotEmpty;

  Map<String, Object?> toRedactedJson() => {
        'providerId': providerId,
        'accountLabel': accountLabel,
        'location': location,
        'secret': hasSecret ? 'redacted' : null,
      };
}

class ModelMessage {
  const ModelMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, Object?> toJson() => {
        'role': role,
        'content': content,
      };
}

class ModelForwardRequest {
  const ModelForwardRequest({
    required this.modelId,
    required this.messages,
    this.providerId,
    this.temperature,
    this.maxTokens,
  });

  final String modelId;
  final List<ModelMessage> messages;
  final String? providerId;
  final double? temperature;
  final int? maxTokens;
}

class ModelForwardChunk {
  const ModelForwardChunk({
    required this.text,
    required this.done,
    required this.providerId,
    required this.modelId,
    this.metadata = const {},
  });

  final String text;
  final bool done;
  final String providerId;
  final String modelId;
  final Map<String, Object?> metadata;
}

class ModelProviderDefinition {
  const ModelProviderDefinition({
    required this.providerId,
    required this.displayName,
    required this.modelIds,
    required this.loginMethod,
    required this.credentialBoundary,
  });

  final String providerId;
  final String displayName;
  final List<String> modelIds;
  final ProviderLoginMethod loginMethod;
  final String credentialBoundary;

  bool supports(String modelId) => modelIds.contains(modelId);
}

abstract class ProviderCredentialResolver {
  Future<ProviderCredential?> resolve(String providerId);
}

class SubscriptionProviderCredentialResolver
    implements ProviderCredentialResolver {
  SubscriptionProviderCredentialResolver({
    required this.subscriptionUsage,
    GitHubDeepService? github,
  }) : github = github ?? GitHubDeepService();

  final SubscriptionUsageService subscriptionUsage;
  final GitHubDeepService github;

  @override
  Future<ProviderCredential?> resolve(String providerId) async {
    if (providerId == SubscriptionProviderKind.copilotGithub.name) {
      await github.initialize();
      final session = github.activeSession;
      if (session != null) {
        return ProviderCredential(
          providerId: providerId,
          accountLabel: '@${session.username}',
          location: 'github_deep_service_secure_storage',
          secret: session.token,
        );
      }
    }

    final credential =
        await subscriptionUsage.readCredentialForProvider(providerId);
    final account = subscriptionUsage.stateFor(providerId).account;
    if (credential == null || account == null) return null;
    return ProviderCredential(
      providerId: providerId,
      accountLabel: account.displayName,
      location: account.credentialLocation,
      secret: credential,
    );
  }
}

abstract class ModelProviderAdapter {
  ModelProviderDefinition get definition;

  bool supports(String modelId) => definition.supports(modelId);

  Stream<ModelForwardChunk> chat({
    required ModelForwardRequest request,
    required ProviderCredential credential,
  });
}

class ModelRouter {
  ModelRouter({
    required ProviderCredentialResolver credentialResolver,
    required List<ModelProviderAdapter> adapters,
  })  : _credentialResolver = credentialResolver,
        _adapters = adapters;

  final ProviderCredentialResolver _credentialResolver;
  final List<ModelProviderAdapter> _adapters;

  static List<ModelProviderDefinition> defaultDefinitions = const [
    ModelProviderDefinition(
      providerId: 'copilotGithub',
      displayName: 'Copilot / GitHub',
      modelIds: ['copilot-chat', 'copilot-agent'],
      loginMethod: ProviderLoginMethod.githubOAuth,
      credentialBoundary:
          'GitHub OAuth/PAT token from GitHubDeepService secure storage; forwarded transiently to the built-in Helper or provider-native Copilot SDK adapter.',
    ),
    ModelProviderDefinition(
      providerId: 'codexChatGpt',
      displayName: 'Codex / ChatGPT',
      modelIds: ['codex-gpt-5.5', 'codex-gpt-5.5-pro', 'codex-gpt-5.4'],
      loginMethod: ProviderLoginMethod.manualApiKey,
      credentialBoundary:
          'OpenAI API key is supported now; ChatGPT subscription sign-in waits for an official third-party handoff.',
    ),
    ModelProviderDefinition(
      providerId: 'antigravityGoogle',
      displayName: 'Antigravity / Google',
      modelIds: ['gemini-pro', 'gemini-flash'],
      loginMethod: ProviderLoginMethod.manualApiKey,
      credentialBoundary:
          'Gemini API key is supported now; Google OAuth requires app client and consent configuration.',
    ),
    ModelProviderDefinition(
      providerId: 'claude',
      displayName: 'Claude',
      modelIds: ['claude-sonnet', 'claude-opus'],
      loginMethod: ProviderLoginMethod.manualApiKey,
      credentialBoundary:
          'Anthropic API key or Workload Identity Federation only; consumer cookie/session login is not supported.',
    ),
  ];

  Stream<ModelForwardChunk> chat(ModelForwardRequest request) async* {
    final adapter = _adapterFor(request);
    final credential =
        await _credentialResolver.resolve(adapter.definition.providerId);
    if (credential == null || !credential.hasSecret) {
      throw ModelRouterException(
        failureKind: 'credential_missing',
        message:
            'No credential is connected for ${adapter.definition.displayName}.',
      );
    }
    yield* adapter.chat(request: request, credential: credential);
  }

  ModelProviderAdapter _adapterFor(ModelForwardRequest request) {
    for (final adapter in _adapters) {
      final providerMatches = request.providerId == null ||
          request.providerId == adapter.definition.providerId;
      if (providerMatches && adapter.supports(request.modelId)) {
        return adapter;
      }
    }
    throw ModelRouterException(
      failureKind: 'model_not_supported',
      message: 'No provider adapter supports model ${request.modelId}.',
    );
  }
}

class CopilotBridgeModelProviderAdapter implements ModelProviderAdapter {
  CopilotBridgeModelProviderAdapter({
    required this.helper,
    ModelProviderDefinition? definition,
  }) : _definition = definition ??
            ModelRouter.defaultDefinitions.firstWhere(
              (definition) => definition.providerId == 'copilotGithub',
            );

  final MobileCodeHelperProvider helper;
  final ModelProviderDefinition _definition;

  @override
  ModelProviderDefinition get definition => _definition;

  @override
  bool supports(String modelId) => definition.supports(modelId);

  @override
  Stream<ModelForwardChunk> chat({
    required ModelForwardRequest request,
    required ProviderCredential credential,
  }) async* {
    final response = await helper.runTypedTask(
      taskKind: 'copilot_chat',
      payload: {
        'path': '.',
        'timeoutMs': 120000,
        'maxOutputBytes': 65536,
        'args': {
          'modelId': request.modelId,
          'messagesJson': jsonEncode(
              request.messages.map((message) => message.toJson()).toList()),
          'githubToken': credential.secret,
          if (request.temperature != null) 'temperature': request.temperature,
          if (request.maxTokens != null) 'maxTokens': request.maxTokens,
        },
      },
    );
    if (response['success'] != true) {
      throw ModelRouterException(
        failureKind: response['failureKind']?.toString() ?? 'provider_failed',
        message: response['stderr']?.toString().trim().isNotEmpty == true
            ? response['stderr'].toString()
            : response['error']?.toString() ??
                'Copilot bridge task failed before returning text.',
      );
    }
    final text = _extractText(response['stdout']);
    yield ModelForwardChunk(
      text: text,
      done: true,
      providerId: definition.providerId,
      modelId: request.modelId,
      metadata: {
        'taskId': response['taskId'],
        'taskKind': response['taskKind'],
        'credential': credential.toRedactedJson(),
      },
    );
  }

  String _extractText(Object? stdout) {
    final raw = stdout?.toString() ?? '';
    if (raw.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded['text']?.toString() ??
            decoded['content']?.toString() ??
            raw;
      }
    } on Object {
      // Plain stdout is allowed for built-in helper bridge prototypes.
    }
    return raw;
  }
}

class ModelRouterException implements Exception {
  const ModelRouterException({
    required this.failureKind,
    required this.message,
  });

  final String failureKind;
  final String message;

  @override
  String toString() => 'ModelRouterException($failureKind): $message';
}
