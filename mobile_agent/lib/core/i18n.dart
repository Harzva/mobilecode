/// Internationalization System for MobileCode
///
/// Provides complete i18n support with:
/// - Two languages: Chinese (zh, default) and English (en)
/// - Runtime language switching via [LocaleNotifier]
/// - Locale persistence across app restarts
/// - Number, date, and file size formatting
/// - Flutter integration via [AppLocalizationsDelegate]
///
/// Usage:
/// ```dart
/// final l10n = AppLocalizations.of(context);
/// Text(l10n.editorTitle);
/// ```
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Abstract Interface
// ═══════════════════════════════════════════════════════════════════════════

/// Abstract interface for all localized strings and formatting.
///
/// Every user-facing string in the app must be defined here.
/// Implementations: [ZhLocalizations], [EnLocalizations].
abstract class AppLocalizations {
  /// Current locale code: 'zh' or 'en'
  String get localeCode;

  /// Currently active locale
  Locale get locale;

  // ── Editor ──────────────────────────────────────────────────────────
  String get editorTitle;
  String get editorNewFile;
  String get editorSave;
  String get editorUndo;
  String get editorRedo;
  String get editorSearch;
  String get editorReplace;
  String get editorGoToLine;
  String get editorFormatCode;
  String get editorToggleLineNumbers;

  // ── AI Assistant ────────────────────────────────────────────────────
  String get aiAssistantTitle;
  String get aiExplainCode;
  String get aiFixCode;
  String get aiGenerateCode;
  String get aiOptimizeCode;
  String get aiThinking;
  String get aiTypeMessage;

  // ── Projects ────────────────────────────────────────────────────────
  String get projectsTitle;
  String get projectsNew;
  String get projectsImport;
  String get projectsExport;
  String get projectsDeleteConfirm;
  String get projectsEmpty;

  // ── GitHub ──────────────────────────────────────────────────────────
  String get githubTitle;
  String get githubLogin;
  String get githubLogout;
  String get githubRepositories;
  String get githubIssues;
  String get githubPullRequests;
  String get githubSync;
  String get githubClone;
  String get githubPush;
  String get githubPull;

  // ── Snippets ────────────────────────────────────────────────────────
  String get snippetsTitle;
  String get snippetsNew;
  String get snippetsVoice;
  String get snippetsScreenshot;
  String get snippetsTemplates;
  String get snippetsDeleteConfirm;

  // ── Screenshot to Code ──────────────────────────────────────────────
  String get screenshotToCodeTitle;
  String get screenshotPickImage;
  String get screenshotTakePhoto;
  String get screenshotConverting;
  String get screenshotResult;
  String get screenshotCopyCode;
  String get screenshotOpenInEditor;

  // ── Settings ────────────────────────────────────────────────────────
  String get settingsTitle;
  String get settingsEditor;
  String get settingsTheme;
  String get settingsLanguage;
  String get settingsFontSize;
  String get settingsAbout;
  String get settingsVersion;

  // ── Common Actions ──────────────────────────────────────────────────
  String get commonCancel;
  String get commonConfirm;
  String get commonDelete;
  String get commonEdit;
  String get commonSave;
  String get commonCopy;
  String get commonPaste;
  String get commonSearch;
  String get commonLoading;
  String get commonError;
  String get commonRetry;
  String get commonDone;
  String get commonClose;
  String get commonCreate;
  String get commonBack;
  String get commonNext;

  // ── Error Messages ──────────────────────────────────────────────────
  String get errorNetwork;
  String get errorTimeout;
  String get errorApiKey;
  String get errorFileNotFound;
  String get errorPermissionDenied;
  String get errorUnknown;
  String get errorInvalidInput;

  // ── API Configuration ───────────────────────────────────────────────
  String get apiConfigTitle;
  String get apiProvider;
  String get apiKey;
  String get apiBaseUrl;
  String get apiModel;
  String get apiAdd;
  String get apiTest;
  String get apiEmpty;

  // ── Formatting Methods ──────────────────────────────────────────────

  /// Format a date according to locale conventions
  String formatDate(DateTime date);

  /// Format a time according to locale conventions
  String formatTime(DateTime time);

  /// Format relative time (e.g., "2 hours ago", "刚刚")
  String formatRelativeTime(DateTime date);

