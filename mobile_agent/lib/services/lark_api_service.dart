import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'secure_storage_service.dart';

@immutable
class LarkCliParityBlueprint {
  const LarkCliParityBlueprint({
    required this.actionKind,
    required this.cliCommandTemplate,
    required this.mobileNativePath,
    required this.tokenCarrier,
    required this.cliErrorCodes,
    required this.requiredScopes,
  });

  final LarkApiActionKind actionKind;
  final String cliCommandTemplate;
  final String mobileNativePath;
  final String tokenCarrier;
  final String cliErrorCodes;
  final List<String> requiredScopes;

  Map<String, Object?> toJson() {
    return {
      'action': actionKind.name,
      'cliCommandTemplate': cliCommandTemplate,
      'mobileNativePath': mobileNativePath,
      'tokenCarrier': tokenCarrier,
      'cliErrorCodes': cliErrorCodes,
      'requiredScopes': requiredScopes,
    };
  }
}

enum LarkTokenMode {
  managedRelay,
  userAccessToken,
  tenantAccessToken,
  runtimeProvidedToken,
  h5ClientContext,
  devProbeOnly,
}

extension LarkTokenModeLabel on LarkTokenMode {
  String get label {
    return switch (this) {
      LarkTokenMode.managedRelay => 'Managed relay',
      LarkTokenMode.userAccessToken => 'User access token',
      LarkTokenMode.tenantAccessToken => 'Tenant access token',
      LarkTokenMode.runtimeProvidedToken => 'Runtime provided token',
      LarkTokenMode.h5ClientContext => 'H5 client context',
      LarkTokenMode.devProbeOnly => 'Dev probe only',
    };
  }

  String get evidenceName {
    return switch (this) {
      LarkTokenMode.managedRelay => 'managed_relay',
      LarkTokenMode.userAccessToken => 'user_access_token',
      LarkTokenMode.tenantAccessToken => 'tenant_access_token',
      LarkTokenMode.runtimeProvidedToken => 'runtime_provided_token',
      LarkTokenMode.h5ClientContext => 'h5_client_context',
      LarkTokenMode.devProbeOnly => 'dev_probe_only',
    };
  }

  bool get canCallOpenApiDirectly {
    return this == LarkTokenMode.userAccessToken ||
        this == LarkTokenMode.tenantAccessToken ||
        this == LarkTokenMode.runtimeProvidedToken;
  }

  bool get isSecretBearing {
    return this == LarkTokenMode.userAccessToken ||
        this == LarkTokenMode.tenantAccessToken ||
        this == LarkTokenMode.runtimeProvidedToken;
  }
}

enum LarkApiActionKind {
  readiness,
  docxCreate,
  docxAppendBlocks,
  driveUploadSmallFile,
  sheetsAppend,
  bitableBatchCreate,
  wikiListSpaces,
}

extension LarkApiActionKindLabel on LarkApiActionKind {
  String get label {
    return switch (this) {
      LarkApiActionKind.readiness => 'Readiness probe',
      LarkApiActionKind.docxCreate => 'Create Docx report',
      LarkApiActionKind.docxAppendBlocks => 'Append Docx evidence blocks',
      LarkApiActionKind.driveUploadSmallFile => 'Upload Drive evidence file',
      LarkApiActionKind.sheetsAppend => 'Append Sheets metrics row',
      LarkApiActionKind.bitableBatchCreate => 'Create Bitable evidence record',
      LarkApiActionKind.wikiListSpaces => 'List Wiki spaces',
    };
  }

  bool get isWriteAction {
    return switch (this) {
      LarkApiActionKind.readiness => false,
      LarkApiActionKind.wikiListSpaces => false,
      LarkApiActionKind.docxCreate => true,
      LarkApiActionKind.docxAppendBlocks => true,
      LarkApiActionKind.driveUploadSmallFile => true,
      LarkApiActionKind.sheetsAppend => true,
      LarkApiActionKind.bitableBatchCreate => true,
    };
  }
}

enum LarkApiFailureKind {
  none,
  missingToken,
  missingRelay,
  missingScope,
  appScopeNotApplied,
  permissionDenied,
  emptyResult,
  previewOnly,
  transportError,
  apiError,
  eventConsumerNotRunning,
}

extension LarkApiFailureKindLabel on LarkApiFailureKind {
  String get evidenceName {
    return switch (this) {
      LarkApiFailureKind.none => 'none',
      LarkApiFailureKind.missingToken => 'missing_token',
      LarkApiFailureKind.missingRelay => 'missing_relay',
      LarkApiFailureKind.missingScope => 'missing_scope',
      LarkApiFailureKind.appScopeNotApplied => 'app_scope_not_applied',
      LarkApiFailureKind.permissionDenied => 'permission_denied',
      LarkApiFailureKind.emptyResult => 'empty_result',
      LarkApiFailureKind.previewOnly => 'preview_only',
      LarkApiFailureKind.transportError => 'transport_error',
      LarkApiFailureKind.apiError => 'api_error',
      LarkApiFailureKind.eventConsumerNotRunning =>
        'event_consumer_not_running',
    };
  }

  String get label {
    return switch (this) {
      LarkApiFailureKind.none => 'OK',
      LarkApiFailureKind.missingToken => 'Missing token',
      LarkApiFailureKind.missingRelay => 'Missing relay',
      LarkApiFailureKind.missingScope => 'Missing user scope',
      LarkApiFailureKind.appScopeNotApplied => 'App scope not applied',
      LarkApiFailureKind.permissionDenied => 'Permission denied',
      LarkApiFailureKind.emptyResult => 'Empty result',
      LarkApiFailureKind.previewOnly => 'Preview only',
      LarkApiFailureKind.transportError => 'Transport error',
      LarkApiFailureKind.apiError => 'API error',
      LarkApiFailureKind.eventConsumerNotRunning =>
        'Event consumer not running',
    };
  }
}

