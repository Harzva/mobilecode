# MobileCode Flutter App - Comprehensive Security Audit Report

**Audit Date:** 2025-01-28
**Auditor:** Senior Security Engineer
**Scope:** `/mnt/agents/output/mobile_agent/lib/` + Android configuration files
**Total Files Scanned:** 60+ Dart files, 4 XML configuration files

---

## Executive Summary

The MobileCode Flutter application was subjected to a comprehensive security audit across 7 vulnerability categories. **13 security findings** were identified, including **2 Critical**, **4 High**, **4 Medium**, and **3 Low** severity issues. The most severe finding is a complete SSL/TLS certificate validation bypass that makes the app vulnerable to Man-in-the-Middle (MITM) attacks.

### Risk Summary
| Severity | Count | Categories |
|----------|-------|------------|
| Critical | 2 | SSL bypass, Command injection |
| High | 4 | Logging secrets, SSH injection, Termux injection, Debug config |
| Medium | 4 | Unencrypted storage, Insecure random, HTTP preset, Permissions |
| Low | 3 | debugPrint in production, Missing path validation |

---

## Findings

---

### 🔴 CRITICAL-001: SSL/TLS Certificate Validation Completely Bypassed

**File:** `lib/services/api_service.dart:148-158`

**Issue:** The `_configureSsl()` method unconditionally accepts ALL SSL certificates by returning `true` from `badCertificateCallback`, regardless of certificate validity. This completely disables SSL/TLS certificate validation, making the application vulnerable to Man-in-the-Middle (MITM) attacks.

```dart
client.badCertificateCallback =
    (X509Certificate cert, String host, int port) {
  // In production, validate certificates properly.
  // For now, accept all certificates (useful for custom/self-signed endpoints).
  return true;  // <-- ACCEPTS ALL CERTIFICATES
};
```

**Impact:** Attackers on the same network (or via DNS hijacking) can intercept all HTTPS traffic including API keys, tokens, and sensitive code. The app is also vulnerable to rogue Wi-Fi hotspot attacks.

**Fix Recommendation:** Only allow certificate bypass in debug mode with explicit user opt-in. In production, always validate certificates. Provide a UI toggle for advanced users to add custom CA certificates.

---

### 🔴 CRITICAL-002: SSH Remote Command Injection

**File:** `lib/services/ssh_service.dart:275-277`, `348-350`, `573`

**Issue:** The `execute()` and `deleteRemotePath()` methods construct shell commands by directly interpolating user-controlled `command` and `remotePath` strings without any sanitization.

```dart
final fullCommand = effectiveWd != null
    ? 'cd "$effectiveWd" && $command'  // command is user-controlled
    : command;

// In deleteRemotePath:
await execute(hostId, 'rm -rf "$remotePath"');  // remotePath is user-controlled
```

**Impact:** An attacker who controls the command or path input can inject arbitrary shell commands. For example, a path like `"; rm -rf / #"` would execute destructive commands on the remote server.

**Fix Recommendation:** Use `session.execute()` from dartssh2 with separate arguments instead of shell string interpolation. Sanitize all path inputs with a whitelist approach.

---

### 🟠 HIGH-001: LogInterceptor Logs API Keys in Debug Mode

**File:** `lib/services/api_service.dart:96-107`

**Issue:** The LogInterceptor is configured with `requestBody: true` and `responseBody: true`, which logs the full HTTP request and response bodies to the console. In debug mode, this can expose API keys, authentication tokens, and sensitive user data in logcat/system logs.

```dart
if (kDebugMode) {
  dio.interceptors.add(
    LogInterceptor(
      requestHeader: true,
      requestBody: true,    // <-- logs full request body (may contain API keys)
      responseHeader: false,
      responseBody: true,   // <-- logs full response body
      error: true,
      logPrint: (obj) => debugPrint('[ApiService] $obj'),
    ),
  );
}
```

**Impact:** API keys and sensitive data may leak through system logs (logcat on Android, Console on iOS). Third-party libraries or analytics services may harvest these logs.

**Fix Recommendation:** Redact sensitive headers (Authorization, x-api-key) from log output. Never log request/response bodies that may contain credentials.

---

### 🟠 HIGH-002: Termux Service Command Injection