  /// Format file size in human-readable form (e.g., "1.5 MB")
  String formatFileSize(int bytes);

  /// Format a number with locale-appropriate separators
  String formatNumber(int number);

  /// Format a duration (e.g., "2m 30s")
  String formatDuration(Duration duration);

  // ── Flutter Localization Integration ────────────────────────────────

  /// Supported locales for the app
  static const List<Locale> supportedLocales = [
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];

  /// Localizations delegates for MaterialApp
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// Lookup instance from BuildContext
  static AppLocalizations of(BuildContext context) {
    final localizations =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (localizations == null) {
      // Fall back to Chinese if localization not found
      return _fallback;
    }
    return localizations;
  }

  /// Get localization instance for a specific locale
  factory AppLocalizations.forLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return EnLocalizations();
      case 'zh':
      default:
        return ZhLocalizations();
    }
  }

  static final AppLocalizations _fallback = ZhLocalizations();
}

// ═══════════════════════════════════════════════════════════════════════════
// Chinese Implementation (Default)
// ═══════════════════════════════════════════════════════════════════════════

/// Chinese (Simplified, China) localization
class ZhLocalizations implements AppLocalizations {
  @override
  String get localeCode => 'zh';

  @override
  Locale get locale => const Locale('zh', 'CN');

  // ── Editor ──────────────────────────────────────────────────────────
  @override
  String get editorTitle => '代码编辑器';
  @override
  String get editorNewFile => '新建文件';
  @override
  String get editorSave => '保存';
  @override
  String get editorUndo => '撤销';
  @override
  String get editorRedo => '重做';
  @override
  String get editorSearch => '搜索';
  @override
  String get editorReplace => '替换';
  @override
  String get editorGoToLine => '跳转到行';
  @override
  String get editorFormatCode => '格式化代码';
  @override
  String get editorToggleLineNumbers => '显示/隐藏行号';

  // ── AI Assistant ────────────────────────────────────────────────────
  @override
  String get aiAssistantTitle => 'AI 助手';
  @override
  String get aiExplainCode => '解释代码';
  @override
  String get aiFixCode => '修复代码';
  @override
  String get aiGenerateCode => '生成代码';
  @override
  String get aiOptimizeCode => '优化代码';
  @override
  String get aiThinking => '正在思考...';
  @override
  String get aiTypeMessage => '输入消息...';

  // ── Projects ────────────────────────────────────────────────────────
  @override
  String get projectsTitle => '项目';
  @override
  String get projectsNew => '新建项目';
  @override
  String get projectsImport => '导入项目';
  @override
  String get projectsExport => '导出项目';
  @override
  String get projectsDeleteConfirm => '确定要删除这个项目吗？此操作不可撤销。';
  @override
  String get projectsEmpty => '暂无项目，点击创建一个新项目';

  // ── GitHub ──────────────────────────────────────────────────────────
  @override
  String get githubTitle => 'GitHub';
  @override
  String get githubLogin => '登录 GitHub';
  @override
  String get githubLogout => '退出登录';
  @override
  String get githubRepositories => '代码仓库';
  @override
  String get githubIssues => '问题';
  @override
  String get githubPullRequests => '拉取请求';
  @override
  String get githubSync => '同步';
  @override
  String get githubClone => '克隆';
  @override
  String get githubPush => '推送';
  @override
  String get githubPull => '拉取';

  // ── Snippets ────────────────────────────────────────────────────────
  @override
  String get snippetsTitle => '代码片段';
  @override
  String get snippetsNew => '新建片段';
  @override
  String get snippetsVoice => '语音输入';
  @override
  String get snippetsScreenshot => '截图转代码';
  @override
  String get snippetsTemplates => '代码模板';
  @override
  String get snippetsDeleteConfirm => '确定要删除此代码片段吗？';

  // ── Screenshot to Code ──────────────────────────────────────────────
  @override
  String get screenshotToCodeTitle => '截图转代码';
  @override
  String get screenshotPickImage => '选择图片';
  @override
  String get screenshotTakePhoto => '拍照';
  @override
  String get screenshotConverting => '正在转换...';
  @override
  String get screenshotResult => '转换结果';
  @override
  String get screenshotCopyCode => '复制代码';
  @override
  String get screenshotOpenInEditor => '在编辑器中打开';

