// lib/providers/security_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/biometric_service.dart';
import '../services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable security state managed by [SecurityNotifier].
///
/// Tracks:
/// - Whether biometric auth is enabled
/// - Current biometric availability
/// - Last successful authentication timestamp
/// - Session validity and timeout
/// - Security level assessment
/// - Initialization status
@immutable
class SecurityState {
  /// Whether the secure storage service is initialized.
  final bool isInitialized;

  /// Whether biometric protection is enabled for secure storage.
  final bool biometricEnabled;

  /// Whether biometric hardware is available on this device.
  final bool biometricAvailable;

  /// Whether biometrics are enrolled and ready to use.
  final bool biometricEnrolled;

  /// Human-readable name of the primary biometric method.
  final String biometricName;

  /// Timestamp of last successful biometric authentication.
  final DateTime? lastAuthTime;

  /// Whether the current session is within the timeout window.
  final bool isSessionActive;

  /// Device security level assessment.
  final BiometricSecurityLevel securityLevel;

  /// Whether a tamper check has been performed.
  final bool tamperCheckCompleted;

  /// Whether the device passed tamper checks.
  final bool deviceIsSecure;

  /// Loading state for async operations.
  final bool isLoading;

  /// Last error message, if any.
  final String? errorMessage;

  const SecurityState({
    this.isInitialized = false,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
    this.biometricEnrolled = false,
    this.biometricName = 'None',
    this.lastAuthTime,
    this.isSessionActive = false,
    this.securityLevel = BiometricSecurityLevel.none,
    this.tamperCheckCompleted = false,
    this.deviceIsSecure = true,
    this.isLoading = false,
    this.errorMessage,
  });

