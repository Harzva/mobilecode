import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum ProviderLoginMethod {
  officialBrowser,
  githubOAuth,
  googleAccount,
  manualApiKey,
  manualAccessToken,
}

enum SubscriptionRefreshState { idle, refreshing, success, error }

enum SubscriptionProviderKind {
  claude,
  copilotGithub,
  antigravityGoogle,
  codexChatGpt,
}

@immutable
class SubscriptionProvider {
  const SubscriptionProvider({
    required this.kind,
    required this.name,
    required this.accountLabel,
    required this.loginMethods,
    required this.recoveryHint,
    required this.colorValue,
  });

  final SubscriptionProviderKind kind;
  final String name;
  final String accountLabel;
  final List<ProviderLoginMethod> loginMethods;
  final String recoveryHint;
  final int colorValue;

  String get id => kind.name;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'accountLabel': accountLabel,
        'loginMethods': loginMethods.map((method) => method.name).toList(),
        'recoveryHint': recoveryHint,
        'colorValue': colorValue,
      };
}

@immutable
class SubscriptionAccount {
  const SubscriptionAccount({
    required this.providerId,
    required this.displayName,
    required this.loginMethod,
    required this.connected,
    this.lastLoginAt,
    this.failureKind,
    this.recoveryHint,
    this.credentialLocation = 'stored_in_secure_storage',
  });

  final String providerId;
  final String displayName;
  final ProviderLoginMethod loginMethod;
  final bool connected;
  final DateTime? lastLoginAt;
  final String? failureKind;
  final String? recoveryHint;
  final String credentialLocation;

  Map<String, Object?> toRedactedJson() => {
        'providerId': providerId,
        'displayName': displayName,
        'loginMethod': loginMethod.name,
        'connected': connected,
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'failureKind': failureKind,
        'recoveryHint': recoveryHint,
        'credential': connected ? credentialLocation : null,
      };
}

@immutable
class UsageQuota {
  const UsageQuota({
    required this.providerId,
    required this.title,
    required this.usagePercent,
    required this.timePercent,
    required this.resetAt,
    required this.mock,
    required this.refreshState,
    this.errorMessage,
    this.lastRefreshedAt,
  });

  final String providerId;
  final String title;
  final double usagePercent;
  final double timePercent;
  final DateTime resetAt;
  final bool mock;
  final SubscriptionRefreshState refreshState;
  final String? errorMessage;
  final DateTime? lastRefreshedAt;

  UsageQuota copyWith({
    double? usagePercent,
    double? timePercent,
    DateTime? resetAt,
    bool? mock,
    SubscriptionRefreshState? refreshState,
    String? errorMessage,
    DateTime? lastRefreshedAt,
  }) {
    return UsageQuota(
      providerId: providerId,
      title: title,
      usagePercent: usagePercent ?? this.usagePercent,
      timePercent: timePercent ?? this.timePercent,
      resetAt: resetAt ?? this.resetAt,
      mock: mock ?? this.mock,
      refreshState: refreshState ?? this.refreshState,
      errorMessage: errorMessage,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'providerId': providerId,
        'title': title,
        'usagePercent': usagePercent,
        'timePercent': timePercent,
        'resetAt': resetAt.toIso8601String(),
        'mock': mock,
        'refreshState': refreshState.name,
        'errorMessage': errorMessage,
        'lastRefreshedAt': lastRefreshedAt?.toIso8601String(),
      };
}

@immutable
class SubscriptionProviderState {
  const SubscriptionProviderState({
    required this.provider,
    required this.account,
    required this.quotas,
  });

  final SubscriptionProvider provider;
  final SubscriptionAccount? account;
  final List<UsageQuota> quotas;

  bool get connected => account?.connected == true;
  bool get hasError =>
      (account?.failureKind != null &&
          account?.failureKind != 'official_flow_not_connected_locally') ||
      quotas
          .any((quota) => quota.refreshState == SubscriptionRefreshState.error);