  // ── Settings ────────────────────────────────────────────────────────
  @override
  String get settingsTitle => '设置';
  @override
  String get settingsEditor => '编辑器设置';
  @override
  String get settingsTheme => '主题';
  @override
  String get settingsLanguage => '语言';
  @override
  String get settingsFontSize => '字体大小';
  @override
  String get settingsAbout => '关于';
  @override
  String get settingsVersion => '版本';

  // ── Common Actions ──────────────────────────────────────────────────
  @override
  String get commonCancel => '取消';
  @override
  String get commonConfirm => '确认';
  @override
  String get commonDelete => '删除';
  @override
  String get commonEdit => '编辑';
  @override
  String get commonSave => '保存';
  @override
  String get commonCopy => '复制';
  @override
  String get commonPaste => '粘贴';
  @override
  String get commonSearch => '搜索';
  @override
  String get commonLoading => '加载中...';
  @override
  String get commonError => '出错了';
  @override
  String get commonRetry => '重试';
  @override
  String get commonDone => '完成';
  @override
  String get commonClose => '关闭';
  @override
  String get commonCreate => '创建';
  @override
  String get commonBack => '返回';
  @override
  String get commonNext => '下一步';

  // ── Error Messages ──────────────────────────────────────────────────
  @override
  String get errorNetwork => '网络连接失败，请检查网络设置';
  @override
  String get errorTimeout => '请求超时，请稍后重试';
  @override
  String get errorApiKey => 'API 密钥无效或已过期';
  @override
  String get errorFileNotFound => '文件不存在';
  @override
  String get errorPermissionDenied => '权限不足，无法访问';
  @override
  String get errorUnknown => '发生未知错误';
  @override
  String get errorInvalidInput => '输入无效';

  // ── API Configuration ───────────────────────────────────────────────
  @override
  String get apiConfigTitle => 'AI API 配置';
  @override
  String get apiProvider => '提供商';
  @override
  String get apiKey => 'API 密钥';
  @override
  String get apiBaseUrl => '基础 URL';
  @override
  String get apiModel => '模型';
  @override
  String get apiAdd => '添加配置';
  @override
  String get apiTest => '测试连接';
  @override
  String get apiEmpty => '暂无 API 配置，添加一个以使用 AI 功能';

  // ── Formatting ──────────────────────────────────────────────────────

  static final DateFormat _dateFormat = DateFormat('yyyy年MM月dd日');
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  String formatDate(DateTime date) => _dateFormat.format(date);

  @override
  String formatTime(DateTime time) => _timeFormat.format(time);

  @override
  String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}个月前';
    return '${diff.inDays ~/ 365}年前';
  }

  @override
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String formatNumber(int number) {
    return NumberFormat('#,###', 'zh_CN').format(number);
  }

  @override
  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) return '${hours}时${minutes}分${seconds}秒';
    if (minutes > 0) return '${minutes}分${seconds}秒';
    return '${seconds}秒';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// English Implementation
// ═══════════════════════════════════════════════════════════════════════════

/// English (United States) localization
class EnLocalizations implements AppLocalizations {
  @override
  String get localeCode => 'en';

  @override
  Locale get locale => const Locale('en', 'US');

  // ── Editor ──────────────────────────────────────────────────────────
  @override
  String get editorTitle => 'Code Editor';
  @override
  String get editorNewFile => 'New File';
  @override
  String get editorSave => 'Save';
  @override
  String get editorUndo => 'Undo';
  @override
  String get editorRedo => 'Redo';
  @override
  String get editorSearch => 'Search';
  @override
  String get editorReplace => 'Replace';
  @override
  String get editorGoToLine => 'Go to Line';
  @override
  String get editorFormatCode => 'Format Code';
  @override
  String get editorToggleLineNumbers => 'Toggle Line Numbers';

  // ── AI Assistant ────────────────────────────────────────────────────
  @override
  String get aiAssistantTitle => 'AI Assistant';
  @override
  String get aiExplainCode => 'Explain Code';
  @override
  String get aiFixCode => 'Fix Code';
  @override
  String get aiGenerateCode => 'Generate Code';
  @override
  String get aiOptimizeCode => 'Optimize Code';
  @override
  String get aiThinking => 'Thinking...';
  @override
  String get aiTypeMessage => 'Type a message...';

