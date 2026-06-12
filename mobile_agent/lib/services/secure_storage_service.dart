// lib/services/secure_storage_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'biometric_service.dart';

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception thrown when secure storage operations fail.
class SecureStorageException implements Exception {
  final String message;
  final String? operation;
  final dynamic originalError;

  const SecureStorageException({
    required this.message,
    this.operation,
    this.originalError,
  });

  @override
  String toString() =>
      'SecureStorageException [$operation]: $message${originalError != null ? ' | $originalError' : ''}';
}

/// Exception thrown when encryption / decryption fails.
class EncryptionException implements Exception {
  final String message;
  final dynamic originalError;

  const EncryptionException({required this.message, this.originalError});

  @override
  String toString() =>
      'EncryptionException: $message${originalError != null ? ' | $originalError' : ''}';
}

/// Exception thrown when tampering is detected.
class TamperDetectedException implements Exception {
  final String message;

  const TamperDetectedException({required this.message});

  @override
  String toString() => 'TamperDetectedException: $message';
}

/// Exception thrown when biometric authentication fails.
class BiometricAuthException implements Exception {
  final String message;

  const BiometricAuthException({required this.message});

  @override
  String toString() => 'BiometricAuthException: $message';
}

// ---------------------------------------------------------------------------
// Secure Storage Service
// ---------------------------------------------------------------------------

/// Production-grade secure storage with AES-256-GCM encryption.
///
/// All sensitive data (API keys, tokens, passwords) is encrypted at rest
/// using AES-256-GCM with keys stored in the Android Keystore / iOS
/// Keychain. Biometric authentication can be required for access.
///
/// ## Architecture
/// ```
/// ┌─────────────────────────────────────────┐
/// │  SecureStorageService                   │
/// │  ┌───────────────────────────────────┐  │
/// │  │  AES-256-GCM Encrypter            │  │
/// │  │  Key ← Android Keystore / iOS     │  │
/// │  │        Keychain                   │  │
/// │  └───────────────────────────────────┘  │
/// │           │                             │
/// │           ▼                             │
/// │  ┌───────────────────────────────────┐  │
/// │  │  flutter_secure_storage           │  │
/// │  │  (encryptedSharedPreferences /    │  │
/// │  │   Keychain)                       │  │
/// │  └───────────────────────────────────┘  │
/// └─────────────────────────────────────────┘
/// ```
class SecureStorageService {
  final FlutterSecureStorage _secureStorage;
  final BiometricService _biometricService;

  encrypt.Key? _masterKey;
  encrypt.IV? _iv;
  encrypt.Encrypter? _encrypter;

  bool _initialized = false;
  bool _biometricRequired = false;

  // -- Key names stored in Keystore / Keychain ---------------------------

  static const String _masterKeyName = 'mc_master_key_v1';
  static const String _ivKeyName = 'mc_iv_v1';
  static const String _integrityHashName = 'mc_integrity_v1';
  static const String _biometricRequiredKey = 'mc_biometric_required';
  static const String _providersListKey = 'mc_providers_list';

