import 'package:flutter/material.dart';

void main() {
  runApp(const MobileCodePreviewApp());
}

class MobileCodePreviewApp extends StatelessWidget {
  const MobileCodePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MobileCode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5EE0B8),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07100F),
      ),
      home: const PreviewHomePage(),
    );
  }
}

class PreviewHomePage extends StatelessWidget {
  const PreviewHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = [
      ('Screenshot to code', Icons.photo_camera_outlined),
      ('Voice to task', Icons.mic_none_outlined),
      ('Agent actions', Icons.smart_toy_outlined),
      ('GitHub workflow', Icons.account_tree_outlined),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const _Badge(),
            const SizedBox(height: 28),
            Text(
              'MobileCode',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'AI coding workspace for mobile devices. This preview APK proves the Android package pipeline while the full Flutter app continues integration.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFAEB8AE),
                    height: 1.55,
                  ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF121F1D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preview build',
                    style: TextStyle(
                      color: Color(0xFFF0B35A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...features.map(
                    (feature) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(feature.$2, color: const Color(0xFF5EE0B8)),
                          const SizedBox(width: 12),
                          Text(feature.$1),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Ready for Android release'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF5EE0B8).withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF5EE0B8).withOpacity(0.24)),
        ),
        child: const Text(
          'v0.1.0 preview',
          style: TextStyle(
            color: Color(0xFF5EE0B8),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
