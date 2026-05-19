import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_deep_service.dart';

class GitHubOAuthLaunchResult {
  const GitHubOAuthLaunchResult({
    required this.startedOAuth,
    required this.message,
  });

  final bool startedOAuth;
  final String message;
}

class GitHubOAuthCallbackResult {
  const GitHubOAuthCallbackResult({
    required this.handled,
    required this.success,
    this.message,
  });

  final bool handled;
  final bool success;
  final String? message;
}

class GitHubOAuthFlow {
  static const _systemTools = MethodChannel('mobilecode/system_tools');
  static const _stateKey = 'github_oauth_pending_state';
  static const clientId = String.fromEnvironment('MOBILECODE_GITHUB_OAUTH_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('MOBILECODE_GITHUB_OAUTH_CLIENT_SECRET');
  static const redirectUri = String.fromEnvironment(
    'MOBILECODE_GITHUB_OAUTH_REDIRECT_URI',
    defaultValue: 'mobilecode://github/oauth',
  );
  static const scopes = 'repo user notifications workflow';

  static bool get canExchange => clientId.isNotEmpty && clientSecret.isNotEmpty;

  static String get authModeLabel => canExchange ? 'OAuth Web Login' : 'Browser token setup';

  static String get authModeDescription => canExchange
      ? 'Sign in through GitHub, then MobileCode will exchange the callback code for a stored token.'
      : 'Open GitHub in the browser, create a token, then return and paste it above.';

  static String get actionLabel => canExchange ? 'Login with GitHub OAuth' : 'Open GitHub token page';

  static Future<GitHubOAuthLaunchResult> launchAuthorization() async {
    const tokenSetupUrl =
        'https://github.com/settings/tokens/new?description=MobileCode&scopes=repo,user,notifications,workflow';
    if (!canExchange) {
      await launchUrl(Uri.parse(tokenSetupUrl), mode: LaunchMode.externalApplication);
      final missing = clientId.isEmpty ? 'client id' : 'client secret';
      return GitHubOAuthLaunchResult(
        startedOAuth: false,
        message: 'This build has no GitHub OAuth $missing configured. Use a token, or build with OAuth client settings.',
      );
    }

    final state = _newState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, state);
    final url = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scopes,
      'state': state,
      'prompt': 'select_account',
    });
    await launchUrl(url, mode: LaunchMode.externalApplication);
    return const GitHubOAuthLaunchResult(
      startedOAuth: true,
      message: 'GitHub OAuth opened. Return to MobileCode after authorization.',
    );
  }

  static Future<Uri?> consumePendingCallbackUri() async {
    String? rawLink;
    try {
      rawLink = await _systemTools.invokeMethod<String>('consumeInitialDeepLink');
    } catch (_) {
      return null;
    }
    if (rawLink == null || rawLink.trim().isEmpty) return null;
    final uri = Uri.tryParse(rawLink);
    if (uri == null || uri.scheme != 'mobilecode' || uri.host != 'github') {
      return null;
    }
    return uri;
  }

  static Future<GitHubOAuthCallbackResult> completeCallbackUri(
    Uri uri,
    GitHubDeepService github,
  ) async {
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final description = uri.queryParameters['error_description'] ?? error;
      await _clearState();
      return GitHubOAuthCallbackResult(
        handled: true,
        success: false,
        message: 'GitHub OAuth failed: $description',
      );
    }

    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      return const GitHubOAuthCallbackResult(handled: false, success: false);
    }

    final prefs = await SharedPreferences.getInstance();
    final expectedState = prefs.getString(_stateKey);
    final actualState = uri.queryParameters['state'];
    if (expectedState != null && expectedState.isNotEmpty && actualState != expectedState) {
      await _clearState();
      return const GitHubOAuthCallbackResult(
        handled: true,
        success: false,
        message: 'GitHub OAuth state mismatch. Please try login again.',
      );
    }

    if (!canExchange) {
      await _clearState();
      final missing = clientId.isEmpty ? 'client id' : 'client secret';
      return GitHubOAuthCallbackResult(
        handled: true,
        success: false,
        message: 'GitHub OAuth callback arrived, but this APK has no OAuth $missing configured. Use token login or rebuild with OAuth settings.',
      );
    }

    try {
      final ok = await github.authenticateWithOAuthCode(
        code: code,
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
      );
      await _clearState();
      return GitHubOAuthCallbackResult(
        handled: true,
        success: ok,
        message: ok ? 'GitHub OAuth login connected.' : 'GitHub OAuth token was received but /user could not be read.',
      );
    } catch (error) {
      await _clearState();
      return GitHubOAuthCallbackResult(
        handled: true,
        success: false,
        message: 'GitHub OAuth exchange failed: $error',
      );
    }
  }

  static Future<GitHubOAuthCallbackResult> consumeAndComplete(
    GitHubDeepService github,
  ) async {
    final uri = await consumePendingCallbackUri();
    if (uri == null) {
      return const GitHubOAuthCallbackResult(handled: false, success: false);
    }
    return completeCallbackUri(uri, github);
  }

  static String _newState() {
    final random = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = List.generate(12, (_) => random.nextInt(36).toRadixString(36)).join();
    return '$now-$suffix';
  }

  static Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stateKey);
  }
}