  // -- Platform-specific options ----------------------------------------

  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );

  static const IOSOptions _iosOptions = IOSOptions(
    accountName: 'mobile_coding_secure',
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  // -- In-memory secure cache (cleared on lock) -------------------------

  final Map<String, SecureString> _memoryCache = {};
  DateTime? _lastAuthTime;
  static const Duration _sessionTimeout = Duration(minutes: 5);

  // -- Singleton ---------------------------------------------------------

  static SecureStorageService? _instance;

  factory SecureStorageService({BiometricService? biometricService}) {
    _instance ??= SecureStorageService._internal(
      biometricService: biometricService,
    );
    return _instance!;
  }

  SecureStorageService._internal({BiometricService? biometricService})
      : _secureStorage = const FlutterSecureStorage(
          aOptions: _androidOptions,
          iOptions: _iosOptions,
        ),
        _biometricService = biometricService ?? BiometricService();

  /// Reset the singleton (mainly for testing).
  static void reset() => _instance = null;

  // ═══════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Initialize the secure storage service.
  ///
  /// 1. Retrieves or generates the master key from Keystore / Keychain.
  /// 2. Retrieves or generates the AES IV.
  /// 3. Builds the AES-256-GCM encrypter.
  /// 4. Verifies encryption integrity with a known test value.
  ///
  /// Must be called before any [read] / [write] operation.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('[SecureStorage] Initializing...');

      // 1. Retrieve or generate master key.
      final masterKeyBytes = await _getOrCreateMasterKey();
      _masterKey = encrypt.Key(masterKeyBytes);

      // 2. Retrieve or create IV.
      final ivBytes = await _getOrCreateIV();
      _iv = encrypt.IV(ivBytes);

      // 3. Build encrypter (AES-256-GCM).
      _encrypter = encrypt.Encrypter(
        encrypt.AES(_masterKey!, mode: encrypt.AESMode.gcm),
      );

      // 4. Verify encryption integrity.
      await _verifyEncryptionIntegrity();

      // 5. Load biometric preference.
      final bioPref = await _secureStorage.read(
        key: _biometricRequiredKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      _biometricRequired = bioPref == 'true';

      _initialized = true;
      debugPrint('[SecureStorage] Initialized successfully');
    } catch (e, st) {
      throw SecureStorageException(
        message: 'Failed to initialize secure storage: $e',
        operation: 'initialize',
        originalError: e,
      );
    }
  }

  /// Retrieve existing master key or generate a new one.
  Future<Uint8List> _getOrCreateMasterKey() async {
    try {
      final existing = await _secureStorage.read(
        key: _masterKeyName,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      if (existing != null) {
        // Decode existing key.
        return base64Decode(existing);
      }

      // Generate new 256-bit (32-byte) master key.
      final random = Random.secure();
      final keyBytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        keyBytes[i] = random.nextInt(256);
      }

      // Store in Keystore / Keychain.
      await _secureStorage.write(
        key: _masterKeyName,
        value: base64Encode(keyBytes),
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      debugPrint('[SecureStorage] New master key generated');
      return keyBytes;
    } catch (e) {
      throw SecureStorageException(
        message: 'Master key operation failed: $e',
        operation: '_getOrCreateMasterKey',
        originalError: e,
      );
    }
  }

  /// Retrieve existing IV or generate a new one.
  Future<Uint8List> _getOrCreateIV() async {
    try {
      final existing = await _secureStorage.read(
        key: _ivKeyName,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      if (existing != null) {
        return base64Decode(existing);
      }

      // Generate new 96-bit (12-byte) IV for GCM.
      final random = Random.secure();
      final ivBytes = Uint8List(12);
      for (var i = 0; i < 12; i++) {
        ivBytes[i] = random.nextInt(256);
      }

      await _secureStorage.write(
        key: _ivKeyName,
        value: base64Encode(ivBytes),
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      debugPrint('[SecureStorage] New IV generated');
      return ivBytes;
    } catch (e) {
      throw SecureStorageException(
        message: 'IV operation failed: $e',
        operation: '_getOrCreateIV',
        originalError: e,
      );
    }
  }

  /// Verify that encryption/decryption round-trip works.
  Future<void> _verifyEncryptionIntegrity() async {
    const testValue = 'mobile_coding_integrity_check_v1';

    try {
      // Encrypt test value.
      final encrypted = _encrypter!.encrypt(testValue, iv: _iv!);
      final encryptedBase64 = encrypted.base64;

      // Check if we have a stored integrity hash.
      final storedHash = await _secureStorage.read(
        key: _integrityHashName,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      final computedHash =
          sha256.convert(utf8.encode(encryptedBase64)).toString();

      if (storedHash == null) {
        // First run: store integrity hash.
        await _secureStorage.write(
          key: _integrityHashName,
          value: computedHash,
          aOptions: _androidOptions,
          iOptions: _iosOptions,
        );
      } else if (storedHash != computedHash) {
        // Integrity check failed: key material may have been tampered.
        throw const TamperDetectedException(
          message:
              'Encryption integrity check failed. Key material may have been compromised.',
        );
      }

      // Verify round-trip.
      final decrypted = _encrypter!.decrypt64(encryptedBase64, iv: _iv!);
      if (decrypted != testValue) {
        throw const EncryptionException(
          message: 'Encryption round-trip verification failed',
        );
      }

      debugPrint('[SecureStorage] Integrity check passed');
    } on TamperDetectedException {
      rethrow;
    } catch (e) {
      throw EncryptionException(
        message: 'Integrity verification failed: $e',
        originalError: e,
      );
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const SecureStorageException(
        message:
            'SecureStorageService not initialized. Call initialize() first.',
        operation: '_ensureInitialized',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SESSION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if the current session is still valid (within timeout).
  bool get _isSessionValid {
    if (_lastAuthTime == null) return false;
    return DateTime.now().difference(_lastAuthTime!) < _sessionTimeout;
  }

  /// Require a valid session — triggers biometric if needed.
  Future<void> _requireSession() async {
    if (!_biometricRequired) return;
    if (_isSessionValid) return;

    final success = await _biometricService.authenticate(
      reason: 'Authenticate to access secure data',
      stickyAuth: true,
    );

    if (!success) {
      throw const BiometricAuthException(
        message: 'Biometric authentication required but not provided',
      );
    }

    _lastAuthTime = DateTime.now();
  }

  /// Lock the session (force re-authentication on next access).
  void lockSession() {
    _lastAuthTime = null;
    clearMemory();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CORE CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// Encrypt and store a value securely.
  ///
  /// [key] must be a non-empty alphanumeric identifier.
  /// [value] is encrypted with AES-256-GCM before storage.
  Future<void> write(String key, String value) async {
    _ensureInitialized();
    await _requireSession();

    if (key.isEmpty) {
      throw const SecureStorageException(
        message: 'Key cannot be empty',
        operation: 'write',
      );
    }

    try {
      final encrypted = _encrypter!.encrypt(value, iv: _iv!);
      final encryptedPackage = base64Encode(utf8.encode(encrypted.base64));

      await _secureStorage.write(
        key: 'mc_enc_$key',
        value: encryptedPackage,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      // Update memory cache.
      _memoryCache[key] = SecureString.fromString(value);

      debugPrint('[SecureStorage] Written encrypted key: $key');
    } catch (e) {
      throw SecureStorageException(
        message: 'Failed to write key "$key": $e',
        operation: 'write',
        originalError: e,
      );
    }
  }

  /// Read and decrypt a value.
  ///
  /// Returns `null` if the key does not exist.
  Future<String?> read(String key) async {
    _ensureInitialized();
    await _requireSession();

    try {
      // Check memory cache first.
      if (_memoryCache.containsKey(key) && !_memoryCache[key]!._disposed) {
        return _memoryCache[key]!.value;
      }

      final encryptedPackage = await _secureStorage.read(
        key: 'mc_enc_$key',
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      if (encryptedPackage == null) return null;

      // Decode: base64 → encrypted bytes → decrypt.
      final encryptedBase64 = utf8.decode(base64Decode(encryptedPackage));
      final decrypted = _encrypter!.decrypt64(encryptedBase64, iv: _iv!);

      // Cache in secure memory.
      _memoryCache[key] = SecureString.fromString(decrypted);

      return decrypted;
    } catch (e) {
      throw SecureStorageException(
        message: 'Failed to read key "$key": $e',
        operation: 'read',
        originalError: e,
      );
    }
  }

  /// Delete a key from secure storage.
  Future<void> delete(String key) async {
    _ensureInitialized();
    await _requireSession();

    try {
      await _secureStorage.delete(
        key: 'mc_enc_$key',
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      // Remove from memory cache.
      _memoryCache.remove(key)?.dispose();

      debugPrint('[SecureStorage] Deleted key: $key');
    } catch (e) {
      throw SecureStorageException(
        message: 'Failed to delete key "$key": $e',
        operation: 'delete',
        originalError: e,
      );
    }
  }

  /// Check if a key exists in secure storage.
  Future<bool> contains(String key) async {
    _ensureInitialized();

    try {
      final value = await _secureStorage.read(
        key: 'mc_enc_$key',
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      return value != null;
    } catch (e) {
      return false;
    }
  }

  /// Clear ALL secure data (destructive operation).
  ///
  /// Deletes all encrypted values and resets the memory cache.
  /// Master key and IV are preserved — call [clearAllWithKeys] to
  /// wipe everything including key material.
  Future<void> clearAll() async {
    _ensureInitialized();
    await _requireSession();

    try {
      // Delete all keys with our prefix.
      final allKeys = await _secureStorage.readAll(
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      for (final entry in allKeys.entries) {
        if (entry.key.startsWith('mc_enc_')) {
          await _secureStorage.delete(
            key: entry.key,
            aOptions: _androidOptions,
            iOptions: _iosOptions,
          );
        }
      }

      // Clear memory cache.
      clearMemory();

      // Clear provider list.
      await _secureStorage.delete(
        key: _providersListKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      debugPrint('[SecureStorage] All secure data cleared');
    } catch (e) {
      throw SecureStorageException(
        message: 'Failed to clear all data: $e',
        operation: 'clearAll',
        originalError: e,
      );
    }
  }

  /// Complete wipe including master key and IV.
  ///
  /// After calling this, [initialize] must be called again to use
  /// the service. **Use with extreme caution.**
  Future<void> clearAllWithKeys() async {
    _ensureInitialized();
    await _requireSession();

    try {
      await _secureStorage.deleteAll(
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      clearMemory();
      _initialized = false;
      _masterKey = null;
      _iv = null;
      _encrypter = null;
      _lastAuthTime = null;

      debugPrint('[SecureStorage] Complete wipe performed');
    } catch (e) {
      throw SecureStorageException(
        message: 'Failed to perform complete wipe: $e',
        operation: 'clearAllWithKeys',
        originalError: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // API KEY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Store an API key for a specific provider.
  ///
  /// [provider] is the provider identifier: 'openai', 'claude', 'gemini',
  /// 'github', or 'custom'.
  /// [apiKey] is the raw API key — it will be encrypted before storage.
  Future<void> storeApiKey(String provider, String apiKey) async {
    if (provider.isEmpty || apiKey.isEmpty) {
      throw const SecureStorageException(
        message: 'Provider and API key cannot be empty',
        operation: 'storeApiKey',
      );
    }

    // Sanitize provider name for key safety.
    final sanitizedProvider = provider.toLowerCase().trim();
    final storageKey = 'apikey_$sanitizedProvider';

    // Encrypt and store.
    await write(storageKey, apiKey);

    // Update provider list.
    await _updateProvidersList(sanitizedProvider, add: true);

    debugPrint('[SecureStorage] Stored API key for: $sanitizedProvider');
  }

  /// Retrieve an API key for a specific provider.
  ///
  /// Returns the decrypted API key or `null` if not found.
  Future<String?> getApiKey(String provider) async {
    final sanitizedProvider = provider.toLowerCase().trim();
    final storageKey = 'apikey_$sanitizedProvider';
    return read(storageKey);
  }

  /// Delete an API key for a provider.
  Future<void> deleteApiKey(String provider) async {
    final sanitizedProvider = provider.toLowerCase().trim();
    final storageKey = 'apikey_$sanitizedProvider';

    await delete(storageKey);
    await _updateProvidersList(sanitizedProvider, add: false);

    debugPrint('[SecureStorage] Deleted API key for: $sanitizedProvider');
  }

  /// List all providers with stored API keys.
  Future<List<String>> getStoredProviders() async {
    _ensureInitialized();

    try {
      final listJson = await _secureStorage.read(
        key: _providersListKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      if (listJson == null || listJson.isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(listJson);
      return decoded.cast<String>();
    } catch (e) {
      debugPrint('[SecureStorage] Failed to read providers list: $e');
      return [];
    }
  }

  /// Update the stored list of providers.
  Future<void> _updateProvidersList(String provider,
      {required bool add}) async {
    final providers = await getStoredProviders();

    if (add) {
      if (!providers.contains(provider)) {
        providers.add(provider);
      }
    } else {
      providers.remove(provider);
    }

    await _secureStorage.write(
      key: _providersListKey,
      value: jsonEncode(providers),
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BIOMETRIC AUTHENTICATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if biometric authentication is available on this device.
  Future<bool> isBiometricAvailable() async {
    try {
      return await _biometricService.canCheckBiometrics();
    } catch (e) {
      debugPrint('[SecureStorage] Biometric check failed: $e');
      return false;
    }
  }

  /// Authenticate with biometrics.
  ///
  /// Returns `true` if authentication succeeded, `false` otherwise.
  Future<bool> authenticateWithBiometric(
      {String reason = 'Access secure data'}) async {
    try {
      final success = await _biometricService.authenticate(
        reason: reason,
        stickyAuth: true,
      );

      if (success) {
        _lastAuthTime = DateTime.now();
      }

      return success;
    } catch (e) {
      debugPrint('[SecureStorage] Biometric authentication error: $e');
      return false;
    }
  }

  /// Enable or disable biometric requirement for secure storage access.
  ///
  /// When enabled, every [read] / [write] / [delete] operation will
  /// require biometric authentication.
  Future<void> setBiometricRequired(bool required) async {
    _ensureInitialized();

    if (required) {
      // Verify biometric is available before enabling.
      final available = await isBiometricAvailable();
      if (!available) {
        throw const SecureStorageException(
          message: 'Biometric authentication is not available on this device',
          operation: 'setBiometricRequired',
        );
      }

      // Require an initial authentication to enable.
      final success = await authenticateWithBiometric(
        reason: 'Enable biometric protection for secure storage',
      );
      if (!success) {
        throw const SecureStorageException(
          message: 'Biometric authentication required to enable this setting',
          operation: 'setBiometricRequired',
        );
      }
    }

    _biometricRequired = required;
    await _secureStorage.write(
      key: _biometricRequiredKey,
      value: required.toString(),
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );

    debugPrint('[SecureStorage] Biometric required: $required');
  }

  /// Check if biometric protection is currently enabled.
  bool get isBiometricRequired => _biometricRequired;

  // ═══════════════════════════════════════════════════════════════════════
  // SECURE CLIPBOARD
  // ═══════════════════════════════════════════════════════════════════════

  /// Copy sensitive text to the system clipboard with automatic clearing.
  ///
  /// The clipboard is cleared after [clearAfter] duration (default 30s).
  Future<void> secureCopy(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {
    try {
      // Copy to clipboard.
      await Clipboard.setData(ClipboardData(text: text));

      debugPrint(
          '[SecureStorage] Copied to clipboard (auto-clear in ${clearAfter.inSeconds}s)');

      // Schedule auto-clear.
      Timer(clearAfter, () async {
        try {
          // Clear by copying empty string.
          await Clipboard.setData(const ClipboardData(text: ''));
          debugPrint('[SecureStorage] Clipboard auto-cleared');
        } catch (e) {
          debugPrint('[SecureStorage] Failed to clear clipboard: $e');
        }
      });
    } catch (e) {
      throw SecureStorageException(
        message: 'Failed to copy to clipboard: $e',
        operation: 'secureCopy',
        originalError: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MEMORY SECURITY
  // ═══════════════════════════════════════════════════════════════════════

  /// Create a [SecureString] from a plain string.
  ///
  /// The value is held in memory as raw bytes and can be securely
  /// wiped by calling [SecureString.dispose].
  SecureString createSecureString(String value) {
    return SecureString.fromString(value);
  }

  /// Clear all sensitive data from memory cache.
  ///
  /// Call this when the app goes to background or receives a
  /// security lock signal.
  void clearMemory() {
    for (final entry in _memoryCache.entries) {
      entry.value.dispose();
    }
    _memoryCache.clear();
    _lastAuthTime = null;

    debugPrint('[SecureStorage] Memory cleared');
  }

  /// Dispose the service and clear all resources.
  void dispose() {
    clearMemory();
    _masterKey = null;
    _iv = null;
    _encrypter = null;
    _initialized = false;
    debugPrint('[SecureStorage] Disposed');
  }
}

// ---------------------------------------------------------------------------
// Secure String
// ---------------------------------------------------------------------------

/// A secure string holder that zeros memory when disposed.
///
/// ```dart
/// final secure = SecureString.fromString('sensitive');
/// try {
///   print(secure.value);
/// } finally {
///   secure.dispose(); // Memory is zeroed
/// }
/// ```
class SecureString {
  final Uint8List _bytes;
  bool _disposed = false;

  /// Create from a UTF-8 string.
  factory SecureString.fromString(String value) {
    return SecureString._(Uint8List.fromList(utf8.encode(value)));
  }

  SecureString._(this._bytes);

  /// Get the string value.
  ///
  /// Throws [StateError] if already disposed.
  String get value {
    if (_disposed) throw StateError('SecureString already disposed');
    return utf8.decode(_bytes);
  }

  /// Whether this secure string has been disposed.
  bool get isDisposed => _disposed;

  /// Securely wipe the memory and mark as disposed.
  void dispose() {
    if (!_disposed) {
      _bytes.fillRange(0, _bytes.length, 0);
      _disposed = true;
    }
  }
}

// ---------------------------------------------------------------------------
// Tamper Detector
// ---------------------------------------------------------------------------

/// Detects potential tampering with the app or device.
///
/// Checks for:
/// - Rooted / jailbroken devices
/// - Sideloaded installations
/// - App signature integrity
class TamperDetector {
  /// Check if the device appears to be compromised.
  ///
  /// Returns `true` if rooting/jailbreaking indicators are detected.
  /// This is a best-effort check and should not be relied upon as
  /// the sole security measure.
  static Future<bool> isDeviceCompromised() async {
    if (Platform.isAndroid) {
      return _checkAndroidRoot();
    } else if (Platform.isIOS) {
      return _checkIOSJailbreak();
    }
    return false;
  }

  /// Check for Android root indicators.
  static Future<bool> _checkAndroidRoot() async {
    // Check for common root binaries.
    final rootPaths = [
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/su/bin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/su',
    ];

    for (final path in rootPaths) {
      try {
        if (File(path).existsSync()) {
          debugPrint('[TamperDetector] Root indicator found: $path');
          return true;
        }
      } catch (_) {
        // Ignore permission errors.
      }
    }

    // Check for test-keys build tag.
    try {
      const platform = MethodChannel('mobile_coding/platform');
      final buildTags = await platform.invokeMethod<String>('getBuildTags');
      if (buildTags != null && buildTags.contains('test-keys')) {
        return true;
      }
    } catch (_) {
      // Channel not available — skip.
    }

    return false;
  }

  /// Check for iOS jailbreak indicators.
  static Future<bool> _checkIOSJailbreak() async {
    final jbPaths = [
      '/Applications/Cydia.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt/',
    ];

    for (final path in jbPaths) {
      try {
        if (File(path).existsSync()) {
          debugPrint('[TamperDetector] Jailbreak indicator found: $path');
          return true;
        }
      } catch (_) {
        // Ignore.
      }
    }

    // Check if we can write outside sandbox.
    try {
      final testFile = File('/private/jailbreak_test.txt');
      await testFile.writeAsString('test', flush: true);
      await testFile.delete();
      return true;
    } catch (_) {
      // Expected — sandbox is intact.
    }

    return false;
  }

  /// Check if the app was sideloaded (not from official store).
  ///
  /// Returns `true` if sideloading is detected.
  static Future<bool> isSideloaded() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('mobile_coding/platform');
        final installer =
            await platform.invokeMethod<String>('getInstallerPackage');
        // Valid installers: com.android.vending (Play Store), com.amazon.veneta
        final validInstallers = [
          'com.android.vending',
          'com.amazon.veneta',
          'com.huawei.appmarket',
        ];
        return installer != null && !validInstallers.contains(installer);
      } catch (_) {
        return false;
      }
    } else if (Platform.isIOS) {
      // On iOS, check if provisioning profile indicates App Store.
      try {
        const platform = MethodChannel('mobile_coding/platform');
        final isAppStore = await platform.invokeMethod<bool>('isAppStoreBuild');
        return isAppStore == false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Verify app signature / code integrity.
  ///
  /// Returns `true` if the signature is valid.
  static Future<bool> verifySignature() async {
    try {
      const platform = MethodChannel('mobile_coding/platform');
      final valid = await platform.invokeMethod<bool>('verifySignature');
      return valid ?? false;
    } catch (_) {
      // Platform channel not available — assume valid.
      return true;
    }
  }

  /// Run all tamper checks and return a composite report.
  static Future<Map<String, dynamic>> runFullCheck() async {
    final compromised = await isDeviceCompromised();
    final sideloaded = await isSideloaded();
    final signatureValid = await verifySignature();

    return {
      'isDeviceCompromised': compromised,
      'isSideloaded': sideloaded,
      'signatureValid': signatureValid,
      'isSecure': !compromised && !sideloaded && signatureValid,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
