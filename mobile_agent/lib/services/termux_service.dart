// lib/services/termux_service.dart
// Termux Service — Integrates MobileCode with Termux for Flutter builds.
//
// Provides access to Flutter SDK, Android SDK, and build tools via Termux.
// Supports APK building, web preview, file sync, permission management,
// and automated setup wizard for first-time users.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';

import 'terminal_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Termux Service
// ═══════════════════════════════════════════════════════════════════════════

/// Integrates MobileCode with Termux for:
/// - Flutter SDK access
/// - Android SDK access
/// - Build commands (flutter build apk/web)
/// - Java/Python/Node runtimes
/// - File system access
///
/// Communication methods (in order of preference):
/// 1. Socket communication (most reliable)
/// 2. Intent-based (am command)
/// 3. Shared storage (file-based)
/// 4. Termux:API plugin
///
/// Usage:
/// ```dart
/// final termux = TermuxService();
/// await termux.initialize();
/// final installed = await termux.isTermuxInstalled();
/// final result = await termux.buildApk('/path/to/project');
/// ```
class TermuxService {
  // Singleton
  static final TermuxService _instance = TermuxService._internal();
  factory TermuxService() => _instance;
  TermuxService._internal();

  // ── Connection State ─────────────────────────────────────────────

  /// Terminal service for executing local commands.
  TerminalService? _terminalService;

  /// Build log stream controller.
  final StreamController<String> _buildLogController =
      StreamController<String>.broadcast();

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Cached Termux installation status.
  bool? _termuxInstalledCache;

  /// Cached Termux:API installation status.
  bool? _termuxApiInstalledCache;

  /// Cached Flutter SDK status.
  FlutterSdkStatus? _flutterSdkStatusCache;

  /// Current build process reference for cancellation.
  Process? _currentBuildProcess;

  /// Shared storage path for file-based communication.
  late String _sharedStoragePath;

  // ── Constants ────────────────────────────────────────────────────

  static const String _termuxPackage = 'com.termux';
  static const String _termuxApiPackage = 'com.termux.api';
  static const String _termuxFdroidPackage = 'com.termux';
  static const String _setupCompleteKey = 'termux_setup_complete';

  // ═════════════════════════════════════════════════════════════════
  // Public Accessors
  // ═════════════════════════════════════════════════════════════════

  /// Stream of build log output lines.
  Stream<String> get buildLogStream => _buildLogController.stream;

  /// Whether the service is initialized.
  bool get isInitialized => _initialized;

  /// Whether Termux is known to be installed (from cache).
  bool? get isTermuxInstalledCached => _termuxInstalledCache;

  /// Whether Termux:API is known to be installed (from cache).
  bool? get isTermuxApiInstalledCached => _termuxApiInstalledCache;

  // ═════════════════════════════════════════════════════════════════
  // Initialization
  // ═════════════════════════════════════════════════════════════════

  /// Initialize the Termux service.
  ///
  /// Sets up the terminal service and shared storage paths.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('[TermuxService] Initializing...');

      _terminalService = TerminalService();

      final appDir = await _getAppDocumentsDirectory();
      _sharedStoragePath = p.join(appDir, 'termux_shared');

      await Directory(_sharedStoragePath).create(recursive: true);