  Map<String, Object?> toRedactedJson() => {
        'provider': provider.toJson(),
        'account': account?.toRedactedJson(),
        'quotas': quotas.map((quota) => quota.toJson()).toList(),
      };
}

@immutable
class SubscriptionLoginValidation {
  const SubscriptionLoginValidation({
    required this.success,
    this.accountLabel,
    this.failureKind,
    this.recoveryHint,
  });

  final bool success;
  final String? accountLabel;
  final String? failureKind;
  final String? recoveryHint;
}

abstract class SubscriptionLoginAdapter {
  Future<SubscriptionLoginValidation> validateCredential({
    required SubscriptionProvider provider,
    required String credential,
    required ProviderLoginMethod method,
  });
}

class GitHubSubscriptionLoginAdapter implements SubscriptionLoginAdapter {
  GitHubSubscriptionLoginAdapter({
    HttpClient? httpClient,
    Uri? userEndpoint,
  })  : _httpClient = httpClient ?? HttpClient(),
        _userEndpoint =
            userEndpoint ?? Uri.parse('https://api.github.com/user');

  final HttpClient _httpClient;
  final Uri _userEndpoint;

  @override
  Future<SubscriptionLoginValidation> validateCredential({
    required SubscriptionProvider provider,
    required String credential,
    required ProviderLoginMethod method,
  }) async {
    if (method != ProviderLoginMethod.manualAccessToken) {
      return SubscriptionLoginValidation(
        success: false,
        failureKind: 'unsupported_login_method',
        recoveryHint:
            'Use a GitHub personal access token here, or connect GitHub through the dedicated GitHub screen.',
      );
    }

    try {
      final request = await _httpClient.getUrl(_userEndpoint);
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $credential');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'MobileCode Usage Hub');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const SubscriptionLoginValidation(
          success: false,
          failureKind: 'github_token_validation_failed',
          recoveryHint:
              'GitHub rejected this token. Create a valid token with user read access, then retry. The token was not saved.',
        );
      }
      final payload = jsonDecode(body);
      final login = payload is Map ? payload['login']?.toString() : null;
      return SubscriptionLoginValidation(
        success: true,
        accountLabel:
            login == null || login.isEmpty ? provider.accountLabel : '@$login',
      );
    } on Object {
      return const SubscriptionLoginValidation(
        success: false,
        failureKind: 'github_token_validation_unreachable',
        recoveryHint:
            'Could not validate this token with GitHub right now. Check network access and retry. The token was not saved.',
      );
    }
  }
}

class OpenAiSubscriptionLoginAdapter implements SubscriptionLoginAdapter {
  OpenAiSubscriptionLoginAdapter({
    HttpClient? httpClient,
    Uri? modelsEndpoint,
  })  : _httpClient = httpClient ?? HttpClient(),
        _modelsEndpoint =
            modelsEndpoint ?? Uri.parse('https://api.openai.com/v1/models');

  final HttpClient _httpClient;
  final Uri _modelsEndpoint;

  @override
  Future<SubscriptionLoginValidation> validateCredential({
    required SubscriptionProvider provider,
    required String credential,
    required ProviderLoginMethod method,
  }) {
    return _validateJsonGet(
      httpClient: _httpClient,
      endpoint: _modelsEndpoint,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $credential',
        HttpHeaders.acceptHeader: 'application/json',
      },
      accountLabel: 'OpenAI API key',
      invalidFailureKind: 'openai_key_validation_failed',
      unreachableFailureKind: 'openai_key_validation_unreachable',
      invalidRecoveryHint:
          'OpenAI rejected this API key. Create a valid API key, then retry. The key was not saved.',
      unreachableRecoveryHint:
          'Could not validate this API key with OpenAI right now. Check network access and retry. The key was not saved.',
    );
  }
}

class AnthropicSubscriptionLoginAdapter implements SubscriptionLoginAdapter {
  AnthropicSubscriptionLoginAdapter({
    HttpClient? httpClient,
    Uri? modelsEndpoint,
  })  : _httpClient = httpClient ?? HttpClient(),
        _modelsEndpoint =
            modelsEndpoint ?? Uri.parse('https://api.anthropic.com/v1/models');

  final HttpClient _httpClient;
  final Uri _modelsEndpoint;

