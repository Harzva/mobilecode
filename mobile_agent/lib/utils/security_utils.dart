// lib/utils/security_utils.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// ---------------------------------------------------------------------------
// Security Utilities
// ---------------------------------------------------------------------------

/// Collection of security-related utility functions.
///
/// Provides operations for:
/// - API key strength estimation
/// - Secure random token generation
/// - Cryptographic hashing
/// - Input sanitization
/// - API key masking and validation
///
/// All operations use cryptographically secure random number generation
/// where applicable.
///
/// ```dart
/// final strength = SecurityUtils.checkStrength('myPassword123!');
/// final token = SecurityUtils.generateSecureToken(length: 32);
/// final masked = SecurityUtils.maskApiKey('sk-abc123...');
/// ```
class SecurityUtils {
  SecurityUtils._(); // Private constructor — utility class.

  // -- Strength scoring constants -----------------------------------------

  static const int _minLengthWeak = 8;
  static const int _minLengthFair = 12;
  static const int _minLengthGood = 16;
  static const int _minLengthStrong = 24;

  // -- Character set regex ------------------------------------------------

  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasDigits = RegExp(r'\d');
  static final RegExp _hasSpecialChars = RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:\\,.<>?]');
  static final RegExp _hasWhitespace = RegExp(r'\s');

  /// OpenAI API key format: sk- followed by alphanumeric characters.
  static final RegExp _openAIKeyRegex = RegExp(r'^sk-[A-Za-z0-9_-]{20,}$');

  /// Anthropic Claude API key format: sk-ant- followed by alphanumeric.
  static final RegExp _claudeKeyRegex = RegExp(r'^sk-ant-[A-Za-z0-9_-]{20,}$');

  /// GitHub personal access token: ghp_ followed by alphanumeric.
  static final RegExp _githubTokenRegex = RegExp(r'^ghp_[A-Za-z0-9]{36}$');

  /// Gemini API key: alphanumeric, typically 39 characters.
  static final RegExp _geminiKeyRegex = RegExp(r'^[A-Za-z0-9_-]{30,}$');

  /// Base URL validation.
  static final RegExp _urlRegex = RegExp(
    r'^https?://'
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'
    r'localhost|'
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'
    r'(?::\d+)?'
    r'(?:/?|[/?]\S+)$',
    caseSensitive: false,
  );

  // ═══════════════════════════════════════════════════════════════════════
  // PASSWORD / KEY STRENGTH
  // ═══════════════════════════════════════════════════════════════════════

  /// Evaluate the strength of a password or API key.
  ///
  /// Returns an integer from 1 (very weak) to 5 (very strong).
  ///
  /// Scoring criteria:
  /// | Level | Label       | Criteria                          |
  /// |-------|-------------|-----------------------------------|
  /// | 1     | Very Weak   | < 8 chars, single character type  |
  /// | 2     | Weak        | 8-11 chars, limited variety       |
  /// | 3     | Fair        | 12-15 chars, some variety         |
  /// | 4     | Strong      | 16-23 chars, good variety         |
  /// | 5     | Very Strong | 24+ chars, full variety           |
  static int checkStrength(String key) {
    if (key.isEmpty) return 1;

    int score = 0;
    int varietyCount = 0;

    // Length scoring.
    final length = key.length;
    if (length >= _minLengthStrong) {
      score += 2;
    } else if (length >= _minLengthGood) {
      score += 2;
    } else if (length >= _minLengthFair) {
      score += 1;
    } else if (length >= _minLengthWeak) {
      score += 0;
    }

    // Character variety scoring.
    if (_hasLowercase.hasMatch(key)) varietyCount++;
    if (_hasUppercase.hasMatch(key)) varietyCount++;
    if (_hasDigits.hasMatch(key)) varietyCount++;
    if (_hasSpecialChars.hasMatch(key)) varietyCount++;

    score += varietyCount;

    // Penalize whitespace.
    if (_hasWhitespace.hasMatch(key)) score -= 1;

    // Penalize common patterns.
    if (_hasCommonPatterns(key)) score -= 1;

    // Clamp to 1-5 range.
    return score.clamp(1, 5);
  }

  /// Get a human-readable label for a strength score.
  static String strengthLabel(int score) {
    switch (score.clamp(1, 5)) {
      case 1:
        return 'Very Weak';
      case 2:
        return 'Weak';
      case 3:
        return 'Fair';
      case 4:
        return 'Strong';
      case 5:
        return 'Very Strong';
      default:
        return 'Unknown';
    }
  }

  /// Get a color hex code for a strength score (for UI display).
  static String strengthColor(int score) {
    switch (score.clamp(1, 5)) {
      case 1:
        return '#FF4444'; // Red
      case 2:
        return '#FF8800'; // Orange
      case 3:
        return '#FFCC00'; // Yellow
      case 4:
        return '#88CC44'; // Light green
      case 5:
        return '#44AA44'; // Green
      default:
        return '#999999';
    }
  }

  /// Check if the key contains common weak patterns.
  static bool _hasCommonPatterns(String key) {
    final lower = key.toLowerCase();
    final commonPatterns = [
      'password', '123456', 'qwerty', 'abcdef',
      'letmein', 'welcome', 'admin', 'root',
      'default', 'test', 'demo', 'sample',
      '111111', '000000', 'abc123', 'login',
    ];
    return commonPatterns.any((pattern) => lower.contains(pattern));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SECURE RANDOM TOKENS
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a cryptographically secure random token.
  ///
  /// [length] is the number of random bytes (default 32 = 256 bits).
  /// Returns a Base64-encoded string.
  static String generateSecureToken({int length = 32}) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64UrlEncode(bytes);
  }

  /// Generate a secure random token as a hexadecimal string.
  ///
  /// [length] is the number of random bytes (default 32).
  static String generateSecureHexToken({int length = 32}) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generate a secure random alphanumeric string.
  ///
  /// [length] is the character count (default 32).
  static String generateAlphanumericToken({int length = 32}) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Generate a nonce (number used once) for cryptographic operations.
  ///
  /// Returns a 12-byte nonce as a Base64 string (recommended for GCM).
  static String generateNonce() {
    final random = Random.secure();
    final bytes = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HASHING
  // ═══════════════════════════════════════════════════════════════════════

  /// Compute SHA-256 hash of data.
  ///
  /// Use for integrity verification, **not for password storage**.
  static String hashSha256(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Compute SHA-512 hash of data.
  static String hashSha512(String data) {
    final bytes = utf8.encode(data);
    final digest = sha512.convert(bytes);
    return digest.toString();
  }

  /// Compute HMAC-SHA256 of data with a key.
  ///
  /// Use for message authentication and integrity.
  static String hmacSha256(String data, String key) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.toString();
  }

  /// Compute a quick hash for comparison purposes (e.g., checking
  /// if a value has changed).
  ///
  /// Returns first 16 chars of SHA-256 for compact comparison.
  static String quickHash(String data) {
    return hashSha256(data).substring(0, 16);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INPUT SANITIZATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Sanitize user input to prevent injection attacks.
  ///
  /// - Removes null bytes
  /// - Trims whitespace
  /// - Removes control characters (except newlines)
  /// - Limits length
  static String sanitize(String input, {int maxLength = 10000}) {
    if (input.isEmpty) return '';

    // Remove null bytes.
    var sanitized = input.replaceAll('\x00', '');

    // Remove control characters except common whitespace.
    sanitized = sanitized.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
      '',
    );

    // Trim leading/trailing whitespace.
    sanitized = sanitized.trim();

    // Limit length.
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }

    return sanitized;
  }

  /// Sanitize input for use in URLs / paths.
  ///
  /// Removes characters that could enable path traversal.
  static String sanitizePath(String input) {
    if (input.isEmpty) return '';

    return input
        .replaceAll('..', '')
        .replaceAll('~', '')
        .replaceAll(RegExp(r'[<>|&;"\\]'), '')
        .trim();
  }

  /// Escape special characters for safe display.
  ///
  /// Converts HTML-special characters to entities.
  static String escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// Remove all whitespace from a string.
  static String removeWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s'), '');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // API KEY MASKING
  // ═══════════════════════════════════════════════════════════════════════

  /// Mask an API key for safe display.
  ///
  /// Shows only the first 3 and last 4 characters.
  /// ```
  /// sk-abc123...wxyz → sk-...wxyz
  /// ```
  static String maskApiKey(String apiKey) {
    if (apiKey.isEmpty) return '';
    if (apiKey.length <= 8) return '*' * apiKey.length;

    final prefix = apiKey.substring(0, 3);
    final suffix = apiKey.substring(apiKey.length - 4);
    return '$prefix...$suffix';
  }

  /// Mask with custom visible prefix/suffix lengths.
  static String maskApiKeyCustom(
    String apiKey, {
    int prefixLength = 3,
    int suffixLength = 4,
  }) {
    if (apiKey.isEmpty) return '';
    if (apiKey.length <= prefixLength + suffixLength) {
      return '*' * apiKey.length;
    }

    final prefix = apiKey.substring(0, prefixLength);
    final suffix = apiKey.substring(apiKey.length - suffixLength);
    return '$prefix${'.' * 4}$suffix';
  }

  /// Mask only the middle portion (show more of the key).
  static String maskMiddle(String apiKey, {int visibleEnds = 6}) {
    if (apiKey.isEmpty) return '';
    if (apiKey.length <= visibleEnds * 2) return '*' * apiKey.length;

    final prefix = apiKey.substring(0, visibleEnds);
    final suffix = apiKey.substring(apiKey.length - visibleEnds);
    final middleLength = apiKey.length - (visibleEnds * 2);
    return '$prefix${'*' * middleLength}$suffix';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // API KEY VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate an OpenAI API key format.
  ///
  /// Checks for `sk-` prefix and minimum length.
  static bool isValidOpenAIKey(String key) {
    if (key.isEmpty || key.length < 20) return false;
    return _openAIKeyRegex.hasMatch(key);
  }

  /// Validate an Anthropic Claude API key format.
  static bool isValidClaudeKey(String key) {
    if (key.isEmpty || key.length < 20) return false;
    return _claudeKeyRegex.hasMatch(key);
  }

  /// Validate a Google Gemini API key format.
  static bool isValidGeminiKey(String key) {
    if (key.isEmpty || key.length < 20) return false;
    return _geminiKeyRegex.hasMatch(key);
  }

  /// Validate a GitHub personal access token format.
  static bool isValidGitHubToken(String token) {
    if (token.isEmpty) return false;
    return _githubTokenRegex.hasMatch(token);
  }

  /// Auto-detect provider from API key format.
  ///
  /// Returns the provider name or 'unknown'.
  static String detectProvider(String key) {
    if (isValidOpenAIKey(key)) return 'openai';
    if (isValidClaudeKey(key)) return 'claude';
    if (isValidGitHubToken(key)) return 'github';
    if (isValidGeminiKey(key)) return 'gemini';
    return 'unknown';
  }

  /// Validate a base URL format.
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;
    return _urlRegex.hasMatch(url);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ENCODING / DECODING HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Encode bytes to Base64.
  static String base64EncodeBytes(Uint8List bytes) => base64Encode(bytes);

  /// Decode Base64 to bytes.
  static Uint8List base64DecodeBytes(String base64Str) =>
      Uint8List.fromList(base64Decode(base64Str));

  /// Encode a string to Base64.
  static String toBase64(String input) =>
      base64Encode(utf8.encode(input));

  /// Decode a Base64 string.
  static String fromBase64(String base64Str) =>
      utf8.decode(base64Decode(base64Str));

  /// Constant-time comparison to prevent timing attacks.
  ///
  /// Returns `true` if [a] and [b] are equal.
  static bool secureCompare(String a, String b) {
    if (a.length != b.length) return false;

    var result = 0;
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);

    for (var i = 0; i < aBytes.length; i++) {
      result |= aBytes[i] ^ bBytes[i];
    }

    return result == 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONSTANTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Minimum recommended API key length.
  static const int minApiKeyLength = 20;

  /// Recommended token length for generated secrets.
  static const int recommendedTokenLength = 32;

  /// AES-256 key length in bytes.
  static const int aes256KeyLength = 32;

  /// AES GCM IV length in bytes.
  static const int aesGcmIvLength = 12;

  /// AES GCM authentication tag length in bytes.
  static const int aesGcmTagLength = 16;
}