@immutable
class LarkApiDiagnosis {
  const LarkApiDiagnosis({
    required this.failureKind,
    required this.summary,
    required this.nextAction,
    this.missingScopes = const [],
    this.logId,
    this.consoleUrl,
    this.source = 'mobile_native',
  });

  final LarkApiFailureKind failureKind;
  final String summary;
  final String nextAction;
  final List<String> missingScopes;
  final String? logId;
  final String? consoleUrl;
  final String source;

  bool get ok =>
      failureKind == LarkApiFailureKind.none ||
      failureKind == LarkApiFailureKind.emptyResult;

  Map<String, Object?> toJson() {
    return {
      'source': source,
      'failureKind': failureKind.evidenceName,
      'label': failureKind.label,
      'ok': ok,
      'summary': summary,
      'nextAction': nextAction,
      'missingScopes': missingScopes,
      'logId': logId,
      'consoleUrl': consoleUrl,
    };
  }
}

@immutable
class LarkRelayEvidenceSample {
  const LarkRelayEvidenceSample({
    required this.sendMode,
    required this.failureKind,
    required this.nextAction,
    required this.eventId,
    required this.requestId,
    required this.replyMessageId,
    required this.rawJsonPreviewStatus,
    this.rawJsonPreviewAvailable = false,
    this.eventTool = 'event consume im.message.receive_v1',
  });

  final String sendMode;
  final String failureKind;
  final String nextAction;
  final String eventId;
  final String requestId;
  final String replyMessageId;
  final String rawJsonPreviewStatus;
  final bool rawJsonPreviewAvailable;
  final String eventTool;

  bool get isSample => rawJsonPreviewAvailable;

  Map<String, Object?> toDisplayMap() {
    return {
      'send_mode': sendMode,
      'failure_kind': failureKind,
      'next_action': nextAction,
      'event_id': eventId,
      'request_id': requestId,
      'reply_message_id': replyMessageId,
      'raw_json_preview_status': rawJsonPreviewStatus,
    };
  }
}

@immutable
class LarkApiConnection {
  const LarkApiConnection({
    this.baseUrl = LarkApiService.defaultBaseUrl,
    this.relayUrl = '',
    this.relayToken = '',
    this.accessToken = '',
    this.tokenMode = LarkTokenMode.userAccessToken,
  });

  final String baseUrl;
  final String relayUrl;
  final String relayToken;
  final String accessToken;
  final LarkTokenMode tokenMode;

  bool get hasDirectToken =>
      accessToken.trim().isNotEmpty && tokenMode.canCallOpenApiDirectly;
  bool get hasRelay =>
      relayUrl.trim().isNotEmpty && tokenMode == LarkTokenMode.managedRelay;

  LarkApiConnection copyWith({
    String? baseUrl,
    String? relayUrl,
    String? relayToken,
    String? accessToken,
    LarkTokenMode? tokenMode,
  }) {
    return LarkApiConnection(
      baseUrl: baseUrl ?? this.baseUrl,
      relayUrl: relayUrl ?? this.relayUrl,
      relayToken: relayToken ?? this.relayToken,
      accessToken: accessToken ?? this.accessToken,
      tokenMode: tokenMode ?? this.tokenMode,
    );
  }

  Map<String, Object?> toRedactedJson() {
    return {
      'baseUrl': baseUrl,
      'relayUrl': relayUrl.isEmpty ? '' : relayUrl,
      'relayToken':
          relayToken.isEmpty ? '' : LarkApiService.redactSecret(relayToken),
      'accessToken':
          accessToken.isEmpty ? '' : LarkApiService.redactSecret(accessToken),
      'tokenMode': tokenMode.evidenceName,
      'canCallDirect': hasDirectToken,
      'canCallRelay': hasRelay,
    };
  }
}

@immutable
class LarkApiPayloadDraft {
  const LarkApiPayloadDraft({
    this.title = 'MobileCode evidence report',
    this.content = 'Generated from MobileCode. Review before publishing.',
    this.folderToken = '',
    this.documentId = '',
    this.blockId = '',
    this.driveParentNode = '',
    this.driveFileName = 'mobilecode-evidence.json',
    this.spreadsheetToken = '',
    this.sheetRange = 'Sheet1!A1:D4',
    this.bitableAppToken = '',
    this.bitableTableId = '',
  });

  final String title;
  final String content;
  final String folderToken;
  final String documentId;
  final String blockId;
  final String driveParentNode;
  final String driveFileName;
  final String spreadsheetToken;
  final String sheetRange;
  final String bitableAppToken;
  final String bitableTableId;
}

@immutable
class LarkApiRequestSpec {
  const LarkApiRequestSpec({
    required this.kind,
    required this.method,
    required this.path,
    required this.label,
    required this.requiredScopes,
    this.query = const {},
    this.body,
    this.contentType = 'application/json; charset=utf-8',
    this.supportsExecution = true,
    this.reasonIfPreviewOnly = '',
  });

  final LarkApiActionKind kind;
  final String method;
  final String path;
  final String label;
  final List<String> requiredScopes;
  final Map<String, String> query;
  final Object? body;
  final String contentType;
  final bool supportsExecution;
  final String reasonIfPreviewOnly;

  bool get isWriteAction => kind.isWriteAction;