**File:** `lib/services/termux_service.dart:543`, `710-711`

**Issue:** The `execute()` method passes user-controlled `command` strings directly to the terminal service. The `installApk()` method interpolates `apkPath` directly into a shell command without sanitization.

```dart
final result = await execute('pm install -r "$apkPath"');
// debugPrint also logs the command which may contain sensitive paths
debugPrint('[TermuxService] Executing: $command${workingDir != null ? ' (in $workingDir)' : ''}');
```

**Impact:** Path traversal via malicious APK paths. An attacker could potentially execute arbitrary commands through crafted path inputs.

**Fix Recommendation:** Validate and sanitize all file paths. Use parameterized execution instead of string interpolation.

---

### 🟠 HIGH-003: Debug Network Security Config Exposes Private Networks

**File:** `android/app/src/debug/res/xml/network_security_config_debug.xml:14-18`

**Issue:** The debug network security configuration permits cleartext traffic for entire IP ranges including all 10.x.x.x and 192.168.x.x addresses, not just localhost. This is overly permissive even for debug builds.

```xml
<domain-config cleartextTrafficPermitted="true">
  <domain includeSubdomains="true">10.0.0.0</domain>
  <domain includeSubdomains="true">192.168.0.0</domain>
</domain-config>
```

**Impact:** During development, traffic to any private network is sent in plaintext. If a debug build is accidentally distributed, sensitive API keys and code will be transmitted without encryption.

**Fix Recommendation:** Restrict to `localhost` and `127.0.0.1` only. Document the security implications for developers.

---

### 🟠 HIGH-004: GitHub Provider Logs Token and User Info

**File:** `lib/providers/github_provider.dart:142-166`

**Issue:** The GitHub authentication provider logs sensitive authentication events including token status and authenticated user identity via `debugPrint`.

```dart
debugPrint('[GitHubAuthNotifier] Empty token provided');
debugPrint('[GitHubAuthNotifier] Authenticated as ${service.currentUser}');
debugPrint('[GitHubAuthNotifier] Auth error: $e');
```

**Impact:** Authentication tokens and user identities may be exposed through system logs.

**Fix Recommendation:** Remove or mask sensitive data in all debugPrint statements.

---

### 🟡 MEDIUM-001: API Keys Stored Unencrypted in SQLite

**File:** `lib/services/local_database_service.dart:180-192`, `489`

**Issue:** The `api_configs` table stores API keys in a plaintext `TEXT` column without encryption. The database is stored on the device's file system and could be accessed by rooted devices or backup extraction.

```dart
// Schema:
api_key TEXT,  // Stored as plaintext

// Insert:
'api_key': config['apiKey'] ?? config['api_key'],  // No encryption
```

**Impact:** If the device is compromised, all API keys are immediately accessible.

**Fix Recommendation:** Store API keys using `FlutterSecureStorage` instead of SQLite. Never persist API keys in plaintext database tables.

---

### 🟡 MEDIUM-002: Insecure Random Number Generation for Feedback IDs

**File:** `lib/services/feedback_learning_service.dart:571-575`

**Issue:** Uses `math.Random()` (non-cryptographic PRNG) to generate feedback IDs. This is predictable and could allow ID collision or prediction attacks.

```dart
final random = math.Random().nextInt(10000);
```

**Impact:** Predictable feedback IDs could allow unauthorized data access or collision attacks.

**Fix Recommendation:** Use `Random.secure()` from `dart:math` for all security-sensitive random generation.

---

### 🟡 MEDIUM-003: HTTP URL Preset in API Manager

**File:** `lib/screens/api_manager_screen.dart:1041`

**Issue:** The LocalAI preset uses `http://localhost:8080/v1` which is an unencrypted HTTP connection. While localhost is generally safe, this pattern encourages HTTP usage.

```dart
_buildPresetChip(
  label: 'LocalAI',
  url: 'http://localhost:8080/v1',  // Unencrypted HTTP
  model: 'ggml-gpt4all-j',
),
```

**Fix Recommendation:** Use `https://` for all presets or clearly warn users about the HTTP connection.

---

### 🟡 MEDIUM-004: Overly Broad Android Permissions

**File:** `android/app/src/main/AndroidManifest.xml:22-38`