  SecurityState copyWith({
    bool? isInitialized,
    bool? biometricEnabled,
    bool? biometricAvailable,
    bool? biometricEnrolled,
    String? biometricName,
    DateTime? lastAuthTime,
    bool? isSessionActive,
    BiometricSecurityLevel? securityLevel,
    bool? tamperCheckCompleted,
    bool? deviceIsSecure,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SecurityState(
      isInitialized: isInitialized ?? this.isInitialized,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricEnrolled: biometricEnrolled ?? this.biometricEnrolled,
      biometricName: biometricName ?? this.biometricName,
      lastAuthTime: lastAuthTime ?? this.lastAuthTime,
      isSessionActive: isSessionActive ?? this.isSessionActive,
      securityLevel: securityLevel ?? this.securityLevel,
      tamperCheckCompleted: tamperCheckCompleted ?? this.tamperCheckCompleted,
      deviceIsSecure: deviceIsSecure ?? this.deviceIsSecure,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  /// Reset error message while keeping other fields.
  SecurityState clearError() => copyWith(errorMessage: null);

  @override
  String toString() {
    return 'SecurityState('
        'init: $isInitialized, '
        'bioEnabled: $biometricEnabled, '
        'bioAvail: $biometricAvailable, '
        'level: ${securityLevel.name}, '
        'sessionActive: $isSessionActive, '
        'deviceSecure: $deviceIsSecure)';
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider for the secure storage service singleton.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Provider for the biometric service.
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// Notifier that manages security state.
///
/// Handles:
/// - Service initialization
/// - Biometric enable/disable toggling
/// - Session management and timeout
/// - Tamper detection checks
/// - Error state
class SecurityNotifier extends StateNotifier<SecurityState> {
  final SecureStorageService _secureStorage;
  final BiometricService _biometricService;

  Timer? _sessionTimer;

  /// Session timeout duration.
  static const Duration sessionTimeout = Duration(minutes: 5);

  SecurityNotifier({
    required SecureStorageService secureStorage,
    required BiometricService biometricService,
  })  : _secureStorage = secureStorage,
        _biometricService = biometricService,
        super(const SecurityState()) {
    debugPrint('[SecurityNotifier] Created');
  }

  // -- Lifecycle ----------------------------------------------------------

  /// Initialize the security subsystem.
  ///
  /// 1. Initializes secure storage.
  /// 2. Checks biometric availability.
  /// 3. Assesses security level.
  /// 4. Runs tamper detection.
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 1. Initialize secure storage.
      await _secureStorage.initialize();

      // 2. Check biometrics.
      final bioAvailable = await _biometricService.canCheckBiometrics();
      final bioTypes = await _biometricService.getAvailableBiometrics();
      final bioEnrolled = bioTypes.isNotEmpty;
      final bioName = await _biometricService.getBiometricName();
      final securityLevel =
          await _biometricService.getRecommendedSecurityLevel();

      // 3. Read stored biometric preference.
      final bioEnabled = _secureStorage.isBiometricRequired;

      // 4. Run tamper detection.
      final tamperReport = await TamperDetector.runFullCheck();
      final deviceIsSecure = tamperReport['isSecure'] as bool;

      state = state.copyWith(
        isInitialized: true,
        biometricEnabled: bioEnabled,
        biometricAvailable: bioAvailable,
        biometricEnrolled: bioEnrolled,
        biometricName: bioName,
        securityLevel: securityLevel,
        tamperCheckCompleted: true,
        deviceIsSecure: deviceIsSecure,
        isLoading: false,
        errorMessage: null,
      );

      // Start session timer.
      _startSessionTimer();

      debugPrint('[SecurityNotifier] Initialized: $state');
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Initialization failed: $e',
      );
      debugPrint('[SecurityNotifier] Initialization error: $e');
    }
  }

  /// Dispose resources.
  @override
  void dispose() {
    _sessionTimer?.cancel();
    _secureStorage.dispose();
    super.dispose();
    debugPrint('[SecurityNotifier] Disposed');
  }

  // -- Biometric Controls -------------------------------------------------

  /// Enable biometric protection for secure storage.
  Future<bool> enableBiometric() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // Verify biometrics are available.
      if (!state.biometricAvailable) {
        throw Exception('Biometric authentication is not available');
      }

      await _secureStorage.setBiometricRequired(true);

      state = state.copyWith(
        biometricEnabled: true,
        isLoading: false,
        errorMessage: null,
      );

      debugPrint('[SecurityNotifier] Biometric enabled');
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to enable biometric: $e',
      );
      return false;
    }
  }

  /// Disable biometric protection.
  Future<bool> disableBiometric() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _secureStorage.setBiometricRequired(false);

      state = state.copyWith(
        biometricEnabled: false,
        isLoading: false,
        errorMessage: null,
      );

      debugPrint('[SecurityNotifier] Biometric disabled');
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to disable biometric: $e',
      );
      return false;
    }
  }

  /// Toggle biometric protection (enable if disabled, disable if enabled).
  Future<bool> toggleBiometric() async {
    if (state.biometricEnabled) {
      return disableBiometric();
    } else {
      return enableBiometric();
    }
  }

  /// Authenticate with biometrics (updates session state).
  Future<bool> authenticate() async {
    state = state.copyWith(errorMessage: null);

    try {
      final success = await _secureStorage.authenticateWithBiometric(
        reason: 'Authenticate to access secure storage',
      );

      if (success) {
        state = state.copyWith(
          lastAuthTime: DateTime.now(),
          isSessionActive: true,
          errorMessage: null,
        );
        _startSessionTimer();
      }

      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Authentication failed: $e');
      return false;
    }
  }

  // -- Session Management -------------------------------------------------

  /// Lock the security session.
  void lockSession() {
    _secureStorage.lockSession();
    _sessionTimer?.cancel();

    state = state.copyWith(
      lastAuthTime: null,
      isSessionActive: false,
    );

    debugPrint('[SecurityNotifier] Session locked');
  }

  /// Refresh the session timeout.
  void refreshSession() {
    if (state.lastAuthTime != null) {
      state = state.copyWith(
        lastAuthTime: DateTime.now(),
        isSessionActive: true,
      );
      _startSessionTimer();
    }
  }

  /// Start / restart the session timeout timer.
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSessionTimeout(),
    );
  }

  /// Check if the session has timed out.
  void _checkSessionTimeout() {
    if (state.lastAuthTime == null) return;

    final elapsed = DateTime.now().difference(state.lastAuthTime!);
    if (elapsed > sessionTimeout && state.isSessionActive) {
      lockSession();
    }
  }

  // -- Security Checks ----------------------------------------------------

  /// Re-run tamper detection checks.
  Future<void> runTamperCheck() async {
    state = state.copyWith(isLoading: true);

    try {
      final report = await TamperDetector.runFullCheck();
      final deviceIsSecure = report['isSecure'] as bool;

      state = state.copyWith(
        tamperCheckCompleted: true,
        deviceIsSecure: deviceIsSecure,
        isLoading: false,
        errorMessage: null,
      );

      debugPrint('[SecurityNotifier] Tamper check: deviceSecure=$deviceIsSecure');
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Tamper check failed: $e',
      );
    }
  }

  /// Check if the current device security level meets a minimum requirement.
  bool meetsSecurityLevel(BiometricSecurityLevel minimum) {
    final current = state.securityLevel;
    final levels = BiometricSecurityLevel.values;
    return levels.indexOf(current) >= levels.indexOf(minimum);
  }

  /// Clear any error message.
  void clearError() {
    state = state.clearError();
  }
}