  Uri uri(String baseUrl) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('$normalizedBase$normalizedPath');
    if (query.isEmpty) return base;
    return base.replace(queryParameters: query);
  }

  Map<String, String> headersForPreview(LarkApiConnection connection) {
    return {
      'Authorization': connection.accessToken.trim().isEmpty
          ? 'Bearer <access_token>'
          : 'Bearer ${LarkApiService.redactSecret(connection.accessToken)}',
      'Content-Type': contentType,
    };
  }

  Map<String, Object?> toPreviewJson(LarkApiConnection connection) {
    return {
      'label': label,
      'method': method,
      'url': uri(connection.baseUrl).toString(),
      'tokenMode': connection.tokenMode.evidenceName,
      'headers': headersForPreview(connection),
      'requiredScopes': requiredScopes,
      'writeAction': isWriteAction,
      'supportsExecution': supportsExecution,
      if (!supportsExecution && reasonIfPreviewOnly.isNotEmpty)
        'previewOnlyReason': reasonIfPreviewOnly,
      if (body != null) 'body': body,
    };
  }

  String toPrettyPreview(LarkApiConnection connection) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toPreviewJson(connection));
  }

  String toCurlPreview(LarkApiConnection connection) {
    final parts = <String>[
      'curl --request $method ${LarkApiService._quote(uri(connection.baseUrl).toString())}',
      '--header ${LarkApiService._quote('Authorization: Bearer <access_token>')}',
      '--header ${LarkApiService._quote('Content-Type: $contentType')}',
    ];
    if (body != null && contentType.startsWith('application/json')) {
      parts.add(
          '--data ${LarkApiService._quote(const JsonEncoder.withIndent('  ').convert(body))}');
    }
    return parts.join(' \\\n  ');
  }
}

@immutable
class LarkApiCallResult {
  const LarkApiCallResult({
    required this.success,
    required this.statusCode,
    required this.elapsedMs,
    required this.endpoint,
    required this.tokenMode,
    this.larkCode,
    this.larkMessage,
    this.requestId,
    this.body = '',
    this.error = '',
  });

  final bool success;
  final int statusCode;
  final int elapsedMs;
  final String endpoint;
  final String tokenMode;
  final int? larkCode;
  final String? larkMessage;
  final String? requestId;
  final String body;
  final String error;

  LarkApiDiagnosis get diagnosis => LarkApiService.diagnoseResult(this);

  Map<String, Object?> toEvidenceJson() {
    final diagnostic = diagnosis;
    return {
      'success': success,
      'statusCode': statusCode,
      'elapsedMs': elapsedMs,
      'endpoint': endpoint,
      'tokenMode': tokenMode,
      'larkCode': larkCode,
      'requestId': requestId,
      'larkMessage': larkMessage,
      'body': LarkApiService.compact(body, limit: 1600),
      'error': error,
      'failureKind': diagnostic.failureKind.evidenceName,
      'missingScopes': diagnostic.missingScopes,
      'nextAction': diagnostic.nextAction,
      'diagnosis': diagnostic.toJson(),
    };
  }

  String toPrettyText() {
    return const JsonEncoder.withIndent('  ').convert(toEvidenceJson());
  }
}

class LarkApiService {
  static const _cliParityCatalog = [
    LarkCliParityBlueprint(
      actionKind: LarkApiActionKind.docxCreate,
      cliCommandTemplate:
          'lark-cli docs +create --api-version v2 --doc-format markdown --title "<title>" --content "<content>" --folder-token "<folder_token>" --dry-run --format json',
      mobileNativePath: 'POST /docx/v1/documents',
      tokenCarrier: 'CLI auth token',
      cliErrorCodes: '0|1001|9999',
      requiredScopes: ['docx:document'],
    ),
    LarkCliParityBlueprint(
      actionKind: LarkApiActionKind.docxAppendBlocks,
      cliCommandTemplate:
          'lark-cli docs +create --api-version v2 --doc-format raw --document-id "<document_id>" --parent-id "<parent_block>" --content "<markdown>" --dry-run --format json',
      mobileNativePath:
          'POST /docx/v1/documents/{document_id}/blocks/{block_id}/children',
      tokenCarrier: 'CLI auth token',
      cliErrorCodes: '0|9999|1001',
      requiredScopes: ['docx:document'],
    ),
    LarkCliParityBlueprint(
      actionKind: LarkApiActionKind.sheetsAppend,
      cliCommandTemplate:
          'lark-cli sheets +append-values --spreadsheet-token "<spreadsheet_token>" --range "<Sheet1!A1:D4>" --values "<json>" --raw --format json',
      mobileNativePath:
          'POST /sheets/v2/spreadsheets/{spreadsheetToken}/values_append',
      tokenCarrier: 'CLI auth token',
      cliErrorCodes: '0|1001|9999',
      requiredScopes: ['sheets:spreadsheet or drive:drive'],
    ),
    LarkCliParityBlueprint(
      actionKind: LarkApiActionKind.driveUploadSmallFile,
      cliCommandTemplate:
          'lark-cli drive +upload --file "<path>" --parent-node "<parent_node>" --file-name "<file_name>" --dry-run --format json',
      mobileNativePath: 'POST /drive/v1/files/upload_all',
      tokenCarrier: 'CLI auth token',
      cliErrorCodes: '0|404|1001|9999',
      requiredScopes: ['drive:file or drive:drive'],
    ),
    LarkCliParityBlueprint(
      actionKind: LarkApiActionKind.wikiListSpaces,
      cliCommandTemplate:
          'lark-cli wiki +space-list --page-size 10 --format json',
      mobileNativePath: 'GET /wiki/v2/spaces?page_size=10',
      tokenCarrier: 'CLI auth token',
      cliErrorCodes: '0|missing_scope|99991672|empty_spaces',
      requiredScopes: [
        'wiki:space:retrieve',
        'wiki:wiki:readonly or wiki:wiki'
      ],
    ),
  ];