  // ── Projects ────────────────────────────────────────────────────────
  @override
  String get projectsTitle => 'Projects';
  @override
  String get projectsNew => 'New Project';
  @override
  String get projectsImport => 'Import Project';
  @override
  String get projectsExport => 'Export Project';
  @override
  String get projectsDeleteConfirm =>
      'Are you sure you want to delete this project? This action cannot be undone.';
  @override
  String get projectsEmpty => 'No projects yet. Tap to create a new one.';

  // ── GitHub ──────────────────────────────────────────────────────────
  @override
  String get githubTitle => 'GitHub';
  @override
  String get githubLogin => 'Login with GitHub';
  @override
  String get githubLogout => 'Logout';
  @override
  String get githubRepositories => 'Repositories';
  @override
  String get githubIssues => 'Issues';
  @override
  String get githubPullRequests => 'Pull Requests';
  @override
  String get githubSync => 'Sync';
  @override
  String get githubClone => 'Clone';
  @override
  String get githubPush => 'Push';
  @override
  String get githubPull => 'Pull';

  // ── Snippets ────────────────────────────────────────────────────────
  @override
  String get snippetsTitle => 'Snippets';
  @override
  String get snippetsNew => 'New Snippet';
  @override
  String get snippetsVoice => 'Voice Input';
  @override
  String get snippetsScreenshot => 'Screenshot to Code';
  @override
  String get snippetsTemplates => 'Code Templates';
  @override
  String get snippetsDeleteConfirm => 'Delete this snippet?';

  // ── Screenshot to Code ──────────────────────────────────────────────
  @override
  String get screenshotToCodeTitle => 'Screenshot to Code';
  @override
  String get screenshotPickImage => 'Pick Image';
  @override
  String get screenshotTakePhoto => 'Take Photo';
  @override
  String get screenshotConverting => 'Converting...';
  @override
  String get screenshotResult => 'Conversion Result';
  @override
  String get screenshotCopyCode => 'Copy Code';
  @override
  String get screenshotOpenInEditor => 'Open in Editor';

  // ── Settings ────────────────────────────────────────────────────────
  @override
  String get settingsTitle => 'Settings';
  @override
  String get settingsEditor => 'Editor Settings';
  @override
  String get settingsTheme => 'Theme';
  @override
  String get settingsLanguage => 'Language';
  @override
  String get settingsFontSize => 'Font Size';
  @override
  String get settingsAbout => 'About';
  @override
  String get settingsVersion => 'Version';

  // ── Common Actions ──────────────────────────────────────────────────
  @override
  String get commonCancel => 'Cancel';
  @override
  String get commonConfirm => 'Confirm';
  @override
  String get commonDelete => 'Delete';
  @override
  String get commonEdit => 'Edit';
  @override
  String get commonSave => 'Save';
  @override
  String get commonCopy => 'Copy';
  @override
  String get commonPaste => 'Paste';
  @override
  String get commonSearch => 'Search';
  @override
  String get commonLoading => 'Loading...';
  @override
  String get commonError => 'Error';
  @override
  String get commonRetry => 'Retry';
  @override
  String get commonDone => 'Done';
  @override
  String get commonClose => 'Close';
  @override
  String get commonCreate => 'Create';
  @override
  String get commonBack => 'Back';
  @override
  String get commonNext => 'Next';

  // ── Error Messages ──────────────────────────────────────────────────
  @override
  String get errorNetwork => 'Network connection failed. Please check your settings.';
  @override
  String get errorTimeout => 'Request timed out. Please try again later.';
  @override
  String get errorApiKey => 'API key is invalid or has expired.';
  @override
  String get errorFileNotFound => 'File not found.';
  @override
  String get errorPermissionDenied => 'Permission denied.';
  @override
  String get errorUnknown => 'An unknown error occurred.';
  @override
  String get errorInvalidInput => 'Invalid input.';

  // ── API Configuration ───────────────────────────────────────────────
  @override
  String get apiConfigTitle => 'AI API Configuration';
  @override
  String get apiProvider => 'Provider';
  @override
  String get apiKey => 'API Key';
  @override
  String get apiBaseUrl => 'Base URL';
  @override
  String get apiModel => 'Model';
  @override
  String get apiAdd => 'Add Configuration';
  @override
  String get apiTest => 'Test Connection';
  @override
  String get apiEmpty => 'No API configurations. Add one to use AI features.';

