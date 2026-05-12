// lib/services/api_service.dart

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Custom exception for API-related errors.
///
/// Wraps the original exception and provides context about the
/// HTTP method and path that failed.
class ApiException implements Exception {
  final String message;
  final String? path;
  final String method;
  final int? statusCode;
  final dynamic originalError;

  const ApiException({
    required this.message,
    this.path,
    this.method = 'GET',
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() =>
      'ApiException [$method $path ${statusCode ?? ''}]: $message';
}

/// A centralized HTTP client service wrapping [Dio].
///
/// Provides a single point of configuration for timeouts, interceptors,
/// error handling, and authentication headers. All other services
/// that need HTTP should use this wrapper rather than creating
/// their own Dio instances.
///
/// ```dart
/// final api = ref.read(apiServiceProvider);
/// final response = await api.get('/user/repos');
/// ```
class ApiService {
  /// The underlying Dio instance. Exposed for advanced use cases
  /// (e.g., streaming downloads) but prefer the wrapper methods.
  late final Dio dio;

  bool _initialized = false;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Default connection timeout for all requests.
  static const Duration _connectTimeout = Duration(seconds: 15);

  /// Default receive timeout for all requests.
  static const Duration _receiveTimeout = Duration(seconds: 30);

  /// Default send timeout for all requests.
  static const Duration _sendTimeout = Duration(seconds: 30);

  /// Creates an [ApiService] but does not initialize it.
  /// Call [init] before making any requests.
  ApiService();

  /// Creates and initializes an [ApiService] in one step.
  factory ApiService.create() {
    final service = ApiService();
    service.init();
    return service;
  }

  /// Initialize the Dio instance with base configuration.
  ///
  /// Sets up timeouts, logging interceptors (debug builds only),
  /// and default headers. This must be called before any HTTP
  /// requests are made.
  void init() {
    if (_initialized) return;

    dio = Dio(
      BaseOptions(
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        sendTimeout: _sendTimeout,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // Add logging interceptor in debug mode.
    // SECURITY: Only enabled in debug builds. Redacts sensitive headers.
    if (kDebugMode) {
      dio.interceptors.add(
        _SecureLogInterceptor(
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (obj) => debugPrint('[ApiService] $obj'),
        ),
      );
    }

    // Add retry interceptor for transient failures.
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          // Retry on timeout or connection error (max 1 retry).
          final isRetryable = error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError;

          final requestOptions = error.requestOptions;
          final extra = requestOptions.extra;
          final hasRetried = extra['_retried'] == true;

          if (isRetryable && !hasRetried) {
            debugPrint('[ApiService] Retrying ${requestOptions.path}...');
            requestOptions.extra['_retried'] = true;
            try {
              await Future.delayed(const Duration(seconds: 1));
              final response = await dio.fetch(requestOptions);
              handler.resolve(response);
              return;
            } catch (e) {
              // Fall through to original error.
            }
          }
          handler.next(error);
        },
      ),
    );

    // Configure SSL certificate handling for all platforms.
    _configureSsl();

    _initialized = true;
    debugPrint('[ApiService] Initialized');
  }

  /// Configure SSL/TLS settings for the HTTP client.
  ///
  /// SECURITY: In production, certificates are always validated.
  /// Only in debug mode with an explicit opt-in are self-signed certs allowed.
  void _configureSsl() {
    (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
        (HttpClient client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        // SECURITY FIX: Always validate certificates in production.
        // Only allow bypass in debug builds when connecting to localhost.
        if (kDebugMode) {
          // Allow self-signed certs only for localhost/loopback in debug.
          if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
            return true;
          }
        }
        // Production: always validate certificates properly.
        return false;
      };
      return client;
    };
  }

  // ─── Generic HTTP Methods ──────────────────────────────────────────

