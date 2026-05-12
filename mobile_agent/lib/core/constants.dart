/// Application-wide constants for MobileCode.
///
/// Organized into namespaced classes for clean access:
/// ```dart
/// AppStrings.appName
/// ApiEndpoints.openAiBase
/// StorageKeys.projects
/// ```
library;

// ═══════════════════════════════════════════════════════════════════════════
// String Constants
// ═══════════════════════════════════════════════════════════════════════════

/// UI text and display strings
class AppStrings {
  AppStrings._();

  static const String appName = 'MobileCode';
  static const String appTagline = '随时随地，Vibing Coding';
  static const String appSlogan = '用安卓开发安卓，用安卓开发世界';
  static const String appSloganAlt = '让手机发烫的除了游戏，还有你写的每一行代码';
  static const String deepDiveName = '深潜模式';
  static const String deepDiveSlogan = 'AI深潜，代码浮现';
  static const String appVersion = '0.1.0';

  // Navigation labels
  static const String navHome = 'Home';
  static const String navEditor = 'Editor';
  static const String navProjects = 'Projects';
  static const String navSnippets = 'Snippets';
  static const String navGitHub = 'GitHub';
  static const String navSettings = 'Settings';

  // Editor
  static const String editorTitle = 'Code Editor';
  static const String editorNewFile = 'New File';
  static const String editorSave = 'Save';
  static const String editorRun = 'Run';
  static const String editorUndo = 'Undo';
  static const String editorRedo = 'Redo';
  static const String editorSearch = 'Search';
  static const String editorReplace = 'Replace';
  static const String editorGoToLine = 'Go to Line';
  static const String editorFontSize = 'Font Size';
  static const String editorWordWrap = 'Word Wrap';
  static const String editorLineNumbers = 'Line Numbers';

  // AI Chat
  static const String aiTitle = 'AI Assistant';
  static const String aiSend = 'Send';
  static const String aiHint = 'Ask me anything about your code...';
  static const String aiThinking = 'Thinking...';
  static const String aiError = 'Something went wrong. Please try again.';
  static const String aiCopy = 'Copy';
  static const String aiInsert = 'Insert into Editor';
  static const String aiExplain = 'Explain this code';
  static const String aiRefactor = 'Refactor';
  static const String aiGenerate = 'Generate';
  static const String aiReview = 'Review Code';

  // Projects
  static const String projectNew = 'New Project';
  static const String projectName = 'Project Name';
  static const String projectDescription = 'Description';
  static const String projectLanguage = 'Language';
  static const String projectDelete = 'Delete Project';
  static const String projectRename = 'Rename';
  static const String projectDuplicate = 'Duplicate';
  static const String projectFavorite = 'Favorite';
  static const String projectEmpty = 'No projects yet. Create one!';

  // Snippets
  static const String snippetNew = 'New Snippet';
  static const String snippetTitle = 'Title';
  static const String snippetContent = 'Code';
  static const String snippetTags = 'Tags';
  static const String snippetFromVoice = 'Voice Note';
  static const String snippetFromText = 'Quick Note';
  static const String snippetFromScreenshot = 'Screenshot';
  static const String snippetEmpty = 'No snippets yet. Capture an idea!';
  static const String snippetDeleteConfirm = 'Delete this snippet?';

  // GitHub
  static const String githubConnect = 'Connect GitHub';
  static const String githubDisconnect = 'Disconnect';
  static const String githubRepos = 'Repositories';
  static const String githubSync = 'Sync';
  static const String githubClone = 'Clone';
  static const String githubPush = 'Push';
  static const String githubPull = 'Pull';
  static const String githubBranch = 'Branch';
  static const String githubCommit = 'Commit';
  static const String githubEmpty = 'No repositories connected';

  // API Configuration
  static const String apiConfigTitle = 'AI API Configuration';
  static const String apiProvider = 'Provider';
  static const String apiKey = 'API Key';
  static const String apiBaseUrl = 'Base URL';
  static const String apiModel = 'Model';
  static const String apiAdd = 'Add Configuration';
  static const String apiDelete = 'Remove Configuration';
  static const String apiTest = 'Test Connection';
  static const String apiEmpty = 'No API configurations. Add one to use AI features.';

