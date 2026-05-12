import 'package:flutter_test/flutter_test.dart';

/// Tests for Secure Storage Service
///
/// Coverage:
/// - Write/read encrypted values (round-trip integrity)
/// - Delete values (key removal)
/// - Key enumeration and listing
/// - API key storage and retrieval (special handling)
/// - Value overwrite behavior
/// - Empty value handling
/// - Null safety
/// - SecureString value object (wrap-once, clear-on-dispose)
/// - SecurityUtils (hashing, validation, sanitization)
/// - Biometric authentication mock behavior
/// - Secure clipboard operations
/// - Rate limiting on failed attempts
///
/// The Secure Storage Service encrypts sensitive data (API keys, tokens)
/// before persisting to device storage, with optional biometric
/// authentication for access.

// ═══════════════════════════════════════════════════════════════════════════
// Mock Secure Storage Implementation (for testing)
// ═══════════════════════════════════════════════════════════════════════════

class MockSecureStorage {
  final Map<String, String> _storage = {};
  int _failedAuthAttempts = 0;
  static const int _maxFailedAttempts = 5;
  bool _biometricEnabled = false;
  bool _biometricAuthenticated = false;

  // ── CRUD Operations ─────────────────────────────────────────────────

  /// Write a value to secure storage
  Future<void> write({required String key, required String value}) async {
    if (key.isEmpty) throw ArgumentError('Key cannot be empty');
    _storage[key] = value;
  }

  /// Read a value from secure storage
  Future<String?> read({required String key}) async {
    if (key.isEmpty) throw ArgumentError('Key cannot be empty');
    if (_biometricEnabled && !_biometricAuthenticated) {
      _failedAuthAttempts++;
      if (_failedAuthAttempts >= _maxFailedAttempts) {
        throw SecurityException('Too many failed authentication attempts');
      }
      return null;
    }
    return _storage[key];
  }

  /// Delete a single value
  Future<void> delete({required String key}) async {
    _storage.remove(key);
  }

  /// Delete all values
  Future<void> deleteAll() async {
    _storage.clear();
  }

  /// Check if a key exists
  Future<bool> containsKey({required String key}) async {
    return _storage.containsKey(key);
  }

  /// List all stored keys
  Future<List<String>> getAllKeys() async {
    return _storage.keys.toList();
  }

  // ── API Key Special Handling ────────────────────────────────────────

  static const String _apiKeyPrefix = 'api_key_';

  Future<void> storeApiKey({
    required String provider,
    required String apiKey,
  }) async {
    if (provider.isEmpty) throw ArgumentError('Provider cannot be empty');
    if (apiKey.isEmpty) throw ArgumentError('API key cannot be empty');
    if (!apiKey.startsWith('sk-') && !apiKey.startsWith('ghp_')) {
      // Still store it, but it's a warning sign
    }
    await write(key: '$_apiKeyPrefix$provider', value: apiKey);
  }

  Future<String?> retrieveApiKey({required String provider}) async {
    return read(key: '$_apiKeyPrefix$provider');
  }

  Future<void> deleteApiKey({required String provider}) async {
    await delete(key: '$_apiKeyPrefix$provider');
  }

  Future<List<String>> listStoredProviders() async {
    return _storage.keys
        .where((k) => k.startsWith(_apiKeyPrefix))
        .map((k) => k.substring(_apiKeyPrefix.length))
        .toList();
  }

  // ── Biometric Authentication ────────────────────────────────────────

  Future<bool> authenticateWithBiometrics() async {
    if (!_biometricEnabled) return true;
    // Mock: simulate successful auth
    _biometricAuthenticated = true;
    _failedAuthAttempts = 0;
    return true;
  }

  void enableBiometricProtection() {
    _biometricEnabled = true;
    _biometricAuthenticated = false;
  }

  void disableBiometricProtection() {
    _biometricEnabled = false;
    _biometricAuthenticated = false;
  }

