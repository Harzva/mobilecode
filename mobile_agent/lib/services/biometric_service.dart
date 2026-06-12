// lib/services/biometric_service.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception thrown when biometric authentication fails.
class BiometricException implements Exception {
  final String message;
  final BiometricErrorCode code;
  final dynamic originalError;

  const BiometricException({
    required this.message,
    this.code = BiometricErrorCode.unknown,
    this.originalError,
  });

  @override
  String toString() =>
      'BiometricException [${code.name}]: $message${originalError != null ? ' | $originalError' : ''}';
}

/// Error codes for biometric authentication failures.
enum BiometricErrorCode {
  notAvailable,
  notEnrolled,
  passcodeNotSet,
  lockedOut,
  permanentlyLockedOut,
  userCancel,
  userFallback,
  unknown,
}

// ---------------------------------------------------------------------------
// Biometric Authentication Service
// ---------------------------------------------------------------------------

/// Cross-platform biometric authentication service.
///
/// Provides a unified interface for:
/// - Fingerprint / Touch ID
/// - Face ID / Face Recognition
/// - Iris scan (where supported)
/// - Device PIN / pattern fallback
///
/// ## Platform Behaviour
///
/// | Feature          | Android                     | iOS                |
/// |------------------|----------------------------|--------------------|
/// | Fingerprint      | `fingerprint`              | `touchID`          |
/// | Face             | `face` (API 29+)           | `faceID`           |
/// | Strong biometric | `strong` (Class 3, API 30+)| `biometric`        |
/// | Weak biometric   | `weak`  (Class 2, API 29+) | —                  |
///
/// ```dart
/// final bio = BiometricService();
/// final ok = await bio.authenticate(reason: 'Unlock secure vault');
/// ```
class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Cached list of available biometrics (refreshed on each call).
  List<BiometricType> _cachedBiometrics = [];

  /// Cached availability result.
  bool _cachedCanCheck = false;

  // -- Public API ---------------------------------------------------------

  /// Check if the device has any biometric hardware available.
  ///
  /// Returns `true` if biometrics can be checked on this device.
  /// Does **not** guarantee that biometrics are enrolled.
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] isDeviceSupported error: $e');
      return false;
    }
  }

  /// Check if biometrics are available and enrolled.
  ///
  /// Returns `true` if at least one biometric is enrolled and ready
  /// for authentication.
  Future<bool> canCheckBiometrics() async {
    try {
      _cachedCanCheck = await _localAuth.canCheckBiometrics;
      return _cachedCanCheck;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] canCheckBiometrics error: $e');
      _cachedCanCheck = false;
      return false;
    }
  }

  /// Get the list of enrolled biometric types on this device.
  ///
  /// Returns an empty list if biometrics are not available or not enrolled.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      _cachedBiometrics = await _localAuth.getAvailableBiometrics();
      debugPrint('[BiometricService] Available: $_cachedBiometrics');
      return List.unmodifiable(_cachedBiometrics);
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] getAvailableBiometrics error: $e');
      _cachedBiometrics = [];
      return [];
    }
  }

  /// Check if strong biometrics (Class 3 / biometric) are available.
  ///
  /// "Strong" means hardware-backed, cryptographically secure
  /// biometric authentication (fingerprint, secure face unlock).
  Future<bool> hasStrongBiometrics() async {
    final biometrics = await getAvailableBiometrics();
    if (Platform.isAndroid) {
      // On Android, strong = fingerprint + face (Class 3).
      return biometrics.contains(BiometricType.fingerprint) ||
          biometrics.contains(BiometricType.face);
    } else if (Platform.isIOS) {
      // On iOS, faceID and touchID are both strong.
      return biometrics.contains(BiometricType.face) ||
          biometrics.contains(BiometricType.fingerprint);
    }
    return false;
  }

  /// Check if weak biometrics are available.
  ///
  /// "Weak" biometrics (e.g., face unlock using camera on some
  /// Android devices) are less secure and not recommended for
  /// high-security operations.
  Future<bool> hasWeakBiometrics() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.iris);
  }

  /// Authenticate the user with biometrics.
  ///
  /// [reason] is displayed to the user in the system biometric dialog.
  /// [stickyAuth] keeps the dialog visible when the app is backgrounded.
  /// [useErrorDialogs] shows system error dialogs on failure.
  /// [sensitiveTransaction] uses stronger authentication if available.
  ///
  /// Returns `true` if authentication succeeded, `false` if cancelled
  /// or failed.
  Future<bool> authenticate({
    required String reason,
    bool stickyAuth = false,
    bool useErrorDialogs = true,
    bool sensitiveTransaction = true,
  }) async {
    try {
      // Check availability first.
      final canCheck = await canCheckBiometrics();
      if (!canCheck) {
        throw const BiometricException(
          message: 'Biometrics not available or not enrolled',
          code: BiometricErrorCode.notEnrolled,
        );
      }

      final result = await _localAuth.authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Biometric Authentication',
            cancelButton: 'Cancel',
            signInHint: 'Verify your identity',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
            localizedFallbackTitle: 'Use Passcode',
          ),
        ],
        biometricOnly: false,
        sensitiveTransaction: sensitiveTransaction,
        persistAcrossBackgrounding: stickyAuth,
      );

      debugPrint('[BiometricService] Authenticate result: $result');
      return result;
    } on PlatformException catch (e) {
      final code = _mapPlatformError(e.code);
      throw BiometricException(
        message: _humanReadableError(code),
        code: code,
        originalError: e,
      );
    } catch (e) {
      throw BiometricException(
        message: 'Authentication failed: $e',
        code: BiometricErrorCode.unknown,
        originalError: e,
      );
    }
  }

  /// Authenticate with biometrics only (no PIN / pattern fallback).
  ///
  /// This is more restrictive and provides stronger assurance that
  /// the user is physically present.
  Future<bool> authenticateBiometricOnly({
    required String reason,
    bool stickyAuth = false,
  }) async {
    try {
      final canCheck = await canCheckBiometrics();
      if (!canCheck) {
        throw const BiometricException(
          message: 'Biometrics not available or not enrolled',
          code: BiometricErrorCode.notEnrolled,
        );
      }

      final result = await _localAuth.authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Strong Biometric Required',
            cancelButton: 'Cancel',
            signInHint: 'Verify with biometric',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
            localizedFallbackTitle: '',
          ),
        ],
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: stickyAuth,
      );

      return result;
    } on PlatformException catch (e) {
      final code = _mapPlatformError(e.code);
      throw BiometricException(
        message: _humanReadableError(code),
        code: code,
        originalError: e,
      );
    } catch (e) {
      throw BiometricException(
        message: 'Biometric-only authentication failed: $e',
        code: BiometricErrorCode.unknown,
        originalError: e,
      );
    }
  }

  /// Stop an in-progress authentication.
  ///
  /// Call this when the user navigates away or cancels the operation.
  Future<bool> stopAuthentication() async {
    try {
      return await _localAuth.stopAuthentication();
    } catch (e) {
      debugPrint('[BiometricService] stopAuthentication error: $e');
      return false;
    }
  }

  // -- Informational ------------------------------------------------------

  /// Get a human-readable name for the primary biometric method.
  ///
  /// Returns "Face ID", "Touch ID", "Fingerprint", etc.
  Future<String> getBiometricName() async {
    final biometrics = await getAvailableBiometrics();

    if (Platform.isIOS) {
      if (biometrics.contains(BiometricType.face)) return 'Face ID';
      if (biometrics.contains(BiometricType.fingerprint)) return 'Touch ID';
      return 'Biometric';
    }

    if (Platform.isAndroid) {
      if (biometrics.contains(BiometricType.face)) return 'Face Unlock';
      if (biometrics.contains(BiometricType.fingerprint)) return 'Fingerprint';
      if (biometrics.contains(BiometricType.iris)) return 'Iris';
      return 'Biometric';
    }

    return 'Biometric';
  }

  /// Get a description of all available biometric types.
  Future<String> getBiometricDescription() async {
    final biometrics = await getAvailableBiometrics();
    if (biometrics.isEmpty) return 'No biometrics enrolled';

    final names = biometrics.map((b) {
      switch (b) {
        case BiometricType.face:
          return Platform.isIOS ? 'Face ID' : 'Face Unlock';
        case BiometricType.fingerprint:
          return Platform.isIOS ? 'Touch ID' : 'Fingerprint';
        case BiometricType.iris:
          return 'Iris';
        case BiometricType.strong:
          return 'Strong biometric';
        case BiometricType.weak:
          return 'Weak biometric';
      }
    }).toList();

    return names.join(', ');
  }

  /// Get the recommended security level based on available biometrics.
  Future<BiometricSecurityLevel> getRecommendedSecurityLevel() async {
    final hasStrong = await hasStrongBiometrics();
    if (hasStrong) return BiometricSecurityLevel.strong;

    final hasWeak = await hasWeakBiometrics();
    if (hasWeak) return BiometricSecurityLevel.weak;

    final canCheck = await canCheckBiometrics();
    if (canCheck) return BiometricSecurityLevel.deviceCredentials;

    return BiometricSecurityLevel.none;
  }

  // -- Private helpers ----------------------------------------------------

  /// Map platform error codes to our internal error codes.
  BiometricErrorCode _mapPlatformError(String code) {
    switch (code) {
      case 'NotAvailable':
        return BiometricErrorCode.notAvailable;
      case 'NotEnrolled':
        return BiometricErrorCode.notEnrolled;
      case 'PasscodeNotSet':
        return BiometricErrorCode.passcodeNotSet;
      case 'LockedOut':
        return BiometricErrorCode.lockedOut;
      case 'PermanentlyLockedOut':
        return BiometricErrorCode.permanentlyLockedOut;
      case 'UserCancel':
        return BiometricErrorCode.userCancel;
      case 'UserFallback':
        return BiometricErrorCode.userFallback;
      default:
        return BiometricErrorCode.unknown;
    }
  }

  /// Human-readable error message for each error code.
  String _humanReadableError(BiometricErrorCode code) {
    switch (code) {
      case BiometricErrorCode.notAvailable:
        return 'Biometric authentication is not available on this device.';
      case BiometricErrorCode.notEnrolled:
        return 'No biometrics are enrolled. Please set up biometrics in device settings.';
      case BiometricErrorCode.passcodeNotSet:
        return 'Device PIN/pattern is not set. Please configure device security first.';
      case BiometricErrorCode.lockedOut:
        return 'Too many failed attempts. Biometric authentication is temporarily locked.';
      case BiometricErrorCode.permanentlyLockedOut:
        return 'Biometric authentication is permanently locked. Please use device credentials.';
      case BiometricErrorCode.userCancel:
        return 'Authentication was cancelled by the user.';
      case BiometricErrorCode.userFallback:
        return 'User chose to use fallback authentication.';
      case BiometricErrorCode.unknown:
        return 'An unknown error occurred during biometric authentication.';
    }
  }
}