  // Settings
  static const String settingsTitle = 'Settings';
  static const String settingsTheme = 'Theme';
  static const String settingsEditor = 'Editor Settings';
  static const String settingsAI = 'AI Settings';
  static const String settingsGitHub = 'GitHub Account';
  static const String settingsAbout = 'About';
  static const String settingsPrivacy = 'Privacy Policy';
  static const String settingsTerms = 'Terms of Service';
  static const String settingsRate = 'Rate App';
  static const String settingsShare = 'Share App';
  static const String settingsFeedback = 'Send Feedback';

  // Common
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String delete = 'Delete';
  static const String save = 'Save';
  static const String edit = 'Edit';
  static const String create = 'Create';
  static const String done = 'Done';
  static const String close = 'Close';
  static const String search = 'Search';
  static const String loading = 'Loading...';
  static const String error = 'Error';
  static const String retry = 'Retry';
  static const String empty = 'Nothing here yet';
}

// ═══════════════════════════════════════════════════════════════════════════
// API Endpoints
// ═══════════════════════════════════════════════════════════════════════════

/// External API endpoint URLs
class ApiEndpoints {
  ApiEndpoints._();

  // OpenAI
  static const String openAiBase = 'https://api.openai.com/v1';
  static const String openAiModels = '/models';
  static const String openAiChat = '/chat/completions';
  static const String openAiAudioTranscription = '/audio/transcriptions';

  // Anthropic (Claude)
  static const String claudeBase = 'https://api.anthropic.com';
  static const String claudeMessages = '/v1/messages';

  // Google (Gemini)
  static const String geminiBase = 'https://generativelanguage.googleapis.com';

  // GitHub API
  static const String githubBase = 'https://api.github.com';
  static const String githubUser = '/user';
  static const String githubUserRepos = '/user/repos';
  static const String githubRepos = '/repos';
  static const String githubSearchRepos = '/search/repositories';
  static const String githubContents = '/contents';
  static const String githubGitTrees = '/git/trees';

  // GitHub OAuth
  static const String githubAuthorize = 'https://github.com/login/oauth/authorize';
  static const String githubAccessToken = 'https://github.com/login/oauth/access_token';
}

// ═══════════════════════════════════════════════════════════════════════════
// Storage Keys (for Hive & SharedPreferences)
// ═══════════════════════════════════════════════════════════════════════════

/// Hive box names
class StorageBoxes {
  StorageBoxes._();

  static const String projects = 'projects';
  static const String snippets = 'snippets';
  static const String apiConfigs = 'api_configs';
  static const String githubRepos = 'github_repos';
  static const String chatHistory = 'chat_history';
}

/// SharedPreferences keys
class PreferenceKeys {
  PreferenceKeys._();

  // App State
  static const String onboardingComplete = 'onboarding_complete';
  static const String lastVisitedProject = 'last_visited_project';

  // Theme
  static const String themeMode = 'theme_mode';

  // Editor
  static const String editorFontSize = 'editor_font_size';
  static const String editorFontFamily = 'editor_font_family';
  static const String editorWordWrap = 'editor_word_wrap';
  static const String editorShowLineNumbers = 'editor_show_line_numbers';
  static const String editorTabSize = 'editor_tab_size';
  static const String editorUseSpaces = 'editor_use_spaces';

  // AI
  static const String defaultProvider = 'default_ai_provider';
  static const String defaultModel = 'default_ai_model';
  static const String aiTemperature = 'ai_temperature';
  static const String aiMaxTokens = 'ai_max_tokens';
  static const String aiStreamResponse = 'ai_stream_response';

  // GitHub
  static const String githubToken = 'github_token';
  static const String githubUsername = 'github_username';
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature Flags
// ═══════════════════════════════════════════════════════════════════════════

/// Feature flags for gradual rollout and A/B testing
class FeatureFlags {
  FeatureFlags._();

  /// Enable AI chat streaming responses
  static const bool enableStreamingChat = true;

  /// Enable voice-to-code snippet creation
  static const bool enableVoiceSnippets = false; // Coming soon