  @override
  Future<SubscriptionLoginValidation> validateCredential({
    required SubscriptionProvider provider,
    required String credential,
    required ProviderLoginMethod method,
  }) {
    return _validateJsonGet(
      httpClient: _httpClient,
      endpoint: _modelsEndpoint,
      headers: {
        'x-api-key': credential,
        'anthropic-version': '2023-06-01',
        HttpHeaders.acceptHeader: 'application/json',
      },
      accountLabel: 'Claude API key',
      invalidFailureKind: 'anthropic_key_validation_failed',
      unreachableFailureKind: 'anthropic_key_validation_unreachable',
      invalidRecoveryHint:
          'Anthropic rejected this API key. Create a valid Claude API key, then retry. The key was not saved.',
      unreachableRecoveryHint:
          'Could not validate this API key with Anthropic right now. Check network access and retry. The key was not saved.',
    );
  }
}

class GeminiSubscriptionLoginAdapter implements SubscriptionLoginAdapter {
  GeminiSubscriptionLoginAdapter({
    HttpClient? httpClient,
    Uri? modelsEndpoint,
  })  : _httpClient = httpClient ?? HttpClient(),
        _modelsEndpoint = modelsEndpoint ??
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models');

  final HttpClient _httpClient;
  final Uri _modelsEndpoint;

  @override
  Future<SubscriptionLoginValidation> validateCredential({
    required SubscriptionProvider provider,
    required String credential,
    required ProviderLoginMethod method,
  }) {
    final endpoint = _modelsEndpoint.replace(
      queryParameters: {
        ..._modelsEndpoint.queryParameters,
        'key': credential,
      },
    );
    return _validateJsonGet(
      httpClient: _httpClient,
      endpoint: endpoint,
      headers: const {HttpHeaders.acceptHeader: 'application/json'},
      accountLabel: 'Gemini API key',
      invalidFailureKind: 'gemini_key_validation_failed',
      unreachableFailureKind: 'gemini_key_validation_unreachable',
      invalidRecoveryHint:
          'Gemini API rejected this key. Create a valid Google AI Studio API key, then retry. The key was not saved.',
      unreachableRecoveryHint:
          'Could not validate this key with Gemini API right now. Check network access and retry. The key was not saved.',
    );
  }
}

Future<SubscriptionLoginValidation> _validateJsonGet({
  required HttpClient httpClient,
  required Uri endpoint,
  required Map<String, String> headers,
  required String accountLabel,
  required String invalidFailureKind,
  required String unreachableFailureKind,
  required String invalidRecoveryHint,
  required String unreachableRecoveryHint,
}) async {
  try {
    final request = await httpClient.getUrl(endpoint);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return SubscriptionLoginValidation(
        success: false,
        failureKind: invalidFailureKind,
        recoveryHint: invalidRecoveryHint,
      );
    }
    return SubscriptionLoginValidation(
      success: true,
      accountLabel: accountLabel,
    );
  } on Object {
    return SubscriptionLoginValidation(
      success: false,
      failureKind: unreachableFailureKind,
      recoveryHint: unreachableRecoveryHint,
    );
  }
}

abstract class SubscriptionCredentialVault {
  Future<void> writeCredential({
    required String providerId,
    required String accountId,
    required String credential,
  });

  Future<String?> readCredential({
    required String providerId,
    required String accountId,
  });

  Future<void> deleteCredential({
    required String providerId,
    required String accountId,
  });
}

