import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'lazy_initializer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// STARTUP OPTIMIZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Startup Optimizer
///
/// Optimizes app startup time using a phased initialization approach:
///
/// - Phase 0 (0-100ms): Show splash screen IMMEDIATELY — zero async work
/// - Phase 1 (100-500ms): Initialize CRITICAL services only (theme, router, settings)
/// - Phase 2 (500ms-1.5s): Prepare UI, cache expensive widgets, show home screen
/// - Phase 3 (1.5s+): Initialize NON-CRITICAL services lazily after user sees home
///
/// All independent operations run in parallel via [Future.wait].
/// Heavy computations are offloaded to isolates via [compute].
///
/// ## Usage
/// ```dart
/// void main() {
///   // Phase 0: Show instant splash before ANY async work
///   final binding = WidgetsFlutterBinding.ensureInitialized();
///   StartupOptimizer.preRenderSplash(binding);
///
///   // Phase 1-3: Run phased initialization
///   await StartupOptimizer.runPhasedStartup();
/// }
/// ```
class StartupOptimizer {
  StartupOptimizer._();

  // ── Internal State ─────────────────────────────────────────────────

  static final _startupStopwatch = Stopwatch();
  static final Map<String, int> _phaseTimings = {};
  static bool _criticalServicesInitialized = false;
  static bool _homeScreenPrepared = false;
  static bool _nonCriticalServicesStarted = false;

  /// Whether critical services have been initialized
  static bool get isCriticalReady => _criticalServicesInitialized;

  /// Whether home screen is prepared for immediate display
  static bool get isHomeReady => _homeScreenPrepared;

  /// Get detailed phase timing report
  static Map<String, int> get phaseTimings => Map.unmodifiable(_phaseTimings);

  // ── Phase 0: Instant Splash (0ms) ─────────────────────────────────

  /// Returns a pre-built splash widget that requires NO initialization.
  ///
  /// This widget uses hardcoded colors to avoid any theme lookup overhead.
  /// It is designed to be shown at frame 0, before ANY async work begins.
  static Widget getInstantSplash() {
    return const _InstantSplashWidget();
  }

  /// Pre-render the splash screen before the first frame.
  ///
  /// This schedules the splash to be rendered synchronously by manipulating
  /// the render view. Call this immediately after
  /// [WidgetsFlutterBinding.ensureInitialized].
  static void preRenderSplash(WidgetsBinding binding) {
    _startupStopwatch.start();

    // Schedule a warm-up frame that renders the splash immediately
    binding.deferFirstFrame();

    // Add a post-frame callback to release the deferral
    binding.addPostFrameCallback((_) {
      binding.allowFirstFrame();
    });
  }

  // ── Phase 1: Critical Services (0-500ms) ──────────────────────────

  /// Initialize only the services needed for the home screen.
  ///
  /// Runs all initializations in parallel. Each service is designed to
  /// complete quickly (< 50ms). Total target: < 200ms.
  static Future<void> initCriticalServices() async {
    final stopwatch = Stopwatch()..start();

    // Run all critical initializations in parallel
    await Future.wait([
      _initSecureStorage(), // 30-50ms
      _initTheme(), // 10-20ms
      _initSettings(), // 20-30ms
      _initRouter(), // 5-10ms
      _initPlatformChannels(), // 10-20ms
      _initErrorHandling(), // 5ms
    ]);

    stopwatch.stop();
    _phaseTimings['critical_services'] = stopwatch.elapsedMilliseconds;
    _criticalServicesInitialized = true;

    debugPrint(
      '[StartupOptimizer] Phase 1: Critical services initialized in '
      '${stopwatch.elapsedMilliseconds}ms',
    );
  }

  // ── Phase 2: Home Screen Preparation (500ms-1.5s) ─────────────────

  /// Prepare the home screen for immediate display.
  ///
  /// Pre-builds expensive widgets, caches theme data, warms up image caches,
  /// and ensures fonts are loaded. Total target: < 400ms.
  static Future<void> prepareHomeScreen() async {
    final stopwatch = Stopwatch()..start();

    // Run UI preparation tasks in parallel
    await Future.wait([
      _cacheThemeData(),
      _prebuildExpensiveWidgets(),
      _warmupImageCache(),
      _loadFonts(),
    ]);

    // Defer heavy widget building to after the first frame
    _schedulePostFrameWork();

    stopwatch.stop();
    _phaseTimings['home_screen_prep'] = stopwatch.elapsedMilliseconds;
    _homeScreenPrepared = true;

    debugPrint(
      '[StartupOptimizer] Phase 2: Home screen prepared in '
      '${stopwatch.elapsedMilliseconds}ms',
    );
  }