// ---------------------------------------------------------------------------
// Provider Definition
// ---------------------------------------------------------------------------

/// Riverpod state notifier provider for security state.
///
/// ```dart
/// final security = ref.watch(securityProvider);
/// ref.read(securityProvider.notifier).enableBiometric();
/// ```
final securityProvider = StateNotifierProvider<SecurityNotifier, SecurityState>(
  (ref) {
    final secureStorage = ref.watch(secureStorageServiceProvider);
    final biometricService = ref.watch(biometricServiceProvider);

    return SecurityNotifier(
      secureStorage: secureStorage,
      biometricService: biometricService,
    );
  },
);

// ---------------------------------------------------------------------------
// Convenience Selectors
// ---------------------------------------------------------------------------

/// Provider that exposes only whether biometrics are available.
final biometricAvailableProvider = Provider<bool>((ref) {
  return ref.watch(securityProvider).biometricAvailable;
});

/// Provider that exposes only whether biometrics are enabled.
final biometricEnabledProvider = Provider<bool>((ref) {
  return ref.watch(securityProvider).biometricEnabled;
});

/// Provider that exposes whether the session is active.
final sessionActiveProvider = Provider<bool>((ref) {
  return ref.watch(securityProvider).isSessionActive;
});

/// Provider that exposes whether the device is secure.
final deviceSecureProvider = Provider<bool>((ref) {
  return ref.watch(securityProvider).deviceIsSecure;
});

/// Provider that exposes the security level.
final securityLevelProvider = Provider<BiometricSecurityLevel>((ref) {
  return ref.watch(securityProvider).securityLevel;
});

// ---------------------------------------------------------------------------
// Provider for API key secure storage operations
// ---------------------------------------------------------------------------

/// Provider for securely storing and retrieving API keys.
final secureApiKeyProvider = Provider<SecureApiKeyOperations>((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return SecureApiKeyOperations(secureStorage: secureStorage);
});

/// Encapsulates API key operations through secure storage.
class SecureApiKeyOperations {
  final SecureStorageService _secureStorage;

  const SecureApiKeyOperations({required SecureStorageService secureStorage})
      : _secureStorage = secureStorage;

  /// Store an API key securely.
  Future<void> store(String provider, String apiKey) async {
    await _secureStorage.storeApiKey(provider, apiKey);
  }

  /// Retrieve a stored API key.
  Future<String?> retrieve(String provider) async {
    return _secureStorage.getApiKey(provider);
  }

  /// Delete a stored API key.
  Future<void> delete(String provider) async {
    await _secureStorage.deleteApiKey(provider);
  }

  /// List all providers with stored keys.
  Future<List<String>> listProviders() async {
    return _secureStorage.getStoredProviders();
  }

  /// Check if a provider has a stored key.
  Future<bool> hasKey(String provider) async {
    return _secureStorage.contains('apikey_$provider');
  }
}