class SecureSubscriptionCredentialVault implements SubscriptionCredentialVault {
  SecureSubscriptionCredentialVault({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String providerId, String accountId) =>
      'mobilecode.subscription.$providerId.$accountId.credential';

  @override
  Future<void> writeCredential({
    required String providerId,
    required String accountId,
    required String credential,
  }) {
    return _storage.write(
      key: _key(providerId, accountId),
      value: credential,
    );
  }

  @override
  Future<String?> readCredential({
    required String providerId,
    required String accountId,
  }) {
    return _storage.read(key: _key(providerId, accountId));
  }

  @override
  Future<void> deleteCredential({
    required String providerId,
    required String accountId,
  }) {
    return _storage.delete(key: _key(providerId, accountId));
  }
}

class SubscriptionUsageService extends ChangeNotifier {
  SubscriptionUsageService({
    SubscriptionCredentialVault? credentialVault,
    Map<String, SubscriptionLoginAdapter>? loginAdapters,
    DateTime Function()? clock,
  })  : _credentialVault =
            credentialVault ?? SecureSubscriptionCredentialVault(),
        _loginAdapters = loginAdapters ?? _defaultLoginAdapters(),
        _clock = clock ?? DateTime.now {
    _states = _defaultStates(_clock());
  }

  final SubscriptionCredentialVault _credentialVault;
  final Map<String, SubscriptionLoginAdapter> _loginAdapters;
  final DateTime Function() _clock;
  late List<SubscriptionProviderState> _states;

  static final SubscriptionUsageService instance = SubscriptionUsageService();

  List<SubscriptionProviderState> get states => List.unmodifiable(_states);

  SubscriptionProviderState stateFor(String providerId) {
    return _states.firstWhere((state) => state.provider.id == providerId);
  }

  Future<String?> readCredentialForProvider(String providerId) {
    return _credentialVault.readCredential(
      providerId: providerId,
      accountId: _accountId(providerId),
    );
  }

  Future<void> connectManualCredential({
    required String providerId,
    required String accountLabel,
    required String credential,
    ProviderLoginMethod method = ProviderLoginMethod.manualApiKey,
  }) async {
    final trimmedCredential = credential.trim();
    if (trimmedCredential.isEmpty) {
      throw ArgumentError.value(
          providerId, 'providerId', 'Credential is empty');
    }
    final accountId = _accountId(providerId);
    final state = stateFor(providerId);
    final adapter = _loginAdapters[providerId];
    String displayName = accountLabel.trim().isEmpty
        ? state.provider.accountLabel
        : accountLabel.trim();
    if (adapter != null) {
      final validation = await adapter.validateCredential(
        provider: state.provider,
        credential: trimmedCredential,
        method: method,
      );
      if (!validation.success) {
        _replaceState(
          providerId,
          (state) => SubscriptionProviderState(
            provider: state.provider,
            account: SubscriptionAccount(
              providerId: providerId,
              displayName: displayName,
              loginMethod: method,
              connected: false,
              failureKind:
                  validation.failureKind ?? 'credential_validation_failed',
              recoveryHint:
                  validation.recoveryHint ?? state.provider.recoveryHint,
            ),
            quotas: state.quotas
                .map((quota) => quota.copyWith(
                      refreshState: SubscriptionRefreshState.error,
                      errorMessage:
                          'Credential validation failed. No credential was saved.',
                    ))
                .toList(growable: false),
          ),
        );
        return;
      }
      displayName = validation.accountLabel?.trim().isEmpty == false
          ? validation.accountLabel!.trim()
          : displayName;
    }

    await _credentialVault.writeCredential(
      providerId: providerId,
      accountId: accountId,
      credential: trimmedCredential,
    );
    _replaceState(
      providerId,
      (state) => SubscriptionProviderState(
        provider: state.provider,
        account: SubscriptionAccount(
          providerId: providerId,
          displayName: displayName,
          loginMethod: method,
          connected: true,
          lastLoginAt: _clock(),
          recoveryHint: state.provider.recoveryHint,
        ),
        quotas: state.quotas
            .map((quota) => quota.copyWith(
                  mock: true,
                  refreshState: SubscriptionRefreshState.success,
                  lastRefreshedAt: _clock(),
                ))
            .toList(growable: false),
      ),
    );
  }