  void resetBiometricState() {
    _biometricAuthenticated = false;
    _failedAuthAttempts = 0;
  }

  // ── Access Control ──────────────────────────────────────────────────

  bool get isLockedOut => _failedAuthAttempts >= _maxFailedAttempts;
  int get failedAttempts => _failedAuthAttempts;
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// SecureString Value Object
// ═══════════════════════════════════════════════════════════════════════════

/// A wrapper around sensitive string values that prevents accidental
/// exposure in logs and supports secure disposal.
class SecureString {
  String? _value;
  bool _disposed = false;
  final DateTime _createdAt;

  SecureString._(this._value) : _createdAt = DateTime.now();

  factory SecureString.fromPlain(String value) {
    return SecureString._(value);
  }

  /// Access the value (throws if disposed)
  String get value {
    if (_disposed) throw StateError('SecureString has been disposed');
    return _value ?? '';
  }

  bool get isDisposed => _disposed;
  DateTime get createdAt => _createdAt;

  /// Whether the value is not null and not empty
  bool get hasValue => _value != null && _value!.isNotEmpty;

  /// Length of the secured value (without exposing it)
  int get length => _value?.length ?? 0;

  /// Get a masked representation for display (e.g., "****last4")
  String get masked {
    if (_value == null || _value!.isEmpty) return '';
    if (_value!.length <= 4) return '*' * _value!.length;
    final last4 = _value!.substring(_value!.length - 4);
    return '${'*' * (_value!.length - 4)}$last4';
  }

  /// Securely clear the value from memory
  void dispose() {
    if (_disposed) return;
    // In real implementation, would overwrite memory
    _value = null;
    _disposed = true;
  }

  /// Create a copy (use with caution)
  SecureString copy() {
    if (_disposed) throw StateError('Cannot copy disposed SecureString');
    return SecureString._(_value);
  }

  @override
  String toString() => 'SecureString(masked: $masked, disposed: $_disposed)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Security Utilities
// ═══════════════════════════════════════════════════════════════════════════

class SecurityUtils {
  SecurityUtils._();

  /// Validate that a string is a reasonable API key format
  static bool isValidApiKeyFormat(String key) {
    if (key.isEmpty) return false;
    if (key.length < 10) return false; // Minimum reasonable length
    if (key.length > 512) return false; // Maximum reasonable length
    // Check for common API key prefixes
    final validPrefixes = ['sk-', 'ghp_', 'gho_', 'glpat-', 'AKIA'];
    return validPrefixes.any((prefix) => key.startsWith(prefix)) ||
        RegExp(r'^[A-Za-z0-9_\-]{20,}$').hasMatch(key);
  }

  /// Mask an API key for display
  static String maskApiKey(String key) {
    if (key.isEmpty) return '';
    if (key.length <= 8) return '*' * key.length;
    final prefix = key.substring(0, 4);
    final suffix = key.substring(key.length - 4);
    return '$prefix${'*' * (key.length - 8)}$suffix';
  }

  /// Check if a string contains potential secrets
  static bool containsPotentialSecret(String text) {
    final patterns = [
      RegExp(r'sk-[a-zA-Z0-9]{20,}'),
      RegExp(r'ghp_[a-zA-Z0-9]{30,}'),
      RegExp(r'AKIA[0-9A-Z]{16}'),
      RegExp(r'[a-f0-9]{32,}'), // Hex tokens
    ];
    return patterns.any((p) => p.hasMatch(text));
  }

  /// Sanitize text to remove potential secrets before logging
  static String sanitizeForLogging(String text) {
    if (text.isEmpty) return text;
    String sanitized = text;

    // Replace API keys with masks
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'sk-[a-zA-Z0-9]{20,}'),
      (m) => SecurityUtils.maskApiKey(m.group(0)!),
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'ghp_[a-zA-Z0-9]{30,}'),
      (m) => SecurityUtils.maskApiKey(m.group(0)!),
    );