**Issues:**
1. `MANAGE_EXTERNAL_STORAGE` (line 22) grants access to ALL device storage - extremely dangerous
2. `REQUEST_INSTALL_PACKAGES` (line 38) allows installing APKs from unknown sources
3. `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` combined with scoped storage exemption

**Impact:**
- `MANAGE_EXTERNAL_STORAGE` could allow malicious code to access sensitive files across the device
- `REQUEST_INSTALL_PACKAGES` is a high-risk permission that could be exploited

**Fix Recommendation:** Remove `MANAGE_EXTERNAL_STORAGE` if not absolutely necessary. Use scoped storage APIs instead. Document why each permission is required.

---

### 🟢 LOW-001: debugPrint Statements in Production Code

**File:** Multiple files across the codebase

**Issue:** Over 100+ `debugPrint` statements exist across providers, services, and screens. While `debugPrint` is stripped in release builds on iOS, on Android these can still appear in logcat under certain conditions. Some statements log sensitive operational data.

**Files affected:** `providers/settings_provider.dart`, `providers/team_provider.dart`, `providers/github_provider.dart`, `services/termux_service.dart`, `services/ssh_service.dart`, and 20+ others.

**Fix Recommendation:** Replace all `debugPrint` with a proper logging service that supports log level configuration and redaction of sensitive data.

---

### 🟢 LOW-002: Path Traversal in Self-Action Registry

**File:** `lib/services/self_action_registry.dart:163-170`

**Issue:** The `editor.createFile` and `editor.openFile` actions accept file paths from AI-generated parameters without validation. A malicious AI response could specify paths like `../../../etc/passwd`.

```dart
final path = params['path'] as String?;
// No validation - path could contain ../ sequences
await controller.createFile(path);
```

**Fix Recommendation:** Validate all file paths against a whitelist of allowed directories. Reject paths containing `..` or absolute paths outside the project directory.

---

### 🟢 LOW-003: Error Messages May Leak Sensitive Information

**File:** `lib/services/api_service.dart:454-460`

**Issue:** Error messages from the API service include the original error message which could contain internal paths, API response details, or other sensitive information.

```dart
case DioExceptionType.unknown:
default:
  message = 'An unexpected error occurred: ${error.message}';
```

**Fix Recommendation:** Log full error details internally but return generic error messages to the UI.

---

## Remediation Priority Matrix

| Priority | Finding | Effort | Files |
|----------|---------|--------|-------|
| P0 | CRITICAL-001 SSL Bypass | Medium | `api_service.dart` |
| P0 | CRITICAL-002 SSH Injection | Medium | `ssh_service.dart` |
| P1 | HIGH-001 LogInterceptor | Low | `api_service.dart` |
| P1 | HIGH-002 Termux Injection | Medium | `termux_service.dart` |
| P1 | HIGH-003 Debug Network Config | Low | `network_security_config_debug.xml` |
| P1 | HIGH-004 GitHub Logging | Low | `github_provider.dart` |
| P2 | MEDIUM-001 SQLite API Keys | High | `local_database_service.dart` |
| P2 | MEDIUM-002 Insecure Random | Low | `feedback_learning_service.dart` |
| P2 | MEDIUM-003 HTTP Preset | Low | `api_manager_screen.dart` |
| P2 | MEDIUM-004 Permissions | Low | `AndroidManifest.xml` |
| P3 | LOW-001 debugPrint | Medium | Multiple files |
| P3 | LOW-002 Path Traversal | Medium | `self_action_registry.dart` |
| P3 | LOW-003 Error Leakage | Low | `api_service.dart` |

---

## Positive Security Findings

1. **Secure Storage Service**: `secure_storage_service.dart` properly uses AES-256-GCM with Android Keystore/iOS Keychain for sensitive data
2. **Biometric Authentication**: Available for protecting API key access
3. **Network Security Config**: Proper certificate pinning for known API endpoints
4. **cleartextTraffic="false"**: Correctly disabled in production manifest
5. **allowBackup="false"**: Prevents data backup leaks
6. **Input Sanitization**: `security_utils.dart` contains proper API key masking utilities
7. **Code Patterns**: SQL queries in `local_database_service.dart` use parameterized queries (whereArgs) properly