  static final Map<LarkApiActionKind, Map<String, Object?>> _cliParityLookup = {
    for (final item in _cliParityCatalog) item.actionKind: item.toJson(),
  };

  static Map<String, Object?> cliParityFor(LarkApiActionKind actionKind) {
    return _cliParityLookup[actionKind] ??
        {
          'action': actionKind.name,
          'cliCommandTemplate': 'N/A',
          'mobileNativePath': 'N/A',
          'tokenCarrier': 'N/A',
          'cliErrorCodes': 'unknown',
          'requiredScopes': const <String>[],
        };
  }

  static List<Map<String, Object?>> cliParityCatalog() {
    return _cliParityCatalog.map((item) => item.toJson()).toList();
  }

  static List<Map<String, Object?>> failureTaxonomySamples() {
    return const [
      {
        'sample': 'CLI user before scope grant',
        'tool': 'wiki +space-list',
        'tokenMode': 'user_access_token',
        'failureKind': 'missing_scope',
        'missingScopes': ['wiki:space:retrieve'],
        'nextAction':
            'Run lark-cli auth login --scope "wiki:space:retrieve" or start the mobile OAuth flow for that user scope.',
      },
      {
        'sample': 'CLI user after scope grant',
        'tool': 'wiki +space-list',
        'tokenMode': 'user_access_token',
        'failureKind': 'empty_result',
        'missingScopes': [],
        'nextAction':
            'API path is reachable. If spaces is empty, show a no-visible-wiki-space state instead of retrying auth.',
      },
      {
        'sample': 'CLI bot without app scope',
        'tool': 'wiki +space-list',
        'tokenMode': 'tenant_access_token',
        'failureKind': 'app_scope_not_applied',
        'code': 99991672,
        'missingScopes': [
          'wiki:wiki',
          'wiki:wiki:readonly',
          'wiki:space:retrieve',
        ],
        'nextAction':
            'Open the Feishu developer console for the app and apply the missing bot/app scopes before retrying with tenant token.',
      },
      {
        'sample': 'Feishu bot chat no reply',
        'tool': 'event consume im.message.receive_v1',
        'tokenMode': 'tenant_access_token',
        'failureKind': 'event_consumer_not_running',
        'httpStatus': 200,
        'errorCode': 'event_consumer_not_running',
        'logId': '<log_id>',
        'requestId': '<request_id>',
        'dryRunTrace':
            'lark-cli event consume im.message.receive_v1 --app-id <app_id> --tenant-key <tenant_access_token> --dry-run',
        'missingScopes': ['im:message:readonly or event subscription scopes'],
        'nextAction':
            'Run a Mac/CI/relay event consumer or configure a Feishu callback URL; creating the bot alone does not start an agent reply loop.',
      },
    ];
  }

  static const String _relayEvidenceSampleJson = '''
{
  "event": {
    "event_id": "<event_id>",
    "tool": "event consume im.message.receive_v1",
    "text": "<user_message_text>",
    "send_mode": "dry-run",
    "request_id": "<request_id>"
  },
  "reply": {
    "message_id": "<reply_message_id>",
    "status": "not_sent",
    "send_mode": "dry-run"
  },
  "evidence": {
    "failure_kind": "event_consumer_not_running",
    "next_action":
      "Start a Mac/CI/relay event consumer or configure a Feishu callback URL, then retry the same bot-private channel flow.",
    "token_mode": "tenant_access_token",
    "request_id": "<request_id>",
    "log_id": "<log_id>"
  }
}''';

  static List<LarkRelayEvidenceSample> relayEvidenceSamples() {
    return [
      parseRelayEvidenceSample(_relayEvidenceSampleJson),
    ];
  }

  static LarkRelayEvidenceSample parseRelayEvidenceSample(String rawJson) {
    final envelope = _tryDecodeMap(rawJson);
    final safeEnvelope = _sanitizeEnvelopeKeys(envelope);
    final event = safeEnvelope['event'] is Map<String, Object?>
        ? safeEnvelope['event'] as Map<String, Object?>
        : const <String, Object?>{};
    final reply = safeEnvelope['reply'] is Map<String, Object?>
        ? safeEnvelope['reply'] as Map<String, Object?>
        : const <String, Object?>{};
    final evidence = safeEnvelope['evidence'] is Map<String, Object?>
        ? safeEnvelope['evidence'] as Map<String, Object?>
        : const <String, Object?>{};
    final sendMode = _safeRelayValue(
      event['send_mode'] ?? event['sendMode'],
      fallback: 'N/A',
    );
    final failureKind = _safeRelayValue(
      evidence['failure_kind'] ?? evidence['failureKind'],
      fallback: 'N/A',
    );
    final nextAction = _safeRelayValue(
      evidence['next_action'] ?? evidence['nextAction'],
      fallback: 'Inspect evidence and retry with active consumer.',
    );
    final eventId = _safeRelayValue(
      event['event_id'] ?? event['eventId'],
      fallback: 'N/A',
    );
    final requestId = _safeRelayValue(
      evidence['request_id'] ??
          evidence['requestId'] ??
          event['request_id'] ??
          event['requestId'],
      fallback: 'N/A',
    );
    final replyMessageId = _safeRelayValue(
      reply['message_id'] ?? reply['messageId'],
      fallback: 'N/A',
    );
    return LarkRelayEvidenceSample(
      sendMode: sendMode,
      failureKind: failureKind,
      nextAction: nextAction,
      eventId: eventId,
      requestId: requestId,
      replyMessageId: replyMessageId,
      rawJsonPreviewAvailable: true,
      rawJsonPreviewStatus: _safeRelayValue(
            safeEnvelope['raw_json_preview_status'] ??
                safeEnvelope['rawJsonPreviewStatus'],
            fallback: 'Sample raw JSON loaded.',
          ) +
          (safeEnvelope.containsKey('raw_json_preview_status')
              ? ''
              : ' (sample)'),
      eventTool: _safeRelayValue(
        event['tool'] ?? safeEnvelope['tool'],
        fallback: 'event consume im.message.receive_v1',
      ),
    );
  }