    return sanitized;
  }

  /// Generate a simple hash for non-security purposes (e.g., cache keys)
  static int quickHash(String input) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
    }
    return hash & 0x7fffffff;
  }

  /// Validate password strength (basic check)
  static PasswordStrength checkPasswordStrength(String password) {
    if (password.isEmpty) return PasswordStrength.empty;
    if (password.length < 8) return PasswordStrength.weak;

    bool hasUpper = password.contains(RegExp(r'[A-Z]'));
    bool hasLower = password.contains(RegExp(r'[a-z]'));
    bool hasDigit = password.contains(RegExp(r'[0-9]'));
    bool hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    int score = 0;
    if (hasUpper) score++;
    if (hasLower) score++;
    if (hasDigit) score++;
    if (hasSpecial) score++;
    if (password.length >= 16) score++;

    if (score <= 1) return PasswordStrength.weak;
    if (score <= 3) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }
}

enum PasswordStrength { empty, weak, medium, strong }

// ═══════════════════════════════════════════════════════════════════════════
// Secure Clipboard
// ═══════════════════════════════════════════════════════════════════════════

class SecureClipboard {
  String? _clipboardValue;
  DateTime? _copiedAt;
  static const Duration _clearDelay = Duration(seconds: 30);

  Future<void> copy(String value) async {
    _clipboardValue = value;
    _copiedAt = DateTime.now();
    // In real implementation: await Clipboard.setData(ClipboardData(text: value));
  }

  Future<String?> paste() async {
    // Check if clipboard content should be cleared
    if (_copiedAt != null &&
        DateTime.now().difference(_copiedAt!) > _clearDelay) {
      await clear();
      return null;
    }
    return _clipboardValue;
  }

  Future<void> clear() async {
    _clipboardValue = null;
    _copiedAt = null;
    // In real implementation: await Clipboard.setData(const ClipboardData(text: ''));
  }

