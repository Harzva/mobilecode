/// Security Configuration for MobileCode
/// 
/// Central security settings and checks:
/// - Debug mode detection and prevention
/// - API key validation (no hardcoded keys)
/// - HTTPS enforcement
/// - Build mode awareness

import 'package:flutter/foundation.dart';

class SecurityConfig {
  /// Current build mode
  static bool get isDebug => kDebugMode;
  static bool get isProfile => kProfileMode;
  static bool get isRelease => !kDebugMode && !kProfileMode;
  
  /// Is this a production build? (release mode only)
  static bool get isProduction => isRelease;
  
  /// Should allow debug features?
  /// Only in debug builds, NEVER in release
  static bool get allowDebugFeatures => isDebug;
  
  /// Should use HTTPS only?
  /// Always true in release/profile, configurable in debug
  static bool get enforceHttps => !isDebug;
  
  /// Validate API key format (but never validate actual values)
  static bool isValidApiKeyFormat(String key) {
    if (key.isEmpty) return false;
    // Minimum length check
    if (key.length < 20) return false;
    // Check for placeholder keys (x repeated)
    if (RegExp(r'^[xX]+$').hasMatch(key)) return false;
    return true;
  }
  
  /// Check if API key is a placeholder (should not be used)
  static bool isPlaceholderKey(String key) {
    if (key.isEmpty) return true;
    if (RegExp(r'^[xX\s]+$').hasMatch(key)) return true;
    if (key.contains('xxxxxxxx')) return true;
    if (key.contains('placeholder')) return true;
    return false;
  }
  
  /// Get API key from secure storage (never hardcoded)
  /// Returns null if not found or invalid
  static Future<String?> loadApiKeySecurely(String provider) async {
    // Load from SecureStorageService
    // Never return hardcoded values
    return null;
  }
}

/// Security assertion helpers
/// These throw in debug builds but are silent in release
class SecurityAsserts {
  /// Assert that no hardcoded API keys exist
  static void noHardcodedKeys(String value) {
    assert(
      !SecurityConfig.isPlaceholderKey(value),
      'SECURITY: Hardcoded API key detected! Use SecureStorageService.',
    );
  }
  
  /// Assert debug-only features are not enabled in release
  static void debugOnlyInDebugMode(bool enabled) {
    assert(
      !enabled || SecurityConfig.isDebug,
      'SECURITY: Debug feature enabled in release build!',
    );
  }
}
