// lib/providers/llm_service_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/llm_service.dart';
import 'github_provider.dart';

/// Provider for the LLM service.
///
/// Depends on the shared [ApiService] from [apiServiceProvider].
/// The LLM service handles all AI interactions including code
/// completion, explanation, fixing, and chat.
///
/// ```dart
/// final llm = ref.read(llmServiceProvider);
/// final explanation = await llm.explainCode(code, 'dart', config);
/// ```
final llmServiceProvider = Provider<LLMService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return LLMService(apiService);
});