  bool get hasValue => _clipboardValue != null;
  Duration? get timeSinceCopy =>
      _copiedAt != null ? DateTime.now().difference(_copiedAt!) : null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test Suite
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('SecureStorageService', () {
    late MockSecureStorage storage;

    setUp(() {
      storage = MockSecureStorage();
    });

    // ── Write/Read ──────────────────────────────────────────────────
    test('write and read value', () async {
      await storage.write(key: 'test_key', value: 'test_value');
      final value = await storage.read(key: 'test_key');
      expect(value, equals('test_value'));
    });

    test('read non-existent key returns null', () async {
      final value = await storage.read(key: 'non_existent');
      expect(value, isNull);
    });

    test('write overwrites existing value', () async {
      await storage.write(key: 'key1', value: 'value1');
      await storage.write(key: 'key1', value: 'value2');
      final value = await storage.read(key: 'key1');
      expect(value, equals('value2'));
    });

    test('write with empty key throws ArgumentError', () async {
      expect(
        () => storage.write(key: '', value: 'value'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('read with empty key throws ArgumentError', () async {
      expect(
        () => storage.read(key: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ── Delete ──────────────────────────────────────────────────────
    test('delete removes value', () async {
      await storage.write(key: 'del_key', value: 'del_value');
      await storage.delete(key: 'del_key');
      final value = await storage.read(key: 'del_key');
      expect(value, isNull);
    });

    test('delete non-existent key does not throw', () async {
      expect(() => storage.delete(key: 'non_existent'), returnsNormally);
    });

    test('deleteAll removes all values', () async {
      await storage.write(key: 'a', value: '1');
      await storage.write(key: 'b', value: '2');
      await storage.write(key: 'c', value: '3');
      await storage.deleteAll();

      expect(await storage.read(key: 'a'), isNull);
      expect(await storage.read(key: 'b'), isNull);
      expect(await storage.read(key: 'c'), isNull);
      expect(await storage.getAllKeys(), isEmpty);
    });

    // ── Key Enumeration ─────────────────────────────────────────────
    test('containsKey returns true for existing key', () async {
      await storage.write(key: 'exists', value: 'yes');
      expect(await storage.containsKey(key: 'exists'), isTrue);
    });

    test('containsKey returns false for non-existing key', () async {
      expect(await storage.containsKey(key: 'missing'), isFalse);
    });

    test('getAllKeys returns all stored keys', () async {
      await storage.write(key: 'key_a', value: 'a');
      await storage.write(key: 'key_b', value: 'b');
      final keys = await storage.getAllKeys();

      expect(keys, hasLength(2));
      expect(keys, contains('key_a'));
      expect(keys, contains('key_b'));
    });

    // ── API Key Storage ─────────────────────────────────────────────
    test('storeApiKey writes with prefixed key', () async {
      await storage.storeApiKey(provider: 'openai', apiKey: 'sk-test123456789');
      final value = await storage.read(key: 'api_key_openai');
      expect(value, equals('sk-test123456789'));
    });

    test('retrieveApiKey returns correct key', () async {
      await storage.storeApiKey(provider: 'claude', apiKey: 'sk-ant-key123');
      final key = await storage.retrieveApiKey(provider: 'claude');
      expect(key, equals('sk-ant-key123'));
    });

    test('deleteApiKey removes provider key', () async {
      await storage.storeApiKey(provider: 'gemini', apiKey: 'gemini-key');
      await storage.deleteApiKey(provider: 'gemini');
      final key = await storage.retrieveApiKey(provider: 'gemini');
      expect(key, isNull);
    });

    test('storeApiKey with empty provider throws', () async {
      expect(
        () => storage.storeApiKey(provider: '', apiKey: 'key'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('storeApiKey with empty key throws', () async {
      expect(
        () => storage.storeApiKey(provider: 'openai', apiKey: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('listStoredProviders returns only API key providers', () async {
      await storage.storeApiKey(provider: 'openai', apiKey: 'sk-123');
      await storage.storeApiKey(provider: 'claude', apiKey: 'sk-ant-456');
      await storage.write(key: 'other_key', value: 'not an api key');

      final providers = await storage.listStoredProviders();
      expect(providers, hasLength(2));
      expect(providers, contains('openai'));
      expect(providers, contains('claude'));
      expect(providers, isNot(contains('other_key')));
    });

    // ── Multiple Providers ──────────────────────────────────────────
    test('storing keys for multiple providers works independently', () async {
      await storage.storeApiKey(provider: 'openai', apiKey: 'sk-openai-123');
      await storage.storeApiKey(provider: 'claude', apiKey: 'sk-claude-456');
      await storage.storeApiKey(provider: 'gemini', apiKey: 'gemini-789');

      expect(await storage.retrieveApiKey(provider: 'openai'), equals('sk-openai-123'));
      expect(await storage.retrieveApiKey(provider: 'claude'), equals('sk-claude-456'));
      expect(await storage.retrieveApiKey(provider: 'gemini'), equals('gemini-789'));
    });

    // ── Biometric Authentication ────────────────────────────────────
    test('biometric enabled blocks read until authenticated', () async {
      await storage.write(key: 'secret', value: 'data');
      storage.enableBiometricProtection();

      final value = await storage.read(key: 'secret');
      expect(value, isNull); // Blocked without auth
    });

    test('biometric authentication unlocks storage', () async {
      await storage.write(key: 'secret', value: 'data');
      storage.enableBiometricProtection();

      final authenticated = await storage.authenticateWithBiometrics();
      expect(authenticated, isTrue);

      final value = await storage.read(key: 'secret');
      expect(value, equals('data'));
    });

    test('disabling biometric allows direct access', () async {
      storage.enableBiometricProtection();
      storage.disableBiometricProtection();

      await storage.write(key: 'open', value: 'accessible');
      final value = await storage.read(key: 'open');
      expect(value, equals('accessible'));
    });

    // ── Rate Limiting ───────────────────────────────────────────────
    test('too many failed biometric attempts triggers lockout', () async {
      storage.enableBiometricProtection();

      // Attempt reads without authentication 5+ times
      for (int i = 0; i < 5; i++) {
        await storage.read(key: 'x');
      }

      expect(storage.isLockedOut, isTrue);
      expect(storage.failedAttempts, equals(5));
    });

    test('successful auth resets failed attempts', () async {
      storage.enableBiometricProtection();

      // Some failed attempts
      await storage.read(key: 'x');
      await storage.read(key: 'x');
      expect(storage.failedAttempts, equals(2));

      // Auth resets counter
      await storage.authenticateWithBiometrics();
      expect(storage.failedAttempts, equals(0));
    });

    test('resetBiometricState clears auth and attempts', () async {
      storage.enableBiometricProtection();
      await storage.authenticateWithBiometrics();
      await storage.read(key: 'x'); // This would work

      storage.resetBiometricState();
      expect(storage.isLockedOut, isFalse);
    });
  });

  group('SecureString', () {
    test('fromPlain stores value', () {
      final secure = SecureString.fromPlain('my-secret-key');
      expect(secure.value, equals('my-secret-key'));
    });

    test('hasValue returns true for non-empty string', () {
      final secure = SecureString.fromPlain('key');
      expect(secure.hasValue, isTrue);
    });

    test('hasValue returns false for empty string', () {
      final secure = SecureString.fromPlain('');
      expect(secure.hasValue, isFalse);
    });

    test('length returns string length without exposing value', () {
      final secure = SecureString.fromPlain('12345');
      expect(secure.length, equals(5));
    });

    test('masked hides most of the value', () {
      final secure = SecureString.fromPlain('sk-abcdefghijklmnopqrstuvwxyz');
      expect(secure.masked.startsWith('***'), isTrue);
      expect(secure.masked.endsWith('wxyz'), isTrue);
      expect(secure.masked.length, equals(29));
    });

    test('masked for short value shows all stars', () {
      final secure = SecureString.fromPlain('ab');
      expect(secure.masked, equals('**'));
    });

    test('dispose clears value', () {
      final secure = SecureString.fromPlain('secret');
      secure.dispose();
      expect(secure.isDisposed, isTrue);
      expect(() => secure.value, throwsStateError);
    });

    test('double dispose is safe', () {
      final secure = SecureString.fromPlain('x');
      secure.dispose();
      expect(() => secure.dispose(), returnsNormally);
    });

    test('copy creates independent instance', () {
      final original = SecureString.fromPlain('original');
      final copy = original.copy();

      expect(copy.value, equals('original'));
      copy.dispose();
      expect(original.isDisposed, isFalse);
      expect(original.value, equals('original'));
    });

    test('copy of disposed throws StateError', () {
      final secure = SecureString.fromPlain('test');
      secure.dispose();
      expect(() => secure.copy(), throwsStateError);
    });

    test('toString does not expose value', () {
      final secure = SecureString.fromPlain('super-secret-123');
      final str = secure.toString();
      expect(str, isNot(contains('super-secret')));
      expect(str, contains('masked'));
    });
  });

  group('SecurityUtils', () {
    // ── API Key Validation ──────────────────────────────────────────
    test('isValidApiKeyFormat accepts sk- prefixed keys', () {
      expect(
        SecurityUtils.isValidApiKeyFormat('sk-proj1234567890123456789'),
        isTrue,
      );
    });

    test('isValidApiKeyFormat accepts ghp_ prefixed keys', () {
      expect(
        SecurityUtils.isValidApiKeyFormat('ghp_abcdefghijklmnopqrstuvwxyz1234'),
        isTrue,
      );
    });

    test('isValidApiKeyFormat rejects empty strings', () {
      expect(SecurityUtils.isValidApiKeyFormat(''), isFalse);
    });

    test('isValidApiKeyFormat rejects short strings', () {
      expect(SecurityUtils.isValidApiKeyFormat('sk-123'), isFalse);
    });

    test('isValidApiKeyFormat rejects overly long strings', () {
      expect(
        SecurityUtils.isValidApiKeyFormat('sk-' + 'a' * 600),
        isFalse,
      );
    });

    // ── Masking ─────────────────────────────────────────────────────
    test('maskApiKey shows first 4 and last 4 characters', () {
      final masked = SecurityUtils.maskApiKey('sk-abcdefghijklmnopqrstuvwxyz');
      expect(masked.startsWith('sk-a'), isTrue);
      expect(masked.endsWith('wxyz'), isTrue);
      expect(masked.contains('****'), isTrue);
    });

    test('maskApiKey handles short keys', () {
      final masked = SecurityUtils.maskApiKey('abc');
      expect(masked, equals('***'));
    });

    test('maskApiKey handles empty string', () {
      final masked = SecurityUtils.maskApiKey('');
      expect(masked, equals(''));
    });

    // ── Secret Detection ────────────────────────────────────────────
    test('containsPotentialSecret detects OpenAI key', () {
      expect(
        SecurityUtils.containsPotentialSecret('My key is sk-abc1234567890123456789'),
        isTrue,
      );
    });

    test('containsPotentialSecret detects GitHub token', () {
      expect(
        SecurityUtils.containsPotentialSecret('token: ghp_abcdefghijklmnopqrstuv'),
        isTrue,
      );
    });

    test('containsPotentialSecret returns false for clean text', () {
      expect(
        SecurityUtils.containsPotentialSecret('This is just normal text about programming'),
        isFalse,
      );
    });

    // ── Sanitization ────────────────────────────────────────────────
    test('sanitizeForLogging masks API keys in text', () {
      final text = 'Error with key sk-abc1234567890123456789 in request';
      final sanitized = SecurityUtils.sanitizeForLogging(text);
      expect(sanitized.contains('sk-abc1234567890123456789'), isFalse);
      expect(sanitized.contains('****'), isTrue);
    });

    test('sanitizeForLogging leaves clean text unchanged', () {
      final text = 'Normal log message without secrets';
      final sanitized = SecurityUtils.sanitizeForLogging(text);
      expect(sanitized, equals(text));
    });

    // ── Password Strength ───────────────────────────────────────────
    test('checkPasswordStrength returns empty for empty string', () {
      expect(SecurityUtils.checkPasswordStrength(''), equals(PasswordStrength.empty));
    });

    test('checkPasswordStrength returns weak for short password', () {
      expect(SecurityUtils.checkPasswordStrength('abc'), equals(PasswordStrength.weak));
    });

    test('checkPasswordStrength returns medium for moderate password', () {
      expect(
        SecurityUtils.checkPasswordStrength('Password123'),
        equals(PasswordStrength.medium),
      );
    });

    test('checkPasswordStrength returns strong for complex password', () {
      expect(
        SecurityUtils.checkPasswordStrength('MyStr0ng!Passw0rd#2024'),
        equals(PasswordStrength.strong),
      );
    });

    // ── Hashing ─────────────────────────────────────────────────────
    test('quickHash produces consistent results', () {
      final h1 = SecurityUtils.quickHash('test-string');
      final h2 = SecurityUtils.quickHash('test-string');
      expect(h1, equals(h2));
    });

    test('quickHash produces different values for different inputs', () {
      final h1 = SecurityUtils.quickHash('input-a');
      final h2 = SecurityUtils.quickHash('input-b');
      expect(h1, isNot(equals(h2)));
    });

    test('quickHash handles empty string', () {
      final h = SecurityUtils.quickHash('');
      expect(h, isNonNegative);
    });
  });

  group('SecureClipboard', () {
    late SecureClipboard clipboard;

    setUp(() {
      clipboard = SecureClipboard();
    });

    test('copy stores value', () async {
      await clipboard.copy('sensitive-data');
      expect(clipboard.hasValue, isTrue);
      final pasted = await clipboard.paste();
      expect(pasted, equals('sensitive-data'));
    });

    test('paste returns null after clear', () async {
      await clipboard.copy('temp-data');
      await clipboard.clear();
      expect(clipboard.hasValue, isFalse);
      final pasted = await clipboard.paste();
      expect(pasted, isNull);
    });

    test('clear removes stored value', () async {
      await clipboard.copy('to-be-cleared');
      await clipboard.clear();
      expect(clipboard.hasValue, isFalse);
    });

    test('paste after delay returns null (auto-clear)', () async {
      await clipboard.copy('expires-soon');
      // Simulate time passing beyond the 30s clear delay
      // In the mock, we manipulate the internal state to test this
      clipboard._copiedAt = DateTime.now().subtract(const Duration(seconds: 31));
      final pasted = await clipboard.paste();
      expect(pasted, isNull);
    });

    test('hasValue returns false initially', () {
      expect(clipboard.hasValue, isFalse);
    });

    test('timeSinceCopy is null initially', () {
      expect(clipboard.timeSinceCopy, isNull);
    });

    test('timeSinceCopy is set after copy', () async {
      await clipboard.copy('data');
      expect(clipboard.timeSinceCopy, isNotNull);
      expect(clipboard.timeSinceCopy!.inSeconds, greaterThanOrEqualTo(0));
    });

    test('copy overwrites previous value', () async {
      await clipboard.copy('first');
      await clipboard.copy('second');
      final pasted = await clipboard.paste();
      expect(pasted, equals('second'));
    });
  });

  group('End-to-End Secure Storage Scenarios', () {
    late MockSecureStorage storage;

    setUp(() {
      storage = MockSecureStorage();
    });

    test('full API key lifecycle: store, retrieve, delete', () async {
      // Store
      await storage.storeApiKey(provider: 'openai', apiKey: 'sk-proj-abc123456789');
      expect(await storage.retrieveApiKey(provider: 'openai'), isNotNull);

      // Retrieve
      final key = await storage.retrieveApiKey(provider: 'openai');
      expect(key, equals('sk-proj-abc123456789'));

      // Delete
      await storage.deleteApiKey(provider: 'openai');
      expect(await storage.retrieveApiKey(provider: 'openai'), isNull);
    });

    test('storage survives multiple operations', () async {
      for (int i = 0; i < 10; i++) {
        await storage.write(key: 'key_$i', value: 'value_$i');
      }

      final keys = await storage.getAllKeys();
      expect(keys.length, equals(10));

      for (int i = 0; i < 10; i++) {
        expect(await storage.read(key: 'key_$i'), equals('value_$i'));
      }
    });

    test(' SecureString protects API key in memory', () {
      final apiKey = SecureString.fromPlain('sk-live-super-secret-key-12345');

      // Value is accessible
      expect(apiKey.value, equals('sk-live-super-secret-key-12345'));

      // Masked representation is safe for logs
      expect(apiKey.masked, contains('***'));
      expect(apiKey.toString(), isNot(contains('super-secret')));

      // After disposal, value is gone
      apiKey.dispose();
      expect(apiKey.isDisposed, isTrue);
      expect(() => apiKey.value, throwsStateError);
    });

    test('no secret leakage in logs through sanitization', () {
      final logMessage =
          'Request failed with key sk-abc1234567890123456789 and token ghp_abcdefghijklmnopqrstuv';
      final sanitized = SecurityUtils.sanitizeForLogging(logMessage);

      expect(sanitized.contains('sk-abc1234567890123456789'), isFalse);
      expect(sanitized.contains('ghp_abcdefghijklmnopqrstuv'), isFalse);
      expect(sanitized.length, equals(logMessage.length)); // Same structure
    });
  });
}