  Future<void> connectExistingProviderAccount({
    required String providerId,
    required String displayName,
    required ProviderLoginMethod loginMethod,
    DateTime? authenticatedAt,
    String credentialLocation = 'provider_secure_storage',
  }) async {
    _replaceState(
      providerId,
      (state) => SubscriptionProviderState(
        provider: state.provider,
        account: SubscriptionAccount(
          providerId: providerId,
          displayName: displayName.trim().isEmpty
              ? state.provider.accountLabel
              : displayName.trim(),
          loginMethod: loginMethod,
          connected: true,
          lastLoginAt: authenticatedAt ?? _clock(),
          recoveryHint: state.provider.recoveryHint,
          credentialLocation: credentialLocation,
        ),
        quotas: state.quotas
            .map((quota) => quota.copyWith(
                  refreshState: SubscriptionRefreshState.success,
                  lastRefreshedAt: _clock(),
                  mock: true,
                ))
            .toList(growable: false),
      ),
    );
  }

  Future<void> planOfficialLogin(String providerId) async {
    _replaceState(
      providerId,
      (state) => SubscriptionProviderState(
        provider: state.provider,
        account: SubscriptionAccount(
          providerId: providerId,
          displayName: state.provider.accountLabel,
          loginMethod: state.provider.loginMethods.first,
          connected: false,
          failureKind: 'official_flow_not_connected_locally',
          recoveryHint: state.provider.recoveryHint,
        ),
        quotas: state.quotas
            .map((quota) => quota.copyWith(
                  refreshState: SubscriptionRefreshState.success,
                  errorMessage: null,
                ))
            .toList(growable: false),
      ),
    );
  }