// ---------------------------------------------------------------------------
// Security Level Enum
// ---------------------------------------------------------------------------

/// Represents the available biometric security level on the device.
enum BiometricSecurityLevel {
  /// Strong hardware-backed biometric (fingerprint, secure face).
  strong,

  /// Weak biometric (camera-based face, iris).
  weak,

  /// Only device credentials available (PIN / pattern / password).
  deviceCredentials,

  /// No authentication method available.
  none,
}

// ---------------------------------------------------------------------------
// Extension for convenient checks
// ---------------------------------------------------------------------------

/// Extension methods for [BiometricSecurityLevel].
extension BiometricSecurityLevelX on BiometricSecurityLevel {
  /// Whether this level is sufficient for high-security operations.
  bool get isSecure => this == BiometricSecurityLevel.strong;

  /// Whether any authentication is available.
  bool get hasAuth => this != BiometricSecurityLevel.none;

  /// Human-readable label.
  String get label {
    switch (this) {
      case BiometricSecurityLevel.strong:
        return 'Strong (Hardware-backed)';
      case BiometricSecurityLevel.weak:
        return 'Weak (Camera-based)';
      case BiometricSecurityLevel.deviceCredentials:
        return 'Device Credentials Only';
      case BiometricSecurityLevel.none:
        return 'No Authentication';
    }
  }

  /// Recommendation message for the user.
  String get recommendation {
    switch (this) {
      case BiometricSecurityLevel.strong:
        return 'Your device supports secure biometric authentication.';
      case BiometricSecurityLevel.weak:
        return 'Your biometrics are not hardware-backed. Consider using a device with fingerprint or secure face unlock.';
      case BiometricSecurityLevel.deviceCredentials:
        return 'Please enroll biometrics in device settings for stronger security.';
      case BiometricSecurityLevel.none:
        return 'Please set up device security (PIN, pattern, or biometrics) in settings.';
    }
  }
}