  static Map<String, Object?> _sanitizeEnvelopeKeys(
    Map<String, Object?> envelope,
  ) {
    return envelope.map((key, value) {
      if (value is Map) {
        return MapEntry(
          key,
          value.map((innerKey, innerValue) => MapEntry(
                innerKey.toString(),
                innerValue,
              )),
        );
      }
      return MapEntry(key, value);
    });
  }

  static String _safeRelayValue(
    Object? value, {
    required String fallback,
  }) {
    if (value == null) return fallback;
    if (value is! String) return value.toString().trim();
    final normalized = value.trim();
    if (normalized.isEmpty) return fallback;
    if (normalized.startsWith('<') && normalized.endsWith('>'))
      return normalized;
    if (normalized.length > 64) return '<redacted>';
    return normalized;
  }

  LarkApiService({
    SecureStorageService? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageService();

  static const defaultBaseUrl = 'https://open.larksuite.com/open-apis';
  static const _prefsBaseUrl = 'mobilecode.lark.base_url';
  static const _prefsRelayUrl = 'mobilecode.lark.relay_url';
  static const _prefsTokenMode = 'mobilecode.lark.token_mode';
  static const _secureAccessToken = 'mobilecode_lark_access_token';
  static const _secureRelayToken = 'mobilecode_lark_relay_token';

  final SecureStorageService _secureStorage;
  final _uuid = const Uuid();

  Future<LarkApiConnection> loadConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureSecureStorage();
    final modeName = prefs.getString(_prefsTokenMode);
    return LarkApiConnection(
      baseUrl: prefs.getString(_prefsBaseUrl) ?? defaultBaseUrl,
      relayUrl: prefs.getString(_prefsRelayUrl) ?? '',
      relayToken: await _secureStorage.read(_secureRelayToken) ?? '',
      accessToken: await _secureStorage.read(_secureAccessToken) ?? '',
      tokenMode: LarkTokenMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => LarkTokenMode.userAccessToken,
      ),
    );
  }