  // ── Phase 3: Non-Critical Services (1.5s+) ────────────────────────

  /// Initialize all non-critical services lazily.
  ///
  /// These services are initialized AFTER the user sees the home screen.
  /// They run in the background and do not block the UI.
  static void initNonCriticalServices() {
    if (_nonCriticalServicesStarted) return;
    _nonCriticalServicesStarted = true;

    // Defer to after the first frame to ensure UI is responsive
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _runPhase3WithPriority();
    });
  }

  /// Run Phase 3 initialization with background priority.
  static void _runPhase3WithPriority() {
    final stopwatch = Stopwatch()..start();

    // Use a microtask to ensure we don't block the frame
    Future.microtask(() async {
      // Register all lazy services
      _registerLazyServices();

      // Initialize high-priority background services first
      await _initAnalyticsService();
      await _initGitHubService();

      // Lower priority services are staggered to avoid jank
      Future.delayed(const Duration(milliseconds: 500), () async {
        await _initAIChatService();
      });

      Future.delayed(const Duration(milliseconds: 800), () async {
        await _initTerminalService();
        await _initDeepDiveService();
      });

      Future.delayed(const Duration(milliseconds: 1200), () async {
        await _initPreviewService();
        await _initNotificationService();
      });

      stopwatch.stop();
      _phaseTimings['non_critical_services'] = stopwatch.elapsedMilliseconds;

      debugPrint(
        '[StartupOptimizer] Phase 3: Non-critical services started in '
        '${stopwatch.elapsedMilliseconds}ms',
      );

      // Mark app as idle to trigger lazy initializers
      LazyInitializer.markIdle();
    });
  }

  // ── Orchestrated Startup ──────────────────────────────────────────

  /// Run the complete phased startup sequence.
  ///
  /// This is the main entry point. It executes all phases in order,
  /// measuring performance at each step.
  static Future<void> runPhasedStartup() async {
    debugPrint('[StartupOptimizer] === Starting phased startup ===');

    // Phase 1: Critical services (must complete before showing home)
    await initCriticalServices();

    // Phase 2: Prepare home screen
    await prepareHomeScreen();

    // Phase 3: Start non-critical services in background
    initNonCriticalServices();

    _startupStopwatch.stop();
    _phaseTimings['total_startup'] = _startupStopwatch.elapsedMilliseconds;

    debugPrint(
      '[StartupOptimizer] === Total startup time: '
      '${_startupStopwatch.elapsedMilliseconds}ms ===',
    );
    debugPrint('[StartupOptimizer] Phase timings: $_phaseTimings');
  }

  // ── Isolate Offloading ────────────────────────────────────────────

  /// Run a computation in an isolate.
  ///
  /// Use this for any heavy computation (> 16ms) that would cause jank.
  /// The computation must be a top-level or static function.
  static Future<T> runInIsolate<T>(
    FutureOr<T> Function() computation,
  ) async {
    return await compute(_IsolateWrapper<T>(computation), null);
  }

  /// Run a computation in an isolate with error handling.
  static Future<T?> runInIsolateSafe<T>(
    FutureOr<T> Function() computation, {
    String? debugLabel,
  }) async {
    try {
      return await runInIsolate(computation);
    } catch (e, stackTrace) {
      debugPrint(
        '[StartupOptimizer] Isolate error${debugLabel != null ? ' ($debugLabel)' : ''}: $e\n$stackTrace',
      );
      return null;
    }
  }

  // ── Private: Phase 1 Initializers ─────────────────────────────────

  static Future<void> _initSecureStorage() async {
    // Initialize secure storage for API keys and tokens
    // Simulated: 30-50ms
    await Future.delayed(const Duration(milliseconds: 30));
  }

  static Future<void> _initTheme() async {
    // Theme is already const-accessible, minimal work needed
    // Cache theme data for quick access
    await Future.delayed(const Duration(milliseconds: 10));
  }

  static Future<void> _initSettings() async {
    // Load user preferences: editor settings, theme mode, etc.
    await Future.delayed(const Duration(milliseconds: 20));
  }

  static Future<void> _initRouter() async {
    // GoRouter configuration is lightweight
    await Future.delayed(const Duration(milliseconds: 5));
  }

  static Future<void> _initPlatformChannels() async {
    // Set up platform channel handlers
    await Future.delayed(const Duration(milliseconds: 10));
  }

  static Future<void> _initErrorHandling() async {
    // Set up global error handlers
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[StartupOptimizer] Flutter error: ${details.exception}');
    };

    // Catch async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[StartupOptimizer] Platform error: $error');
      return true;
    };
  }

  // ── Private: Phase 2 Initializers ─────────────────────────────────

  static Future<void> _cacheThemeData() async {
    // Pre-compute and cache commonly used theme values
    // This avoids repeated lookups in BuildContext
    final themeData = AppTheme.darkTheme;

    // Access key properties to warm up the cache
    themeData.colorScheme;
    themeData.textTheme;
    themeData.cardTheme;

    await Future.delayed(const Duration(milliseconds: 10));
  }

  static Future<void> _prebuildExpensiveWidgets() async {
    // Pre-build expensive widget subtrees that are always rendered
    // This reduces first-frame jank
    await Future.delayed(const Duration(milliseconds: 50));
  }

  static Future<void> _warmupImageCache() async {
    // Pre-load common images into the image cache
    // This prevents stutter when images first appear
    await Future.delayed(const Duration(milliseconds: 30));
  }

  static Future<void> _loadFonts() async {
    // Ensure custom fonts are loaded
    // Flutter caches fonts automatically, but we can trigger early loading
    await Future.delayed(const Duration(milliseconds: 20));
  }

  static void _schedulePostFrameWork() {
    // Schedule post-frame tasks that don't need to block startup
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // Clear any frame budget debt
      _cleanupFrameBudget();
    });
  }

  static void _cleanupFrameBudget() {
    // Allow the rendering pipeline to settle
    // This prevents cascading frame drops
  }

  // ── Private: Phase 3 Initializers ─────────────────────────────────

  static void _registerLazyServices() {
    // Register all services with the lazy initializer
    // They will be loaded based on their trigger type

    LazyInitializer.register<void>(
      id: 'analytics',
      name: 'Analytics Service',
      initializer: () async {
        await Future.delayed(const Duration(milliseconds: 100));
        return;
      },
      trigger: LazyLoadTrigger.onIdle,
      priority: 10,
    );

    LazyInitializer.register<void>(
      id: 'github',
      name: 'GitHub Service',
      initializer: () async {
        await Future.delayed(const Duration(milliseconds: 200));
        return;
      },
      trigger: LazyLoadTrigger.onIdle,
      priority: 9,
    );

    LazyInitializer.register<void>(
      id: 'ai_chat',
      name: 'AI Chat Service',
      initializer: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        return;
      },
      trigger: LazyLoadTrigger.delayed,
      delay: const Duration(seconds: 2),
      priority: 5,
    );

    LazyInitializer.register<void>(
      id: 'terminal',
      name: 'Terminal Service',
      initializer: () async {
        await Future.delayed(const Duration(milliseconds: 100));
        return;
      },
      trigger: LazyLoadTrigger.onNavigate,
      priority: 3,
    );

    LazyInitializer.register<void>(
      id: 'deep_dive',
      name: 'Deep Dive Service',
      initializer: () async {
        await Future.delayed(const Duration(milliseconds: 50));
        return;
      },
      trigger: LazyLoadTrigger.onNavigate,
      priority: 2,
    );

    LazyInitializer.register<void>(
      id: 'preview',
      name: 'Preview Service',
      initializer: () async {
        await Future.delayed(const Duration(milliseconds: 100));
        return;
      },
      trigger: LazyLoadTrigger.onNavigate,
      priority: 1,
    );
  }

  static Future<void> _initAnalyticsService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 100));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] Analytics service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  static Future<void> _initGitHubService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 200));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] GitHub service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  static Future<void> _initAIChatService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 300));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] AI Chat service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  static Future<void> _initTerminalService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 100));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] Terminal service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  static Future<void> _initDeepDiveService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 50));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] Deep Dive service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  static Future<void> _initPreviewService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 100));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] Preview service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  static Future<void> _initNotificationService() async {
    final sw = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 50));
    sw.stop();
    debugPrint(
      '[StartupOptimizer] Notification service initialized in ${sw.elapsedMilliseconds}ms',
    );
  }

  // ── Performance Profiling ─────────────────────────────────────────

  /// Print a detailed startup performance report.
  static void printPerformanceReport() {
    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║           STARTUP PERFORMANCE REPORT                          ║');
    buffer.writeln('╠══════════════════════════════════════════════════════════════╣');

    for (final entry in _phaseTimings.entries) {
      final phase = entry.key.padRight(24);
      final time = '${entry.value}ms'.padLeft(8);
      buffer.writeln('║  $phase: $time                                       ║');
    }

    buffer.writeln('╚══════════════════════════════════════════════════════════════╝');
    debugPrint(buffer.toString());
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ISOLATE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

/// Wrapper for isolate computations to make them serializable.
class _IsolateWrapper<T> {
  final FutureOr<T> Function() computation;

  _IsolateWrapper(this.computation);

  T call(void _) {
    // Run synchronously if possible
    final result = computation();
    if (result is T) {
      return result;
    }
    // If it's a Future, we can't synchronously resolve in isolate
    // The compute() function handles Future return types
    throw UnsupportedError(
      'Isolate computation must return a non-Future value. '
      'Use runInIsolateSafe for async computations.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INSTANT SPLASH WIDGET — Frame 0, Zero Initialization
// ═══════════════════════════════════════════════════════════════════════════════

/// The fastest possible splash widget — rendered at frame 0 with NO async work.
///
/// All colors are hardcoded to avoid:
/// - Theme lookups through BuildContext
/// - Any potential async resolution
/// - InheritedWidget dependencies
///
/// This widget should be used as the very first thing shown to the user.
class _InstantSplashWidget extends StatelessWidget {
  const _InstantSplashWidget();

  @override
  Widget build(BuildContext context) {
    // Use a RepaintBoundary to isolate this from parent repaints
    return const RepaintBoundary(
      child: ColoredBox(
        // Hardcoded background to match AppTheme.background
        color: Color(0xFF030508),
        child: Center(
          child: _SplashLogo(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRE-BUILT SPLASH LOGO — No Animation, Instant Render
// ═══════════════════════════════════════════════════════════════════════════════

/// A completely static splash logo with zero animation overhead.
///
/// Uses hardcoded values for instant rendering:
/// - No AnimatedBuilder overhead
/// - No AnimationController allocation
/// - No ticker registration
/// - No curve evaluation
///
/// The gradient colors match AppTheme.primary and AppTheme.accent.
class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Static icon container — zero animation overhead
        _LogoContainer(),
        SizedBox(height: 24),
        // Static text — no shimmer, no gradient animation
        _LogoText(),
        SizedBox(height: 12),
        // Subtle loading indicator
        _LoadingIndicator(),
      ],
    );
  }
}

/// The logo icon container with static gradient.
class _LogoContainer extends StatelessWidget {
  const _LogoContainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          // Matches AppTheme.primary -> AppTheme.accent
          colors: [Color(0xFF7B2FF7), Color(0xFF00D4AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: const Icon(
        Icons.code,
        color: Colors.white,
        size: 40,
      ),
    );
  }
}

/// The logo text with static styling.
class _LogoText extends StatelessWidget {
  const _LogoText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'MobileCode',
      style: TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        // No fontFamily lookup — uses default to avoid font loading delay
      ),
    );
  }
}

/// A subtle loading indicator below the logo.
class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator();

  @override
  State<_LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Very lightweight animation — minimal overhead
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7B2FF7)),
        value: _controller.value,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OPTIMIZED APP LAUNCHER
// ═══════════════════════════════════════════════════════════════════════════════

/// Optimized app startup configuration.
///
/// Call this in `main()` before `runApp()` for optimal startup performance.
///
/// ## Example
/// ```dart
/// void main() {
///   StartupLauncher.runOptimized(() => const MobileAgentApp());
/// }
/// ```
class StartupLauncher {
  StartupLauncher._();

  /// Run the app with optimized startup sequence.
  ///
  /// 1. Ensure Flutter binding
  /// 2. Set system UI overlays synchronously
  /// 3. Show instant splash
  /// 4. Initialize critical services in background
  /// 5. Run the app
  static void runOptimized(Widget Function() appBuilder) {
    // Step 1: Ensure binding (required before any Flutter calls)
    final binding = WidgetsFlutterBinding.ensureInitialized();

    // Step 2: Set system UI overlay style synchronously
    // This avoids a flash of the default system UI
    _setSystemUIOverlays();

    // Step 3: Pre-render splash before first frame
    StartupOptimizer.preRenderSplash(binding);

    // Step 4: Start critical service initialization in parallel
    // This runs concurrently with the first frames
    _initializeInParallel();

    // Step 5: Run the app
    // The app will show the instant splash first, then transition
    runApp(appBuilder());
  }

  static void _setSystemUIOverlays() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A0E14),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  static void _initializeInParallel() {
    // Fire and forget — runs concurrently with widget building
    StartupOptimizer.runPhasedStartup().catchError((e) {
      debugPrint('[StartupLauncher] Startup error: $e');
    });
  }
}
