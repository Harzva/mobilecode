// lib/services/mobile_code_helper_auth.dart
// Process-local auth token shared by the Flutter app and Helper client.

import 'dart:convert';
import 'dart:math';

class MobileCodeHelperAuth {
  MobileCodeHelperAuth._();

  static final String token = _generateToken();

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