  Future<void> saveConnection(LarkApiConnection connection) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureSecureStorage();
    await prefs.setString(
        _prefsBaseUrl,
        connection.baseUrl.trim().isEmpty
            ? defaultBaseUrl
            : connection.baseUrl.trim());
    await prefs.setString(_prefsRelayUrl, connection.relayUrl.trim());
    await prefs.setString(_prefsTokenMode, connection.tokenMode.name);
    await _secureStorage.write(
        _secureAccessToken, connection.accessToken.trim());
    await _secureStorage.write(_secureRelayToken, connection.relayToken.trim());
  }

  Future<void> clearSecrets() async {
    await _ensureSecureStorage();
    await _secureStorage.delete(_secureAccessToken);
    await _secureStorage.delete(_secureRelayToken);
  }

  LarkApiRequestSpec buildSpec({
    required LarkApiActionKind kind,
    required LarkApiPayloadDraft draft,
  }) {
    return switch (kind) {
      LarkApiActionKind.readiness => const LarkApiRequestSpec(
          kind: LarkApiActionKind.readiness,
          method: 'GET',
          path: '/wiki/v2/spaces',
          query: {'page_size': '1'},
          label: 'Readiness probe through a low-volume Wiki list call',
          requiredScopes: [
            'wiki:space:retrieve',
            'wiki:wiki:readonly or wiki:wiki'
          ],
        ),
      LarkApiActionKind.wikiListSpaces => const LarkApiRequestSpec(
          kind: LarkApiActionKind.wikiListSpaces,
          method: 'GET',
          path: '/wiki/v2/spaces',
          query: {'page_size': '10'},
          label: 'List accessible Wiki spaces',
          requiredScopes: [
            'wiki:space:retrieve',
            'wiki:wiki:readonly or wiki:wiki'
          ],
        ),
      LarkApiActionKind.docxCreate => LarkApiRequestSpec(
          kind: LarkApiActionKind.docxCreate,
          method: 'POST',
          path: '/docx/v1/documents',
          label: 'Create a Docx report document',
          requiredScopes: const ['docx:document'],
          body: {
            if (draft.folderToken.trim().isNotEmpty)
              'folder_token': draft.folderToken.trim(),
            'title': draft.title.trim().isEmpty
                ? 'MobileCode evidence report'
                : draft.title.trim(),
          },
        ),
      LarkApiActionKind.docxAppendBlocks => LarkApiRequestSpec(
          kind: LarkApiActionKind.docxAppendBlocks,
          method: 'POST',
          path:
              '/docx/v1/documents/${_requiredSegment(draft.documentId, 'document_id')}/blocks/${_requiredSegment(draft.blockId.isEmpty ? draft.documentId : draft.blockId, 'block_id')}/children',
          query: {
            'document_revision_id': '-1',
            'client_token': _uuid.v4(),
          },
          label: 'Append MobileCode evidence blocks to a Docx document',
          requiredScopes: const ['docx:document'],
          body: {'children': _docxBlocks(draft)},
        ),
      LarkApiActionKind.driveUploadSmallFile => LarkApiRequestSpec(
          kind: LarkApiActionKind.driveUploadSmallFile,
          method: 'POST',
          path: '/drive/v1/files/upload_all',
          label: 'Upload a small evidence file to Drive',
          requiredScopes: const ['drive:file or drive:drive'],
          contentType: 'multipart/form-data',
          supportsExecution: false,
          reasonIfPreviewOnly:
              'MobileCode can build the Drive upload protocol, but this first UI increment does not attach a local binary file yet.',
          body: {
            'file_name': draft.driveFileName.trim().isEmpty
                ? 'mobilecode-evidence.json'
                : draft.driveFileName.trim(),
            'parent_type': 'explorer',
            'parent_node': draft.driveParentNode.trim().isEmpty
                ? '<folder_token>'
                : draft.driveParentNode.trim(),
            'size': '<byte_length>',
            'file': '<binary>',
          },
        ),
      LarkApiActionKind.sheetsAppend => LarkApiRequestSpec(
          kind: LarkApiActionKind.sheetsAppend,
          method: 'POST',
          path:
              '/sheets/v2/spreadsheets/${_requiredSegment(draft.spreadsheetToken, 'spreadsheetToken')}/values_append',
          query: const {'insertDataOption': 'INSERT_ROWS'},
          label: 'Append a benchmark or release metric row to Sheets',
          requiredScopes: const ['sheets:spreadsheet or drive:drive'],
          body: {
            'valueRange': {
              'range': draft.sheetRange.trim().isEmpty
                  ? 'Sheet1!A1:D4'
                  : draft.sheetRange.trim(),
              'values': [
                [
                  DateTime.now().toIso8601String(),
                  draft.title.trim().isEmpty
                      ? 'MobileCode run'
                      : draft.title.trim(),
                  'mobilecode_lark_native_api',
                  draft.content.trim(),
                ],
              ],
            },
          },
        ),
      LarkApiActionKind.bitableBatchCreate => LarkApiRequestSpec(
          kind: LarkApiActionKind.bitableBatchCreate,
          method: 'POST',
          path:
              '/bitable/v1/apps/${_requiredSegment(draft.bitableAppToken, 'app_token')}/tables/${_requiredSegment(draft.bitableTableId, 'table_id')}/records/batch_create',
          query: {'client_token': _uuid.v4()},
          label: 'Create a Bitable evidence record',
          requiredScopes: const ['bitable:app or base:record:create'],
          body: {
            'records': [
              {
                'fields': {
                  'Title': draft.title.trim().isEmpty
                      ? 'MobileCode evidence'
                      : draft.title.trim(),
                  'Content': draft.content.trim(),
                  'Source': 'MobileCode',
                  'Created At': DateTime.now().millisecondsSinceEpoch,
                },
              }
            ],
          },
        ),
    };
  }

  Future<LarkApiCallResult> execute({
    required LarkApiConnection connection,
    required LarkApiRequestSpec spec,
  }) async {
    if (!spec.supportsExecution) {
      return LarkApiCallResult(
        success: false,
        statusCode: 0,
        elapsedMs: 0,
        endpoint: spec.path,
        tokenMode: connection.tokenMode.evidenceName,
        error: spec.reasonIfPreviewOnly,
      );
    }

    if (connection.tokenMode == LarkTokenMode.managedRelay) {
      return _executeViaRelay(connection: connection, spec: spec);
    }

    if (!connection.hasDirectToken) {
      return LarkApiCallResult(
        success: false,
        statusCode: 0,
        elapsedMs: 0,
        endpoint: spec.path,
        tokenMode: connection.tokenMode.evidenceName,
        error:
            'No direct access token is configured. Use User/Tenant/Runtime token mode, or configure a managed relay.',
      );
    }

    return _executeOpenApi(connection: connection, spec: spec);
  }

  Future<LarkApiCallResult> _executeOpenApi({
    required LarkApiConnection connection,
    required LarkApiRequestSpec spec,
  }) async {
    return _executeHttp(
      connection: connection,
      spec: spec,
      uri: spec.uri(connection.baseUrl),
      bearerToken: connection.accessToken.trim(),
    );
  }

  Future<LarkApiCallResult> _executeHttp({
    required LarkApiConnection connection,
    required LarkApiRequestSpec spec,
    required Uri uri,
    required String bearerToken,
  }) async {
    final started = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(spec.method, uri);
      if (bearerToken.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      request.headers.set(HttpHeaders.contentTypeHeader, spec.contentType);
      request.headers
          .set(HttpHeaders.userAgentHeader, 'MobileCode/0.1 LarkNativeApi');
      if (spec.body != null &&
          spec.contentType.startsWith('application/json')) {
        request.write(jsonEncode(spec.body));
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decodeStream(response);
      final requestId = _extractRequestId(response.headers);
      return _resultFromResponse(
        spec: spec,
        connection: connection,
        statusCode: response.statusCode,
        body: body,
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
        endpoint: uri.toString(),
        requestId: requestId,
      );
    } on Object catch (error) {
      return LarkApiCallResult(
        success: false,
        statusCode: 0,
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
        endpoint: uri.toString(),
        tokenMode: connection.tokenMode.evidenceName,
        error: compact(error.toString(), limit: 600),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<LarkApiCallResult> _executeViaRelay({
    required LarkApiConnection connection,
    required LarkApiRequestSpec spec,
  }) async {
    final relayUrl = connection.relayUrl.trim();
    if (relayUrl.isEmpty) {
      return LarkApiCallResult(
        success: false,
        statusCode: 0,
        elapsedMs: 0,
        endpoint: spec.path,
        tokenMode: connection.tokenMode.evidenceName,
        error: 'Managed relay URL is not configured.',
      );
    }
    final endpoint = relayUrl.endsWith('/')
        ? '${relayUrl}lark/openapi'
        : '$relayUrl/lark/openapi';
    final relaySpec = LarkApiRequestSpec(
      kind: spec.kind,
      method: 'POST',
      path: Uri.parse(endpoint).path,
      label: 'Managed relay forwarding ${spec.label}',
      requiredScopes: spec.requiredScopes,
      body: {
        'method': spec.method,
        'path': spec.path,
        'query': spec.query,
        'body': spec.body,
        'tokenMode': connection.tokenMode.evidenceName,
      },
    );
    return _executeHttp(
      connection: connection.copyWith(tokenMode: LarkTokenMode.managedRelay),
      spec: relaySpec,
      uri: Uri.parse(endpoint),
      bearerToken: connection.relayToken.trim(),
    );
  }

  LarkApiCallResult _resultFromResponse({
    required LarkApiRequestSpec spec,
    required LarkApiConnection connection,
    required int statusCode,
    required String body,
    required int elapsedMs,
    String? requestId,
    String? endpoint,
  }) {
    int? larkCode;
    String? larkMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final code = decoded['code'];
        if (code is int) larkCode = code;
        if (code is String) larkCode = int.tryParse(code);
        final msg = decoded['msg'] ?? decoded['message'];
        if (msg != null) larkMessage = msg.toString();
      }
    } catch (_) {
      // Some endpoints may return non-JSON errors.
    }
    final httpOk = statusCode >= 200 && statusCode < 300;
    final apiOk = larkCode == null || larkCode == 0;
    return LarkApiCallResult(
      success: httpOk && apiOk,
      statusCode: statusCode,
      elapsedMs: elapsedMs,
      endpoint: endpoint ?? spec.uri(connection.baseUrl).toString(),
      tokenMode: connection.tokenMode.evidenceName,
      larkCode: larkCode,
      larkMessage: larkMessage,
      requestId: requestId,
      body: redactBody(body),
      error: httpOk && apiOk ? '' : compact(larkMessage ?? body, limit: 600),
    );
  }

  static String? _extractRequestId(HttpHeaders headers) {
    final candidates = <String>[
      'x-tt-logid',
      'x-lark-request-id',
      'x-tt-log-id',
      'x-request-id',
      'request-id',
      'lark-request-id',
    ];
    for (final key in candidates) {
      final value = headers.value(key);
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String redactSecret(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 10) return '${trimmed.substring(0, 2)}...';
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
  }

  static String redactBody(String value) {
    return value
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._\-]+'), 'Bearer <redacted>')
        .replaceAll(
            RegExp(
                r'"(?:access_token|refresh_token|app_secret|Authorization)"\s*:\s*"[^"]+"'),
            '"<secret>":"<redacted>"');
  }

  static String compact(String value, {int limit = 800}) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= limit) return trimmed;
    return '${trimmed.substring(0, limit)}...';
  }

  static LarkApiDiagnosis diagnoseResult(LarkApiCallResult result) {
    final bodyJson = _tryDecodeMap(result.body);
    final errorJson = _tryDecodeMap(result.error);
    final envelope = _mergeDiagnosticMaps(bodyJson, errorJson);
    final text = [
      result.error,
      result.body,
      result.larkMessage ?? '',
      jsonEncode(envelope),
    ].join(' ').toLowerCase();
    final missingScopes = _extractMissingScopes(envelope, text);
    final logId = _firstString(envelope, const [
          'log_id',
          'logId',
          'request_id',
          'requestId',
        ]) ??
        result.requestId;
    final consoleUrl = _firstString(envelope, const [
      'console_url',
      'consoleUrl',
    ]);

    if (result.success) {
      if (_isEmptyWikiSpacesResult(result)) {
        return const LarkApiDiagnosis(
          failureKind: LarkApiFailureKind.emptyResult,
          summary:
              'OpenAPI reachable and authorized, but no visible Wiki spaces were returned.',
          nextAction:
              'Treat this as a valid empty state. Offer my_library lookup, joining a Wiki space, or creating a test Wiki space.',
        );
      }
      return const LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.none,
        summary: 'OpenAPI request succeeded.',
        nextAction: 'Continue with the requested Lark action.',
      );
    }

    if (text.contains('no direct access token is configured')) {
      return const LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.missingToken,
        summary: 'No direct user or tenant access token is configured.',
        nextAction:
            'Paste a user/tenant token, use runtime-provided token mode, or configure managed relay.',
      );
    }

    if (text.contains('managed relay url is not configured')) {
      return const LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.missingRelay,
        summary: 'Managed relay mode is selected but no relay URL is set.',
        nextAction:
            'Set the managed relay URL or switch to user/tenant access token mode.',
      );
    }

    if (result.larkCode == 99991672 ||
        text.contains('app_scope_not_applied') ||
        text.contains('has not applied for the required scope')) {
      return LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.appScopeNotApplied,
        summary:
            'The Feishu/Lark app has not applied for the required API scopes.',
        nextAction: consoleUrl == null
            ? 'Open the Feishu developer console and apply the missing app scopes before retrying.'
            : 'Open $consoleUrl and apply the missing app scopes before retrying.',
        missingScopes: missingScopes,
        logId: logId,
        consoleUrl: consoleUrl,
      );
    }

    if (text.contains('missing_scope') ||
        text.contains('missing required scope') ||
        missingScopes.isNotEmpty) {
      return LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.missingScope,
        summary: 'The current user token is valid but lacks required scopes.',
        nextAction: missingScopes.isEmpty
            ? 'Re-authorize the user token with the required scopes.'
            : 'Re-authorize with scope ${missingScopes.join(' / ')}.',
        missingScopes: missingScopes,
        logId: logId,
      );
    }

    if (result.statusCode == 401 || result.statusCode == 403) {
      return LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.permissionDenied,
        summary: 'Lark rejected the request for auth or permission reasons.',
        nextAction:
            'Check token mode, app visibility, resource membership, and required scopes before retrying.',
        missingScopes: missingScopes,
        logId: logId,
      );
    }

    if (text.contains('first ui increment does not attach') ||
        text.contains('preview') && result.statusCode == 0) {
      return const LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.previewOnly,
        summary: 'This action currently supports protocol preview only.',
        nextAction:
            'Use Preview JSON or Copy cURL, then add native execution support for the missing payload path.',
      );
    }

    if (text.contains('event_consumer_not_running') ||
        text.contains('event consumer is not running') ||
        text.contains('im.message.receive_v1')) {
      return LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.eventConsumerNotRunning,
        summary:
            'Bot event consumer process is not running for this tenant/app context.',
        nextAction:
            'Start an event consumer service or callback path (Mac/CI/relay), then retry the chat flow.',
        missingScopes: const [
          'im:message:readonly or event subscription scopes',
        ],
        logId: logId,
      );
    }

    if (result.statusCode == 0) {
      return LarkApiDiagnosis(
        failureKind: LarkApiFailureKind.transportError,
        summary: 'No HTTP status was returned by the native request.',
        nextAction:
            'Check network, base URL, relay availability, token mode, and platform HTTP permissions.',
        logId: logId,
      );
    }

    return LarkApiDiagnosis(
      failureKind: LarkApiFailureKind.apiError,
      summary: result.error.isEmpty
          ? 'Lark API returned an unsuccessful response.'
          : compact(result.error, limit: 220),
      nextAction:
          'Use statusCode, larkCode, requestId/logId, and required scopes to choose the next recovery step.',
      missingScopes: missingScopes,
      logId: logId,
    );
  }

  static Map<String, Object?> _mergeDiagnosticMaps(
    Map<String, Object?> first,
    Map<String, Object?> second,
  ) {
    final merged = <String, Object?>{};
    void addMap(Map<String, Object?> source) {
      for (final entry in source.entries) {
        merged[entry.key] = entry.value;
        final value = entry.value;
        if (value is Map<String, Object?>) {
          for (final nested in value.entries) {
            merged.putIfAbsent(nested.key, () => nested.value);
          }
        }
      }
    }

    addMap(first);
    addMap(second);
    return merged;
  }

  static Map<String, Object?> _tryDecodeMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    if (value is! String || value.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, val) => MapEntry(key.toString(), val));
      }
    } catch (_) {
      // Non-JSON Lark errors are classified with text fallbacks.
    }
    return const {};
  }

  static List<String> _extractMissingScopes(
    Map<String, Object?> envelope,
    String text,
  ) {
    final scopes = <String>{};

    void addValue(Object? value) {
      if (value is List) {
        for (final item in value) {
          addValue(item);
        }
        return;
      }
      if (value is String) {
        for (final part in value.split(RegExp(r'[\s,]+'))) {
          final trimmed = part.trim().replaceAll(RegExp(r'["\[\]]'), '');
          if (trimmed.contains(':') && trimmed.length > 3) scopes.add(trimmed);
        }
      }
    }

    for (final key in const [
      'missing_scopes',
      'missingScopes',
      'required_scopes',
      'requiredScopes',
    ]) {
      addValue(envelope[key]);
    }

    final missingScopeMatch =
        RegExp(r'missing required scope\(s\):\s*([^"\n]+)').firstMatch(text);
    if (missingScopeMatch != null) {
      addValue(missingScopeMatch.group(1));
    }

    final quotedScopeMatches =
        RegExp(r'[a-z][a-z0-9_]*:[a-z0-9_:.\-]+').allMatches(text);
    for (final match in quotedScopeMatches) {
      scopes.add(match.group(0)!);
    }

    return scopes.toList()..sort();
  }

  static String? _firstString(
      Map<String, Object?> envelope, List<String> keys) {
    for (final key in keys) {
      final value = envelope[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static bool _isEmptyWikiSpacesResult(LarkApiCallResult result) {
    if (!result.endpoint.contains('/wiki/v2/spaces')) return false;
    final decoded = _tryDecodeMap(result.body);
    final Object? data = decoded['data'];
    if (data is Map) {
      final spaces = data['spaces'] ?? data['items'];
      return spaces is List && spaces.isEmpty;
    }
    final spaces = decoded['spaces'] ?? decoded['items'];
    return spaces is List && spaces.isEmpty;
  }

  Future<void> _ensureSecureStorage() async {
    try {
      await _secureStorage.initialize();
    } on Object catch (error) {
      debugPrint('[LarkApiService] secure storage init failed: $error');
      rethrow;
    }
  }

  static String _requiredSegment(String value, String label) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '<$label>' : Uri.encodeComponent(trimmed);
  }

  static List<Map<String, Object?>> _docxBlocks(LarkApiPayloadDraft draft) {
    final lines = <String>[
      draft.title.trim().isEmpty
          ? 'MobileCode evidence report'
          : draft.title.trim(),
      '',
      ...draft.content.split('\n'),
    ];
    return lines.where((line) => line.trim().isNotEmpty).take(50).map((line) {
      final content = line.trim();
      final heading = content == lines.first.trim();
      return {
        'block_type': heading ? 4 : 2,
        if (heading)
          'heading2': {
            'elements': [
              {
                'text_run': {'content': content},
              }
            ],
          }
        else
          'text': {
            'elements': [
              {
                'text_run': {'content': content},
              }
            ],
          },
      };
    }).toList();
  }

  static String _quote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}