  /// Enable screenshot-to-code (OCR)
  static const bool enableScreenshotOcr = false; // Coming soon

  /// Enable real-time collaboration
  static const bool enableCollaboration = false; // Coming soon

  /// Enable cloud sync for projects
  static const bool enableCloudSync = false; // Coming soon

  /// Enable GitHub Actions integration
  static const bool enableGitHubActions = false; // Coming soon

  /// Show debug info in UI
  static const bool showDebugInfo = false;
}

// ═══════════════════════════════════════════════════════════════════════════
// Default Values
// ═══════════════════════════════════════════════════════════════════════════

/// Default configuration values
class Defaults {
  Defaults._();

  // Editor
  static const double editorFontSize = 14.0;
  static const String editorFontFamily = 'JetBrainsMono';
  static const bool editorWordWrap = true;
  static const bool editorShowLineNumbers = true;
  static const int editorTabSize = 2;
  static const bool editorUseSpaces = true;

  // AI
  static const String aiProvider = 'openai';
  static const String aiModel = 'gpt-4o-mini';
  static const double aiTemperature = 0.7;
  static const int aiMaxTokens = 4096;
  static const bool aiStreamResponse = true;

  // Pagination
  static const int pageSize = 20;
  static const int maxRecentFiles = 10;

  // Timeouts
  static const int apiTimeoutSeconds = 60;
  static const int connectionTimeoutSeconds = 10;

  // Limits
  static const int maxSnippetTags = 10;
  static const int maxProjectFiles = 1000;
  static const int maxChatHistory = 100;
}

// ═══════════════════════════════════════════════════════════════════════════
// Supported Languages
// ═══════════════════════════════════════════════════════════════════════════

/// Programming languages supported by the editor
class SupportedLanguages {
  SupportedLanguages._();

  static const Map<String, String> languages = {
    'dart': 'Dart',
    'javascript': 'JavaScript',
    'typescript': 'TypeScript',
    'python': 'Python',
    'go': 'Go',
    'rust': 'Rust',
    'java': 'Java',
    'kotlin': 'Kotlin',
    'swift': 'Swift',
    'php': 'PHP',
    'ruby': 'Ruby',
    'c': 'C',
    'cpp': 'C++',
    'csharp': 'C#',
    'html': 'HTML',
    'css': 'CSS',
    'json': 'JSON',
    'yaml': 'YAML',
    'markdown': 'Markdown',
    'sql': 'SQL',
    'shell': 'Shell',
    'dockerfile': 'Dockerfile',
  };

  /// File extension to language mapping
  static const Map<String, String> extensionMap = {
    '.dart': 'dart',
    '.js': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.jsx': 'javascript',
    '.py': 'python',
    '.go': 'go',
    '.rs': 'rust',
    '.java': 'java',
    '.kt': 'kotlin',
    '.swift': 'swift',
    '.php': 'php',
    '.rb': 'ruby',
    '.c': 'c',
    '.cpp': 'cpp',
    '.h': 'c',
    '.cs': 'csharp',
    '.html': 'html',
    '.htm': 'html',
    '.css': 'css',
    '.scss': 'css',
    '.json': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.md': 'markdown',
    '.sql': 'sql',
    '.sh': 'shell',
    '.bash': 'shell',
    '.zsh': 'shell',
    '.dockerfile': 'dockerfile',
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// AI Provider Models
// ═══════════════════════════════════════════════════════════════════════════

/// Available models per AI provider
class AiModels {
  AiModels._();

  static const Map<String, List<String>> modelsByProvider = {
    'openai': [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-3.5-turbo',
    ],
    'claude': [
      'claude-3-5-sonnet-latest',
      'claude-3-5-haiku-latest',
      'claude-3-opus-latest',
    ],
    'gemini': [
      'gemini-2.0-flash',
      'gemini-2.0-pro',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ],
    'custom': [], // User-defined
  };

  /// Default base URLs for each provider
  static const Map<String, String> defaultBaseUrls = {
    'openai': 'https://api.openai.com/v1',
    'claude': 'https://api.anthropic.com',
    'gemini': 'https://generativelanguage.googleapis.com/v1beta',
    'custom': '',
  };
}