  Future<void> refreshMockUsage(String providerId) async {
    _replaceState(
      providerId,
      (state) => SubscriptionProviderState(
        provider: state.provider,
        account: state.account,
        quotas: state.quotas
            .map((quota) => quota.copyWith(
                refreshState: SubscriptionRefreshState.refreshing))
            .toList(growable: false),
      ),
      notify: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final seed = providerId.codeUnits.fold<int>(0, (sum, code) => sum + code);
    final random = Random(seed + _clock().minute);
    _replaceState(
      providerId,
      (state) => SubscriptionProviderState(
        provider: state.provider,
        account: state.account,
        quotas: [
          for (final quota in state.quotas)
            quota.copyWith(
              usagePercent: (0.18 + random.nextDouble() * 0.62).clamp(0, 1),
              timePercent: (0.10 + random.nextDouble() * 0.78).clamp(0, 1),
              refreshState: SubscriptionRefreshState.success,
              mock: true,
              errorMessage: null,
              lastRefreshedAt: _clock(),
            ),
        ],
      ),
    );
  }

  Future<void> logout(String providerId) async {
    await _credentialVault.deleteCredential(
      providerId: providerId,
      accountId: _accountId(providerId),
    );
    _replaceState(
      providerId,
      (state) => SubscriptionProviderState(
        provider: state.provider,
        account: null,
        quotas: state.quotas
            .map((quota) => quota.copyWith(
                  refreshState: SubscriptionRefreshState.idle,
                  errorMessage: null,
                  lastRefreshedAt: null,
                  mock: true,
                ))
            .toList(growable: false),
      ),
    );
  }

  Map<String, Object?> redactedSnapshot() => {
        'providers': _states.map((state) => state.toRedactedJson()).toList(),
      };

  void _replaceState(
    String providerId,
    SubscriptionProviderState Function(SubscriptionProviderState state)
        update, {
    bool notify = true,
  }) {
    _states = [
      for (final state in _states)
        if (state.provider.id == providerId) update(state) else state,
    ];
    if (notify) notifyListeners();
  }

  String _accountId(String providerId) => '$providerId.default';
}

Map<String, SubscriptionLoginAdapter> _defaultLoginAdapters() => {
      SubscriptionProviderKind.claude.name: AnthropicSubscriptionLoginAdapter(),
      SubscriptionProviderKind.copilotGithub.name:
          GitHubSubscriptionLoginAdapter(),
      SubscriptionProviderKind.antigravityGoogle.name:
          GeminiSubscriptionLoginAdapter(),
      SubscriptionProviderKind.codexChatGpt.name:
          OpenAiSubscriptionLoginAdapter(),
    };

List<SubscriptionProviderState> _defaultStates(DateTime now) {
  const providers = [
    SubscriptionProvider(
      kind: SubscriptionProviderKind.claude,
      name: 'Claude',
      accountLabel: 'Claude account',
      loginMethods: [
        ProviderLoginMethod.officialBrowser,
        ProviderLoginMethod.manualApiKey,
      ],
      recoveryHint:
          'Use Claude official account flow when available, or add a manual API key with explicit consent.',
      colorValue: 0xFFD06445,
    ),
    SubscriptionProvider(
      kind: SubscriptionProviderKind.copilotGithub,
      name: 'Copilot / GitHub',
      accountLabel: 'GitHub account',
      loginMethods: [
        ProviderLoginMethod.githubOAuth,
        ProviderLoginMethod.manualAccessToken,
      ],
      recoveryHint:
          'Connect GitHub through the existing OAuth/token boundary, then refresh Copilot usage.',
      colorValue: 0xFF24292F,
    ),
    SubscriptionProvider(
      kind: SubscriptionProviderKind.antigravityGoogle,
      name: 'Antigravity / Google',
      accountLabel: 'Google account',
      loginMethods: [
        ProviderLoginMethod.googleAccount,
        ProviderLoginMethod.manualApiKey,
      ],
      recoveryHint:
          'Use the system browser Google account flow when provider support is available, or validate a Gemini API key explicitly.',
      colorValue: 0xFF2F7DE1,
    ),
    SubscriptionProvider(
      kind: SubscriptionProviderKind.codexChatGpt,
      name: 'Codex / ChatGPT',
      accountLabel: 'ChatGPT account',
      loginMethods: [
        ProviderLoginMethod.officialBrowser,
        ProviderLoginMethod.manualApiKey,
      ],
      recoveryHint:
          'Use official ChatGPT/Codex login when available; manual API key mode stays explicit and local.',
      colorValue: 0xFF111111,
    ),
  ];

  return [
    for (final provider in providers)
      SubscriptionProviderState(
        provider: provider,
        account: null,
        quotas: _mockQuotas(provider.id, now),
      ),
  ];
}

List<UsageQuota> _mockQuotas(String providerId, DateTime now) {
  switch (providerId) {
    case 'claude':
      return [
        _quota(providerId, '当前会话', 0.35, 0.79,
            now.add(const Duration(hours: 1, minutes: 2))),
        _quota(providerId, '每周限制', 0.65, 0.75,
            now.add(const Duration(days: 2, hours: 4))),
        _quota(providerId, 'Claude Design', 0.25, 0.75,
            now.add(const Duration(days: 2, hours: 4))),
      ];
    case 'copilotGithub':
      return [
        _quota(providerId, '聊天消息', 0.25, 0.78,
            now.add(const Duration(days: 1, hours: 8))),
        _quota(providerId, '内联建议', 0.425, 0.78,
            now.add(const Duration(days: 1, hours: 8))),
        _quota(providerId, '高级请求', 0.68, 0.78,
            now.add(const Duration(days: 1, hours: 8))),
      ];
    case 'antigravityGoogle':
      return [
        _quota(providerId, 'Gemini Pro', 0.60, 0.52,
            now.add(const Duration(hours: 12, minutes: 59))),
        _quota(
            providerId, 'Claude', 0.40, 0.68, now.add(const Duration(days: 2))),
        _quota(providerId, 'Gemini Flash', 0.20, 0.30,
            now.add(const Duration(hours: 3, minutes: 29))),
      ];
    default:
      return [
        _quota(providerId, '当前会话', 0.25, 0.60,
            now.add(const Duration(hours: 1, minutes: 59))),
        _quota(providerId, '每周限制', 0.50, 0.75,
            now.add(const Duration(days: 2, hours: 14))),
        _quota(
            providerId, '每月限制', 0.75, 0.30, now.add(const Duration(days: 20))),
      ];
  }
}

UsageQuota _quota(
  String providerId,
  String title,
  double usagePercent,
  double timePercent,
  DateTime resetAt,
) {
  return UsageQuota(
    providerId: providerId,
    title: title,
    usagePercent: usagePercent,
    timePercent: timePercent,
    resetAt: resetAt,
    mock: true,
    refreshState: SubscriptionRefreshState.idle,
  );
}
