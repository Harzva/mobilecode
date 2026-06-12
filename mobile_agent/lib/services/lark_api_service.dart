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

  Map<String, Object?> toEvidenceJson() {
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
          'lark-cli wiki +space list --page-size 10 --format json',
      mobileNativePath: 'GET /wiki/v2/spaces?page_size=10',
      tokenCarrier: 'CLI auth token',
      cliErrorCodes: '0|1001|9999',
      requiredScopes: ['wiki:wiki:readonly or wiki:wiki'],
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
          requiredScopes: ['wiki:wiki:readonly or wiki:wiki'],
        ),
      LarkApiActionKind.wikiListSpaces => const LarkApiRequestSpec(
          kind: LarkApiActionKind.wikiListSpaces,
          method: 'GET',
          path: '/wiki/v2/spaces',
          query: {'page_size': '10'},
          label: 'List accessible Wiki spaces',
          requiredScopes: ['wiki:wiki:readonly or wiki:wiki'],
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
