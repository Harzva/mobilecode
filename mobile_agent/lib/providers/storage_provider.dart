// lib/providers/storage_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';

/// Provider for the [StorageService] singleton.
///
/// This is initialized in main.dart via ProviderScope overrides.
/// The storage service handles all local persistence (Hive).
///
/// ```dart
/// final storage = ref.read(storageServiceProvider);
/// final projects = await storage.getProjects();
/// ```
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError(
    'storageServiceProvider must be overridden in the ProviderScope '
    'during app initialization in main.dart.\n\n'
    'Example:\n'
    'void main() async {\n'
    '  WidgetsFlutterBinding.ensureInitialized();\n'
    '  final storage = StorageService();\n'
    '  await storage.init();\n'
    '  runApp(\n'
    '    ProviderScope(\n'
    '      overrides: [\n'
    '        storageServiceProvider.overrideWithValue(storage),\n'
    '      ],\n'
    '      child: const MyApp(),\n'
    '    ),\n'
    '  );\n'
    '}',
  );
});