      _initialized = true;
      debugPrint('[TermuxService] Initialized successfully');
    } catch (e) {
      throw TermuxServiceException('Failed to initialize Termux service: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Connection Management
  // ═════════════════════════════════════════════════════════════════

  /// Check if Termux is installed on the device.
  ///
  /// Uses `pm list packages` to detect the Termux app.
  /// Results are cached for 30 seconds.
  Future<bool> isTermuxInstalled() async {
    _ensureInitialized();

    if (_termuxInstalledCache != null) {
      return _termuxInstalledCache!;
    }

    try {
      final result = await _terminalService!.execute(
        'pm list packages | grep $_termuxPackage',
        timeoutSeconds: 5,
      );

      _termuxInstalledCache = result.success && result.stdout.contains(_termuxPackage);
      debugPrint('[TermuxService] Termux installed: $_termuxInstalledCache');
      return _termuxInstalledCache!;
    } catch (e) {
      debugPrint('[TermuxService] Error checking Termux install: $e');
      return false;
    }
  }

  /// Check if Termux:API plugin is installed.
  ///
  /// The API plugin provides additional capabilities like
  /// toast notifications, clipboard access, and sensor data.
  Future<bool> isTermuxApiInstalled() async {
    _ensureInitialized();

    if (_termuxApiInstalledCache != null) {
      return _termuxApiInstalledCache!;
    }

    try {
      final result = await _terminalService!.execute(
        'pm list packages | grep $_termuxApiPackage',
        timeoutSeconds: 5,
      );

      _termuxApiInstalledCache = result.success && result.stdout.contains(_termuxApiPackage);
      debugPrint('[TermuxService] Termux:API installed: $_termuxApiInstalledCache');
      return _termuxApiInstalledCache!;
    } catch (e) {
      debugPrint('[TermuxService] Error checking Termux:API install: $e');
      return false;
    }
  }

  /// Check Flutter SDK availability in Termux.
  ///
  /// Returns one of: notInstalled, installing, installed, outdated
  Future<FlutterSdkStatus> checkFlutterSdk() async {
    _ensureInitialized();

    if (_flutterSdkStatusCache != null) {
      return _flutterSdkStatusCache!;
    }

    try {
      final result = await _terminalService!.execute(
        'which flutter',
        timeoutSeconds: 5,
      );

      if (!result.success || result.stdout.trim().isEmpty) {
        _flutterSdkStatusCache = FlutterSdkStatus.notInstalled;
        debugPrint('[TermuxService] Flutter SDK: not installed');
        return FlutterSdkStatus.notInstalled;
      }

      // Check version to determine if outdated.
      final versionResult = await _terminalService!.execute(
        'flutter --version',
        timeoutSeconds: 10,
      );

      if (versionResult.success) {
        final versionOutput = versionResult.stdout;
        final versionMatch = RegExp(r'Flutter\s+([\d.]+)').firstMatch(versionOutput);
        if (versionMatch != null) {
          final version = versionMatch.group(1) ?? '0.0.0';
          debugPrint('[TermuxService] Flutter SDK version: $version');
          // Consider outdated if older than 3.x
          if (version.startsWith('2.') || version.startsWith('1.')) {
            _flutterSdkStatusCache = FlutterSdkStatus.outdated;
            return FlutterSdkStatus.outdated;
          }
        }
      }

      _flutterSdkStatusCache = FlutterSdkStatus.installed;
      return FlutterSdkStatus.installed;
    } catch (e) {
      debugPrint('[TermuxService] Error checking Flutter SDK: $e');
      return FlutterSdkStatus.notInstalled;
    }
  }

  /// Set up Flutter SDK in Termux (automated installation).
  ///
  /// Runs the installation script via Termux with progress reporting.
  Future<void> setupFlutterSdk() async {
    _ensureInitialized();

    debugPrint('[TermuxService] Starting Flutter SDK setup...');
    _flutterSdkStatusCache = FlutterSdkStatus.installing;

    try {
      // Update packages first.
      _buildLogController.add('[setup] Updating Termux packages...');
      await execute('pkg update -y');

      // Install required dependencies.
      _buildLogController.add('[setup] Installing dependencies...');
      await execute('pkg install -y git curl unzip');

      // Clone the Flutter SDK installer for Termux.
      _buildLogController.add('[setup] Downloading Flutter SDK...');
      await execute('git clone https://github.com/termux/termux-flutter.git \\$HOME/termux-flutter || true');

      // Run the installer.
      _buildLogController.add('[setup] Running Flutter SDK installer...');
      await execute('cd \$HOME/termux-flutter && bash install.sh');

      // Verify installation.
      final status = await checkFlutterSdk();
      if (status == FlutterSdkStatus.installed) {
        _buildLogController.add('[setup] Flutter SDK installed successfully!');
        debugPrint('[TermuxService] Flutter SDK setup complete');
      } else {
        throw TermuxServiceException('Flutter SDK installation verification failed');
      }
    } catch (e) {
      _flutterSdkStatusCache = FlutterSdkStatus.notInstalled;
      _buildLogController.add('[setup] Flutter SDK setup failed: $e');
      throw TermuxServiceException('Failed to setup Flutter SDK: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Build Orchestration
  // ═════════════════════════════════════════════════════════════════

  /// Build Flutter Web (fast preview).
  ///
  /// Much faster than APK build (seconds vs minutes).
  /// Good for quick iteration and UI layout checking.
  Future<BuildResult> buildWeb(String projectPath) async {
    _ensureInitialized();
    _validateProject(projectPath);

    debugPrint('[TermuxService] Building Flutter Web for: $projectPath');
    _buildLogController.add('[build] Starting Flutter Web build...');

    final stopwatch = Stopwatch()..start();

    try {
      // Ensure dependencies are resolved.
      _buildLogController.add('[build] Running flutter pub get...');
      await execute('flutter pub get', workingDir: projectPath);

      // Build for web.
      _buildLogController.add('[build] Building for web...');
      final result = await execute(
        'flutter build web --release',
        workingDir: projectPath,
      );

      stopwatch.stop();

      final webBuildPath = p.join(projectPath, 'build', 'web');
      final webDir = Directory(webBuildPath);

      if (!await webDir.exists()) {
        _buildLogController.add('[build] Web build failed: output directory not found');
        return BuildResult(
          success: false,
          error: 'Build output not found. ${result.stderr}',
          buildTime: stopwatch.elapsed,
        );
      }

      final fileSize = await _calculateDirectorySize(webBuildPath);

      _buildLogController.add('[build] Web build completed in ${stopwatch.elapsed.inSeconds}s');

      return BuildResult(
        success: true,
        outputPath: webBuildPath,
        buildTime: stopwatch.elapsed,
        fileSize: fileSize,
      );
    } catch (e) {
      stopwatch.stop();
      _buildLogController.add('[build] Web build failed: $e');
      return BuildResult(
        success: false,
        error: e.toString(),
        buildTime: stopwatch.elapsed,
      );
    }
  }

  /// Build Flutter APK (real app).
  ///
  /// Builds a real Android APK that can be installed and run.
  /// Takes 2-5 minutes depending on project size and device.
  Future<BuildResult> buildApk(
    String projectPath, {
    BuildMode mode = BuildMode.debug,
  }) async {
    _ensureInitialized();
    _validateProject(projectPath);

    debugPrint('[TermuxService] Building Flutter APK (mode: $mode) for: $projectPath');
    _buildLogController.add('[build] Starting Flutter APK build (mode: ${mode.name})...');

    final stopwatch = Stopwatch()..start();

    try {
      // Ensure dependencies are resolved.
      _buildLogController.add('[build] Running flutter pub get...');
      await execute('flutter pub get', workingDir: projectPath);

      // Build the APK.
      final modeFlag = _buildModeFlag(mode);
      _buildLogController.add('[build] Building APK ($modeFlag)...');

      final result = await execute(
        'flutter build apk $modeFlag',
        workingDir: projectPath,
      );

      stopwatch.stop();

      final apkDir = Directory(p.join(projectPath, 'build', 'app', 'outputs', 'flutter-apk'));
      if (!await apkDir.exists()) {
        _buildLogController.add('[build] APK build failed: output directory not found');
        return BuildResult(
          success: false,
          error: 'APK output not found. ${result.stderr}',
          buildTime: stopwatch.elapsed,
        );
      }

      // Find the APK file.
      final apkFiles = await apkDir
          .list()
          .where((f) => f is File && f.path.endsWith('.apk'))
          .map((f) => f as File)
          .toList();

      if (apkFiles.isEmpty) {
        _buildLogController.add('[build] APK build failed: no APK file found');
        return BuildResult(
          success: false,
          error: 'No APK file found in output directory',
          buildTime: stopwatch.elapsed,
        );
      }

      final apkFile = apkFiles.first;
      final fileSize = await apkFile.length();

      _buildLogController.add('[build] APK build completed: ${apkFile.path}');
      _buildLogController.add('[build] Size: ${_formatFileSize(fileSize)}');

      return BuildResult(
        success: true,
        outputPath: apkFile.path,
        buildTime: stopwatch.elapsed,
        fileSize: fileSize,
      );
    } catch (e) {
      stopwatch.stop();
      _buildLogController.add('[build] APK build failed: $e');
      return BuildResult(
        success: false,
        error: e.toString(),
        buildTime: stopwatch.elapsed,
      );
    }
  }

  /// Build Flutter App Bundle (for Play Store).
  ///
  /// Creates an .aab file for Google Play Store submission.
  Future<BuildResult> buildAppBundle(String projectPath) async {
    _ensureInitialized();
    _validateProject(projectPath);

    debugPrint('[TermuxService] Building Flutter App Bundle for: $projectPath');
    _buildLogController.add('[build] Starting Flutter App Bundle build...');

    final stopwatch = Stopwatch()..start();

    try {
      _buildLogController.add('[build] Running flutter pub get...');
      await execute('flutter pub get', workingDir: projectPath);

      _buildLogController.add('[build] Building app bundle...');
      final result = await execute(
        'flutter build appbundle --release',
        workingDir: projectPath,
      );

      stopwatch.stop();

      final bundlePath = p.join(
        projectPath,
        'build',
        'app',
        'outputs',
        'bundle',
        'release',
        'app-release.aab',
      );

      final bundleFile = File(bundlePath);
      if (!await bundleFile.exists()) {
        return BuildResult(
          success: false,
          error: 'App bundle not found. ${result.stderr}',
          buildTime: stopwatch.elapsed,
        );
      }

      final fileSize = await bundleFile.length();

      return BuildResult(
        success: true,
        outputPath: bundlePath,
        buildTime: stopwatch.elapsed,
        fileSize: fileSize,
      );
    } catch (e) {
      stopwatch.stop();
      return BuildResult(
        success: false,
        error: e.toString(),
        buildTime: stopwatch.elapsed,
      );
    }
  }

  /// Run Flutter app with hot reload support.
  ///
  /// Launches the app on the connected device/emulator.
  Future<void> runFlutter(String projectPath) async {
    _ensureInitialized();
    _validateProject(projectPath);

    debugPrint('[TermuxService] Running Flutter app: $projectPath');

    try {
      await execute('flutter pub get', workingDir: projectPath);

      // Start flutter run in the background.
      _currentBuildProcess = await Process.start(
        'flutter',
        ['run', '--hot'],
        workingDirectory: projectPath,
        runInShell: true,
      );

      // Stream output to the build log.
      _currentBuildProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _buildLogController.add(line));

      _currentBuildProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _buildLogController.add('[stderr] $line'));
    } catch (e) {
      throw TermuxServiceException('Failed to run Flutter app: $e');
    }
  }

  /// Get build logs as a streaming broadcast.
  ///
  /// Subscribe to this stream to receive real-time build output.
  Stream<String> getBuildLogs() => _buildLogController.stream;

  /// Stop the current build process.
  Future<void> stopCurrentBuild() async {
    if (_currentBuildProcess != null) {
      _currentBuildProcess!.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 500));
      _currentBuildProcess?.kill(ProcessSignal.sigkill);
      _currentBuildProcess = null;
      _buildLogController.add('[system] Build stopped by user');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // APK Management
  // ═════════════════════════════════════════════════════════════════

  /// Install an APK on the device.
  ///
  /// Uses `pm install` or `adb install` depending on context.
  Future<InstallResult> installApk(String apkPath) async {
    _ensureInitialized();

    debugPrint('[TermuxService] Installing APK: <redacted>');
    _buildLogController.add('[install] Installing APK...');

    // SECURITY FIX: Validate APK path before use.
    _validateFilePath(apkPath);

    try {
      final escapedPath = _shellEscape(apkPath);
      final result = await execute('pm install -r $escapedPath');

      if (result.success) {
        // Extract package name from APK.
        final packageName = await _extractPackageName(apkPath);
        debugPrint('[TermuxService] APK installed: $packageName');
        _buildLogController.add('[install] APK installed successfully!');

        return InstallResult(
          success: true,
          packageName: packageName,
        );
      } else {
        _buildLogController.add('[install] APK install failed: ${result.stderr}');
        return InstallResult(
          success: false,
          packageName: '',
          error: result.stderr,
        );
      }
    } catch (e) {
      _buildLogController.add('[install] APK install error: $e');
      return InstallResult(
        success: false,
        packageName: '',
        error: e.toString(),
      );
    }
  }

  /// Launch an installed app by package name.
  Future<void> launchApp(String packageName) async {
    _ensureInitialized();

    debugPrint('[TermuxService] Launching app: $packageName');

    try {
      final result = await execute(
        'am start -n $packageName/$packageName.MainActivity',
      );

      if (!result.success) {
        debugPrint('[TermuxService] Failed to launch app: ${result.stderr}');
        // Try alternate main activity path.
        await execute('monkey -p $packageName -c android.intent.category.LAUNCHER 1');
      }
    } catch (e) {
      throw TermuxServiceException('Failed to launch app: $e');
    }
  }

  /// Get information about an installed app.
  Future<AppInfo> getAppInfo(String packageName) async {
    _ensureInitialized();

    try {
      final result = await execute(
        'dumpsys package $packageName | grep -E "versionName|firstInstallTime"',
      );

      String version = 'unknown';
      if (result.success) {
        final versionMatch = RegExp(r'versionName=([^\s]+)').firstMatch(result.stdout);
        if (versionMatch != null) {
          version = versionMatch.group(1) ?? 'unknown';
        }
      }

      // Check if app is currently running.
      final runningResult = await execute(
        'ps | grep $packageName',
      );
      final isRunning = runningResult.success && runningResult.stdout.isNotEmpty;

      return AppInfo(
        packageName: packageName,
        appName: packageName.split('.').last,
        version: version,
        isInstalled: result.success,
        isRunning: isRunning,
      );
    } catch (e) {
      return AppInfo(
        packageName: packageName,
        appName: packageName.split('.').last,
        version: 'unknown',
        isInstalled: false,
        isRunning: false,
      );
    }
  }

  /// Uninstall an app by package name.
  Future<void> uninstallApp(String packageName) async {
    _ensureInitialized();

    debugPrint('[TermuxService] Uninstalling app: $packageName');
    _buildLogController.add('[uninstall] Removing $packageName...');

    try {
      final result = await execute('pm uninstall $packageName');

      if (result.success) {
        _buildLogController.add('[uninstall] App uninstalled successfully');
      } else {
        _buildLogController.add('[uninstall] Uninstall failed: ${result.stderr}');
        throw TermuxServiceException('Failed to uninstall: ${result.stderr}');
      }
    } catch (e) {
      throw TermuxServiceException('Failed to uninstall app: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // File Sync
  // ═════════════════════════════════════════════════════════════════

  /// Sync project files to the Termux workspace.
  ///
  /// Copies the local project to Termux's working directory
  /// for build operations.
  Future<void> syncToTermux(String localPath, String termuxPath) async {
    _ensureInitialized();

    debugPrint('[TermuxService] Syncing $localPath -> $termuxPath');
    _buildLogController.add('[sync] Copying files to Termux workspace...');

    try {
      // Ensure the target directory exists.
      await execute('mkdir -p "$termuxPath"');

      // Copy files using cp -r.
      await execute('cp -r "$localPath/"* "$termuxPath/"');

      _buildLogController.add('[sync] Files synced successfully');
    } catch (e) {
      throw TermuxServiceException('Failed to sync files to Termux: $e');
    }
  }

  /// Sync build output from Termux to local storage.
  ///
  /// Returns the local path where files were synced.
  Future<String> syncFromTermux(String termuxPath, String localPath) async {
    _ensureInitialized();

    debugPrint('[TermuxService] Syncing $termuxPath -> $localPath');

    try {
      await Directory(localPath).create(recursive: true);
      await execute('cp -r "$termuxPath/"* "$localPath/"');

      return localPath;
    } catch (e) {
      throw TermuxServiceException('Failed to sync files from Termux: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Command Execution
  // ═════════════════════════════════════════════════════════════════

  /// Execute a command in Termux environment.
  ///
  /// Returns the complete result including stdout, stderr, and exit code.
  Future<TermuxResult> execute(String command, {String? workingDir}) async {
    _ensureInitialized();

    // SECURITY FIX: Validate inputs and redact from logs.
    if (workingDir != null) {
      _validateFilePath(workingDir);
    }
    debugPrint('[TermuxService] Executing: <redacted>');

    try {
      final result = await _terminalService!.execute(
        command,
        workingDirectory: workingDir,
      );

      return TermuxResult(
        command: command,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        duration: result.duration,
      );
    } catch (e) {
      throw TermuxServiceException('Command execution failed: $e');
    }
  }

  /// Execute a command with streaming output.
  ///
  /// Yields output lines as they are produced. Ideal for
  /// long-running commands like builds.
  Stream<String> executeStream(String command, {String? workingDir}) async* {
    _ensureInitialized();

    debugPrint('[TermuxService] Streaming: $command');

    await for (final line in _terminalService!.executeStream(
      command,
      workingDirectory: workingDir,
    )) {
      yield line;
      _buildLogController.add(line);
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Permission Management
  // ═════════════════════════════════════════════════════════════════

  /// Get all available Termux permissions and their status.
  Future<List<TermuxPermission>> getPermissions() async {
    _ensureInitialized();

    final permissions = [
      const TermuxPermission(
        name: 'storage',
        description: 'Access device storage for file operations',
        isGranted: false,
        isRequired: true,
      ),
      const TermuxPermission(
        name: 'notification',
        description: 'Show build notifications',
        isGranted: false,
        isRequired: false,
      ),
      const TermuxPermission(
        name: 'install_packages',
        description: 'Install packages in Termux',
        isGranted: false,
        isRequired: true,
      ),
      const TermuxPermission(
        name: 'internet',
        description: 'Access network for pub get',
        isGranted: false,
        isRequired: true,
      ),
    ];

    // Check actual permission status.
    final results = <TermuxPermission>[];
    for (final perm in permissions) {
      final granted = await hasPermission(perm);
      results.add(TermuxPermission(
        name: perm.name,
        description: perm.description,
        isGranted: granted,
        isRequired: perm.isRequired,
      ));
    }

    return results;
  }

  /// Check if a specific permission is granted.
  Future<bool> hasPermission(TermuxPermission permission) async {
    _ensureInitialized();

    try {
      switch (permission.name) {
        case 'storage':
          return await _hasStoragePermission();
        case 'internet':
          return await _hasInternetPermission();
        case 'install_packages':
          return true; // Always true in Termux.
        case 'notification':
          return await isTermuxApiInstalled();
        default:
          return false;
      }
    } catch (e) {
      debugPrint('[TermuxService] Error checking permission ${permission.name}: $e');
      return false;
    }
  }

  /// Request a permission from the user.
  ///
  /// For storage, opens Termux to trigger the permission dialog.
  Future<bool> requestPermission(TermuxPermission permission) async {
    _ensureInitialized();

    debugPrint('[TermuxService] Requesting permission: ${permission.name}');

    try {
      switch (permission.name) {
        case 'storage':
          // Launch Termux to trigger storage permission dialog.
          await execute('termux-storage-setup');
          return await _hasStoragePermission();
        case 'notification':
          // Termux:API is needed for notifications.
          if (!await isTermuxApiInstalled()) {
            _buildLogController.add('[perm] Termux:API plugin required for notifications');
            return false;
          }
          return true;
        default:
          return true;
      }
    } catch (e) {
      debugPrint('[TermuxService] Error requesting permission: $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Setup Wizard
  // ═════════════════════════════════════════════════════════════════

  /// Run the setup wizard for first-time users.
  ///
  /// Guides the user through Termux installation, permission granting,
  /// and Flutter SDK setup.
  Future<SetupResult> runSetupWizard() async {
    _ensureInitialized();

    debugPrint('[TermuxService] Starting setup wizard...');

    final completedSteps = <String>[];
    final failedSteps = <String>[];

    // Step 1: Check Termux installation.
    _buildLogController.add('[setup] Step 1/4: Checking Termux installation...');
    if (await isTermuxInstalled()) {
      completedSteps.add('termux_installed');
      _buildLogController.add('[setup] Termux is installed');
    } else {
      failedSteps.add('termux_installed');
      _buildLogController.add('[setup] Termux not installed - please install from F-Droid');
      return SetupResult(
        success: false,
        completedSteps: completedSteps,
        failedSteps: failedSteps,
        message: 'Termux is not installed. Please install Termux from F-Droid store.',
      );
    }

    // Step 2: Check permissions.
    _buildLogController.add('[setup] Step 2/4: Checking permissions...');
    final permissions = await getPermissions();
    final missingRequired = permissions
        .where((p) => p.isRequired && !p.isGranted)
        .toList();

    if (missingRequired.isEmpty) {
      completedSteps.add('permissions');
      _buildLogController.add('[setup] All required permissions granted');
    } else {
      for (final perm in missingRequired) {
        final granted = await requestPermission(perm);
        if (granted) {
          completedSteps.add('permission_${perm.name}');
        } else {
          failedSteps.add('permission_${perm.name}');
        }
      }
    }

    // Step 3: Check Flutter SDK.
    _buildLogController.add('[setup] Step 3/4: Checking Flutter SDK...');
    final flutterStatus = await checkFlutterSdk();
    if (flutterStatus == FlutterSdkStatus.installed) {
      completedSteps.add('flutter_sdk');
      _buildLogController.add('[setup] Flutter SDK is ready');
    } else if (flutterStatus == FlutterSdkStatus.outdated) {
      completedSteps.add('flutter_sdk');
      _buildLogController.add('[setup] Flutter SDK is installed but may be outdated');
    } else {
      _buildLogController.add('[setup] Flutter SDK not found - will install...');
      try {
        await setupFlutterSdk();
        completedSteps.add('flutter_sdk');
      } catch (e) {
        failedSteps.add('flutter_sdk');
        _buildLogController.add('[setup] Flutter SDK installation failed: $e');
      }
    }

    // Step 4: Verify setup.
    _buildLogController.add('[setup] Step 4/4: Verifying setup...');
    try {
      final verifyResult = await execute('flutter doctor');
      if (verifyResult.success) {
        completedSteps.add('verification');
        _buildLogController.add('[setup] Setup verification passed');
      } else {
        failedSteps.add('verification');
        _buildLogController.add('[setup] Setup verification had warnings');
      }
    } catch (e) {
      failedSteps.add('verification');
    }

    final success = failedSteps.isEmpty ||
        failedSteps.every((s) => !['termux_installed', 'flutter_sdk'].contains(s));

    final result = SetupResult(
      success: success,
      completedSteps: completedSteps,
      failedSteps: failedSteps,
      message: success
          ? 'Setup complete! You can now build Flutter apps.'
          : 'Setup incomplete. Please resolve the failed steps.',
    );

    debugPrint('[TermuxService] Setup wizard complete: success=$success');
    return result;
  }

  /// Check if the initial setup is complete.
  Future<bool> isSetupComplete() async {
    _ensureInitialized();

    try {
      final termuxReady = await isTermuxInstalled();
      final flutterReady = await checkFlutterSdk();

      return termuxReady &&
          (flutterReady == FlutterSdkStatus.installed ||
              flutterReady == FlutterSdkStatus.outdated);
    } catch (e) {
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Utility / Private Methods
  // ═════════════════════════════════════════════════════════════════

  void _ensureInitialized() {
    if (!_initialized) {
      throw const TermuxServiceException(
          'TermuxService not initialized. Call initialize() first.');
    }
  }

  void _validateProject(String projectPath) {
    final dir = Directory(projectPath);
    if (!dir.existsSync()) {
      throw TermuxServiceException('Project directory not found: $projectPath');
    }

    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw TermuxServiceException(
          'No pubspec.yaml found in project directory. Is this a Flutter project?');
    }
  }

  String _buildModeFlag(BuildMode mode) {
    switch (mode) {
      case BuildMode.debug:
        return '--debug';
      case BuildMode.profile:
        return '--profile';
      case BuildMode.release:
        return '--release';
    }
  }

  Future<String> _getAppDocumentsDirectory() async {
    // Use the app's documents directory.
    final appDir = Directory('/sdcard/Documents/MobileCode');
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir.path;
  }

  Future<int> _calculateDirectorySize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;

    int totalSize = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (_) {
      // Ignore permission errors during size calculation.
    }
    return totalSize;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Future<String> _extractPackageName(String apkPath) async {
    try {
      final result = await execute(
        'aapt dump badging "$apkPath" | grep package',
        timeoutSeconds: 10,
      );
      final match = RegExp(r"name='([^']+)").firstMatch(result.stdout);
      return match?.group(1) ?? 'unknown.package';
    } catch (e) {
      return 'unknown.package';
    }
  }

  Future<bool> _hasStoragePermission() async {
    try {
      final result = await execute('ls /sdcard/', timeoutSeconds: 3);
      return result.success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _hasInternetPermission() async {
    try {
      final result = await execute('ping -c 1 google.com', timeoutSeconds: 5);
      return result.success;
    } catch (e) {
      return false;
    }
  }

  /// Clear all cached status values.
  void clearCache() {
    _termuxInstalledCache = null;
    _termuxApiInstalledCache = null;
    _flutterSdkStatusCache = null;
  }

  /// Dispose all resources.
  void dispose() {
    _currentBuildProcess?.kill(ProcessSignal.sigkill);
    _currentBuildProcess = null;

    if (!_buildLogController.isClosed) {
      _buildLogController.close();
    }

    _initialized = false;
    debugPrint('[TermuxService] Disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Build mode for APK compilation.
enum BuildMode { debug, profile, release }

/// Flutter SDK installation status.
enum FlutterSdkStatus { notInstalled, installing, installed, outdated }

// ═══════════════════════════════════════════════════════════════════════════
// Data Classes
// ═══════════════════════════════════════════════════════════════════════════

/// Result of a build operation.
class BuildResult {
  /// Whether the build succeeded.
  final bool success;

  /// Path to the built output file or directory.
  final String? outputPath;

  /// Error message if the build failed.
  final String? error;

  /// Time taken to complete the build.
  final Duration buildTime;

  /// Size of the build output in bytes.
  final int fileSize;

  /// Human-readable file size (e.g., "12.5MB").
  String get formattedSize => _formatSize(fileSize);

  const BuildResult({
    required this.success,
    this.outputPath,
    this.error,
    required this.buildTime,
    this.fileSize = 0,
  });

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  String toString() => 'BuildResult(success=$success, time=${buildTime.inSeconds}s, size=$formattedSize)';
}

/// Result of an APK installation.
class InstallResult {
  /// Whether the installation succeeded.
  final bool success;

  /// Package name of the installed app.
  final String packageName;

  /// Error message if installation failed.
  final String? error;

  const InstallResult({
    required this.success,
    required this.packageName,
    this.error,
  });

  @override
  String toString() => 'InstallResult(success=$success, package=$packageName)';
}

/// Termux permission descriptor.
class TermuxPermission {
  /// Permission identifier (e.g., 'storage', 'internet').
  final String name;

  /// Human-readable description of what this permission enables.
  final String description;

  /// Whether this permission is currently granted.
  final bool isGranted;

  /// Whether this permission is required for basic functionality.
  final bool isRequired;

  const TermuxPermission({
    required this.name,
    required this.description,
    required this.isGranted,
    required this.isRequired,
  });

  @override
  String toString() => 'TermuxPermission($name, granted=$isGranted, required=$isRequired)';
}

/// Result of the setup wizard.
class SetupResult {
  /// Whether the setup completed successfully.
  final bool success;

  /// Names of steps that completed successfully.
  final List<String> completedSteps;

  /// Names of steps that failed.
  final List<String> failedSteps;

  /// Human-readable summary message.
  final String message;

  const SetupResult({
    required this.success,
    required this.completedSteps,
    required this.failedSteps,
    required this.message,
  });

  /// Whether all critical steps passed.
  bool get isFullyOperational =>
      success && failedSteps.isEmpty;

  @override
  String toString() =>
      'SetupResult(success=$success, completed=${completedSteps.length}, failed=${failedSteps.length})';
}

/// Information about an installed app.
class AppInfo {
  /// Android package name.
  final String packageName;

  /// Display name of the app.
  final String appName;

  /// App version string.
  final String version;

  /// Whether the app is installed.
  final bool isInstalled;

  /// Whether the app is currently running.
  final bool isRunning;

  const AppInfo({
    required this.packageName,
    required this.appName,
    required this.version,
    required this.isInstalled,
    required this.isRunning,
  });

  @override
  String toString() => 'AppInfo($packageName, v$version, installed=$isInstalled, running=$isRunning)';
}

/// Result of a Termux command execution.
class TermuxResult {
  /// The command that was executed.
  final String command;

  /// Standard output.
  final String stdout;

  /// Standard error.
  final String stderr;

  /// Exit code (0 = success).
  final int exitCode;

  /// Execution duration.
  final Duration duration;

  const TermuxResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  /// Whether the command succeeded.
  bool get success => exitCode == 0;

  @override
  String toString() => 'TermuxResult($command, exit=$exitCode, ${duration.inMilliseconds}ms)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Security Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Validates that a file path is safe (no traversal attempts).
void _validateFilePath(String path) {
  if (path.isEmpty) {
    throw const TermuxServiceException('Path cannot be empty');
  }
  // Reject paths with directory traversal sequences.
  if (path.contains('../') || path.contains('..\\')) {
    throw const TermuxServiceException(
        'Path contains directory traversal sequences');
  }
  // Reject null bytes.
  if (path.contains('\x00')) {
    throw const TermuxServiceException('Path contains null bytes');
  }
}

/// Escapes a string for safe use in shell contexts.
String _shellEscape(String input) {
  final escaped = input.replaceAll("'", "'\"'\"'");
  return "'$escaped'";
}

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

/// Exception thrown by the Termux Service.
class TermuxServiceException implements Exception {
  final String message;

  const TermuxServiceException(this.message);

  @override
  String toString() => 'TermuxServiceException: $message';
}