  // ── Formatting ──────────────────────────────────────────────────────

  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  static final DateFormat _timeFormat = DateFormat('h:mm a');
  static final DateFormat _dateTimeFormat = DateFormat('MMM d, yyyy h:mm a');

  @override
  String formatDate(DateTime date) => _dateFormat.format(date);

  @override
  String formatTime(DateTime time) => _timeFormat.format(time);

  @override
  String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
    return '${diff.inDays ~/ 365}y ago';
  }

  @override
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String formatNumber(int number) {
    return NumberFormat('#,###', 'en_US').format(number);
  }

  @override
  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Flutter Localization Delegate
// ═══════════════════════════════════════════════════════════════════════════

/// [LocalizationsDelegate] that loads [AppLocalizations] instances.
///
/// Registered in [AppLocalizations.localizationsDelegates].
class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations.forLocale(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// Locale Persistence & Runtime Switching
// ═══════════════════════════════════════════════════════════════════════════

/// Key used in SharedPreferences to store the selected locale
const _kLocalePersistenceKey = 'app_locale';

/// Notifier for reactive locale switching across the app.
///
/// Use with [ValueListenableBuilder] or Riverpod:
/// ```dart
/// final localeNotifier = LocaleNotifier();
/// localeNotifier.setLocale(Locale('en', 'US'));
/// ```
class LocaleNotifier extends ValueNotifier<Locale> {
  LocaleNotifier() : super(const Locale('zh', 'CN')) {
    _loadPersistedLocale();
  }

  /// Whether a locale has been loaded from persistence
  bool _initialized = false;

  /// The currently active [AppLocalizations] instance
  AppLocalizations get localizations => AppLocalizations.forLocale(value);

  /// Switch to a new locale and persist the choice
  Future<void> setLocale(Locale newLocale) async {
    if (!isSupported(newLocale)) return;
    if (value == newLocale) return;

    value = newLocale;
    await _persistLocale(newLocale);
  }

  /// Switch to Chinese
  Future<void> setChinese() => setLocale(const Locale('zh', 'CN'));

  /// Switch to English
  Future<void> setEnglish() => setLocale(const Locale('en', 'US'));

  /// Toggle between supported locales
  Future<void> toggleLocale() async {
    if (value.languageCode == 'zh') {
      await setEnglish();
    } else {
      await setChinese();
    }
  }

  /// Check if a locale is supported
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);
  }

  /// Load the persisted locale from SharedPreferences
  Future<void> _loadPersistedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString(_kLocalePersistenceKey);
      if (savedLocale != null) {
        final parts = savedLocale.split('_');
        if (parts.length == 2) {
          final locale = Locale(parts[0], parts[1]);
          if (isSupported(locale)) {
            value = locale;
          }
        }
      }
    } catch (e) {
      // Fall back to default locale on error
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Persist the locale choice to SharedPreferences
  Future<void> _persistLocale(Locale locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocalePersistenceKey, '${locale.languageCode}_${locale.countryCode}');
    } catch (e) {
      // Silently fail - locale switch still works in-memory
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Global Locale Instance
// ═══════════════════════════════════════════════════════════════════════════

/// Global locale notifier for app-wide locale access.
///
/// Initialize at app startup:
/// ```dart
/// void main() {
///   final localeNotifier = createLocaleNotifier();
///   runApp(MyApp(localeNotifier: localeNotifier));
/// }
/// ```
LocaleNotifier createLocaleNotifier() => LocaleNotifier();

// ═══════════════════════════════════════════════════════════════════════════
// Convenience Extensions
// ═══════════════════════════════════════════════════════════════════════════

/// Extension on [BuildContext] for easy access to localization
extension AppLocalizationsContext on BuildContext {
  /// Get the current [AppLocalizations] instance
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Get the current locale
  Locale get currentLocale => Localizations.localeOf(this);
}

// ═══════════════════════════════════════════════════════════════════════════
// Required imports for Flutter localization delegates
// ═══════════════════════════════════════════════════════════════════════════

// These are required by [AppLocalizations.localizationsDelegates]
// ignore: unused_import
typedef GlobalMaterialLocalizations = MaterialLocalizations;
// ignore: unused_import
typedef GlobalWidgetsLocalizations = WidgetsLocalizations;
// ignore: unused_import
typedef GlobalCupertinoLocalizations = CupertinoLocalizations;