  /// Perform a GET request.
  ///
  /// [path] can be a full URL or a relative path (if [baseUrl] is set).
  /// [query] parameters are appended to the URL.
  ///
  /// Throws [ApiException] on failure.
  Future<Response> get(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      final response = await dio.get(
        path,
        queryParameters: query,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _mapDioError(e, 'GET', path);
    } catch (e) {
      throw ApiException(
        message: 'Unexpected error: $e',
        path: path,
        method: 'GET',
        originalError: e,
      );
    }
  }

  /// Perform a POST request.
  ///
  /// [data] is serialized to JSON automatically by Dio.
  /// Throws [ApiException] on failure.
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      final response = await dio.post(
        path,
        data: data,
        queryParameters: query,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _mapDioError(e, 'POST', path);
    } catch (e) {
      throw ApiException(
        message: 'Unexpected error: $e',
        path: path,
        method: 'POST',
        originalError: e,
      );
    }
  }

  /// Perform a PUT request.
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      final response = await dio.put(
        path,
        data: data,
        queryParameters: query,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _mapDioError(e, 'PUT', path);
    } catch (e) {
      throw ApiException(
        message: 'Unexpected error: $e',
        path: path,
        method: 'PUT',
        originalError: e,
      );
    }
  }

  /// Perform a PATCH request.
  Future<Response> patch(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      final response = await dio.patch(
        path,
        data: data,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _mapDioError(e, 'PATCH', path);
    } catch (e) {
      throw ApiException(
        message: 'Unexpected error: $e',
        path: path,
        method: 'PATCH',
        originalError: e,
      );
    }
  }

  /// Perform a DELETE request.
  Future<Response> delete(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      final response = await dio.delete(
        path,
        data: data,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _mapDioError(e, 'DELETE', path);
    } catch (e) {
      throw ApiException(
        message: 'Unexpected error: $e',
        path: path,
        method: 'DELETE',
        originalError: e,
      );
    }
  }

  // ─── SSE Streaming ─────────────────────────────────────────────────

  /// Initiate a Server-Sent Events (SSE) stream.
  ///
  /// Returns a [Stream] of decoded string lines from the SSE response.
  /// The caller is responsible for parsing individual SSE events.
  ///
  /// ```dart
  /// final stream = api.sseStream('/v1/chat/completions', data: body);
  /// await for (final line in stream) {
  ///   if (line.startsWith('data: ')) { ... }
  /// }
  /// ```
  Stream<String> sseStream(
    String path, {
    required Map<String, dynamic> data,
    Map<String, dynamic>? headers,
  }) {
    _ensureInitialized();

    final requestDio = Dio(
      BaseOptions(
        baseUrl: dio.options.baseUrl,
        headers: {
          ...?dio.options.headers,
          ...?headers,
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        },
        responseType: ResponseType.stream,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 5), // Long-running streams.
      ),
    );

    final streamController = StreamController<String>.broadcast();

    () async {
      try {
        final response = await requestDio.post(
          path,
          data: data,
        );

        final responseStream = response.data as ResponseBody;
        final lines =
            responseStream.stream.transform(const Utf8Decoder()).transform(const LineSplitter());

        await for (final line in lines) {
          if (streamController.isClosed) break;
          streamController.add(line);
        }

        await streamController.close();
      } on DioException catch (e) {
        if (!streamController.isClosed) {
          streamController.addError(_mapDioError(e, 'POST', path));
          await streamController.close();
        }
      } catch (e) {
        if (!streamController.isClosed) {
          streamController.addError(ApiException(
            message: 'SSE stream error: $e',
            path: path,
            method: 'POST',
            originalError: e,
          ));
          await streamController.close();
        }
      }
    }();

    return streamController.stream;
  }

  // ─── Auth & Configuration ──────────────────────────────────────────

  /// Set the base URL for all requests.
  void setBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  /// Set the Authorization header with a Bearer token.
  void setAuthHeader(String token) {
    dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Set a custom header.
  void setHeader(String key, String value) {
    dio.options.headers[key] = value;
  }

  /// Remove the Authorization header.
  void clearAuthHeader() {
    dio.options.headers.remove('Authorization');
  }

  /// Clear all custom headers except defaults.
  void clearHeaders() {
    dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  // ─── Private Helpers ───────────────────────────────────────────────

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'ApiService has not been initialized. Call init() first.');
    }
  }

  /// Map Dio exceptions to our custom [ApiException] type.
  ApiException _mapDioError(DioException error, String method, String path) {
    String message;
    int? statusCode;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = 'Connection timed out. Please check your network.';
        break;
      case DioExceptionType.connectionError:
        message = 'No internet connection. Please check your network.';
        break;
      case DioExceptionType.badResponse:
        statusCode = error.response?.statusCode;
        final responseData = error.response?.data;
        if (responseData is Map && responseData['error'] != null) {
          final err = responseData['error'];
          if (err is Map) {
            message = err['message']?.toString() ?? 'Server error $statusCode';
          } else {
            message = err.toString();
          }
        } else if (responseData is Map && responseData['message'] != null) {
          message = responseData['message'].toString();
        } else {
          message = 'Server returned status $statusCode';
        }
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      case DioExceptionType.badCertificate:
        message = 'SSL certificate verification failed.';
        break;
      case DioExceptionType.unknown:
      default:
        // SECURITY: Do not leak internal error details to the UI.
        message = 'An unexpected error occurred. Please try again.';
    }

    return ApiException(
      message: message,
      path: path,
      method: method,
      statusCode: statusCode,
      originalError: error,
    );
  }

  /// Dispose of resources.
  void dispose() {
    dio.close(force: true);
    _initialized = false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Secure Log Interceptor (Redacts sensitive headers)
// ═══════════════════════════════════════════════════════════════════════════

/// A secure logging interceptor that redacts sensitive headers.
///
/// SECURITY: Prevents API keys, tokens, and credentials from leaking
/// into system logs. Use this instead of the default [LogInterceptor].
class _SecureLogInterceptor extends Interceptor {
  final bool requestHeader;
  final bool requestBody;
  final bool responseHeader;
  final bool responseBody;
  final bool error;
  final void Function(Object)? logPrint;

  _SecureLogInterceptor({
    this.requestHeader = true,
    this.requestBody = false,
    this.responseHeader = true,
    this.responseBody = false,
    this.error = true,
    this.logPrint,
  });

  static const _sensitiveHeaders = {
    'authorization',
    'x-api-key',
    'cookie',
    'x-github-token',
    'x-auth-token',
  };

  Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
    final redacted = <String, dynamic>{};
    for (final entry in headers.entries) {
      final lowerKey = entry.key.toLowerCase();
      if (_sensitiveHeaders.contains(lowerKey)) {
        redacted[entry.key] = '***REDACTED***';
      } else {
        redacted[entry.key] = entry.value;
      }
    }
    return redacted;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final log = StringBuffer();
    log.writeln('REQUEST: ${options.method} ${options.path}');
    if (requestHeader) {
      log.writeln('HEADERS: ${_redactHeaders(options.headers)}');
    }
    if (requestBody && options.data != null) {
      log.writeln('BODY: ${_redactBody(options.data)}');
    }
    logPrint?.call(log.toString());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final log = StringBuffer();
    log.writeln('RESPONSE: ${response.statusCode} ${response.requestOptions.path}');
    if (responseHeader) {
      log.writeln('HEADERS: ${response.headers.map}');
    }
    if (responseBody) {
      log.writeln('BODY: ${_redactBody(response.data)}');
    }
    logPrint?.call(log.toString());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (error) {
      final log = StringBuffer();
      log.writeln('ERROR: ${err.type} ${err.requestOptions.path}');
      logPrint?.call(log.toString());
    }
    handler.next(err);
  }

  /// Redact sensitive fields from request/response body.
  Object? _redactBody(Object? data) {
    if (data is Map) {
      final redacted = Map<String, dynamic>.from(data);
      for (final key in const ['api_key', 'apiKey', 'key', 'token', 'password', 'secret']) {
        if (redacted.containsKey(key)) {
          redacted[key] = '***REDACTED***';
        }
      }
      return redacted;
    }
    return data;
  }
}
