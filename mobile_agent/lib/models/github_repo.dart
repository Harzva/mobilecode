import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// {@template github_repo}
/// Represents a GitHub repository synced with Mobile Agent.
///
/// Stores repository metadata and sync state for GitHub-connected
/// projects. The [id] is locally generated while [repoId] is the
/// GitHub API repository ID.
///
/// ## Usage
/// ```dart
/// final repo = GitHubRepo.create(
///   name: 'my-flutter-app',
///   owner: 'username',
///   description: 'A cool app',
/// );
/// ```
/// {@endtemplate}
@immutable
class GitHubRepo {
  // ===========================================================================
  // EXISTING FIELDS (keep all of them)
  // ===========================================================================

  /// Local unique identifier
  final String id;

  /// Repository name (e.g., 'mobile-agent')
  final String name;

  /// Repository owner username or organization
  final String owner;

  /// Optional repository description
  final String description;

  /// Whether the repository is private
  final bool isPrivate;

  /// Default branch name (e.g., 'main', 'master')
  final String defaultBranch;

  /// Number of stargazers
  final int stars;

  /// When the repository was last synced with local storage
  final DateTime lastSynced;

  /// GitHub API repository ID (from GitHub)
  final String? repoId;

  /// Clone URL for the repository
  final String? cloneUrl;

  /// HTML URL for the repository (web interface)
  final String? htmlUrl;

  /// SSH URL for the repository
  final String? sshUrl;

  /// Current locally-checked-out branch
  final String? currentBranch;

  /// Whether there are uncommitted local changes
  final bool hasLocalChanges;

  // ===========================================================================
  // NEW FIELDS
  // ===========================================================================

  /// Fork count
  final int forks;

  /// Open issues count
  final int openIssues;

  /// Watchers count
  final int watchers;

  /// Primary language (e.g., "Dart")
  final String? language;

  /// Language color hex (e.g., "#00B4AB")
  final String? languageColor;

  /// Repository topics/tags
  final List<String> topics;

  /// License name (e.g., "MIT")
  final String? license;

  /// Is template repository
  final bool isTemplate;

  /// Has issues enabled
  final bool hasIssues;

  /// Has wiki enabled
  final bool hasWiki;

  /// Has GitHub Pages enabled
  final bool hasPages;

  /// Has projects enabled
  final bool hasProjects;

  /// Is this a fork
  final bool isFork;

  /// Creation date
  final DateTime createdAt;

  /// Last update date
  final DateTime updatedAt;

  /// Last push date
  final DateTime pushedAt;

  /// Repo size in KB
  final int size;

  /// Homepage URL
  final String? homepage;

  // ===========================================================================
  // CONSTRUCTOR
  // ===========================================================================

  /// Creates a [GitHubRepo] with all fields specified.
  const GitHubRepo({
    required this.id,
    required this.name,
    required this.owner,
    required this.description,
    required this.isPrivate,
    required this.defaultBranch,
    required this.stars,
    required this.lastSynced,
    this.repoId,
    this.cloneUrl,
    this.htmlUrl,
    this.sshUrl,
    this.currentBranch,
    this.hasLocalChanges = false,
    // NEW fields with defaults
    this.forks = 0,
    this.openIssues = 0,
    this.watchers = 0,
    this.language,
    this.languageColor,
    this.topics = const [],
    this.license,
    this.isTemplate = false,
    this.hasIssues = true,
    this.hasWiki = false,
    this.hasPages = false,
    this.hasProjects = true,
    this.isFork = false,
    required this.createdAt,
    required this.updatedAt,
    required this.pushedAt,
    this.size = 0,
    this.homepage,
  });

  /// Factory for creating a new GitHub repo entry with auto-generated values.
  factory GitHubRepo.create({
    required String name,
    required String owner,
    String description = '',
    bool isPrivate = false,
    String defaultBranch = 'main',
    String? cloneUrl,
    String? htmlUrl,
    String? sshUrl,
    String? repoId,
    String? language,
    String? license,
    int size = 0,
    String? homepage,
  }) {
    final now = DateTime.now();
    return GitHubRepo(
      id: const Uuid().v4(),
      name: name,
      owner: owner,
      description: description,
      isPrivate: isPrivate,
      defaultBranch: defaultBranch,
      stars: 0,
      lastSynced: now,
      repoId: repoId,
      cloneUrl: cloneUrl,
      htmlUrl: htmlUrl,
      sshUrl: sshUrl,
      language: language,
      license: license,
      createdAt: now,
      updatedAt: now,
      pushedAt: now,
      size: size,
      homepage: homepage,
    );
  }

  /// Creates a [GitHubRepo] from a GitHub API response JSON.
  factory GitHubRepo.fromGitHubApi(Map<String, dynamic> json) {
    final now = DateTime.now();

    // Parse topics from the API response
    final topicsList = <String>[];
    if (json['topics'] is List) {
      topicsList.addAll(
        (json['topics'] as List).whereType<String>(),
      );
    }

    // Extract license name if available
    final licenseData = json['license'];
    final licenseName = licenseData is Map<String, dynamic>
        ? licenseData['name'] as String?
        : null;

    // Get the language from API
    final primaryLanguage = json['language'] as String?;

    // Look up language color
    final langColor = GitHubLanguage.getColor(primaryLanguage);

    // Parse dates from API
    DateTime parseDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return now;
      try {
        return DateTime.parse(dateStr);
      } catch (_) {
        return now;
      }
    }

    return GitHubRepo(
      id: const Uuid().v4(),
      name: json['name'] as String,
      owner: (json['owner'] as Map<String, dynamic>)['login'] as String,
      description: json['description'] as String? ?? '',
      isPrivate: json['private'] as bool? ?? false,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      stars: json['stargazers_count'] as int? ?? 0,
      lastSynced: now,
      repoId: json['id']?.toString(),
      cloneUrl: json['clone_url'] as String?,
      htmlUrl: json['html_url'] as String?,
      sshUrl: json['ssh_url'] as String?,
      // NEW fields from API
      forks: json['forks_count'] as int? ?? 0,
      openIssues: json['open_issues_count'] as int? ?? 0,
      watchers: json['watchers_count'] as int? ?? 0,
      language: primaryLanguage,
      languageColor: langColor,
      topics: topicsList,
      license: licenseName,
      isTemplate: json['is_template'] as bool? ?? false,
      hasIssues: json['has_issues'] as bool? ?? true,
      hasWiki: json['has_wiki'] as bool? ?? false,
      hasPages: json['has_pages'] as bool? ?? false,
      hasProjects: json['has_projects'] as bool? ?? true,
      isFork: json['fork'] as bool? ?? false,
      createdAt: parseDate(json['created_at'] as String?),
      updatedAt: parseDate(json['updated_at'] as String?),
      pushedAt: parseDate(json['pushed_at'] as String?),
      size: json['size'] as int? ?? 0,
      homepage: json['homepage'] as String?,
    );
  }

  /// Creates a [GitHubRepo] from a locally stored JSON map.
  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return GitHubRepo(
      id: json['id'] as String,
      name: json['name'] as String,
      owner: json['owner'] as String,
      description: json['description'] as String? ?? '',
      isPrivate: json['isPrivate'] as bool? ?? false,
      defaultBranch: json['defaultBranch'] as String? ?? 'main',
      stars: json['stars'] as int? ?? 0,
      lastSynced: DateTime.parse(json['lastSynced'] as String),
      repoId: json['repoId'] as String?,
      cloneUrl: json['cloneUrl'] as String?,
      htmlUrl: json['htmlUrl'] as String?,
      sshUrl: json['sshUrl'] as String?,
      currentBranch: json['currentBranch'] as String?,
      hasLocalChanges: json['hasLocalChanges'] as bool? ?? false,
      // NEW fields
      forks: json['forks'] as int? ?? 0,
      openIssues: json['openIssues'] as int? ?? 0,
      watchers: json['watchers'] as int? ?? 0,
      language: json['language'] as String?,
      languageColor: json['languageColor'] as String? ??
          GitHubLanguage.getColor(json['language'] as String?),
      topics: ((json['topics'] as List<dynamic>?)?.whereType<String>().toList()) ??
          const [],
      license: json['license'] as String?,
      isTemplate: json['isTemplate'] as bool? ?? false,
      hasIssues: json['hasIssues'] as bool? ?? true,
      hasWiki: json['hasWiki'] as bool? ?? false,
      hasPages: json['hasPages'] as bool? ?? false,
      hasProjects: json['hasProjects'] as bool? ?? true,
      isFork: json['isFork'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : now,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : now,
      pushedAt: json['pushedAt'] != null
          ? DateTime.parse(json['pushedAt'] as String)
          : now,
      size: json['size'] as int? ?? 0,
      homepage: json['homepage'] as String?,
    );
  }

  /// Converts this repo to a JSON map for local storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner': owner,
      'description': description,
      'isPrivate': isPrivate,
      'defaultBranch': defaultBranch,
      'stars': stars,
      'lastSynced': lastSynced.toIso8601String(),
      if (repoId != null) 'repoId': repoId,
      if (cloneUrl != null) 'cloneUrl': cloneUrl,
      if (htmlUrl != null) 'htmlUrl': htmlUrl,
      if (sshUrl != null) 'sshUrl': sshUrl,
      if (currentBranch != null) 'currentBranch': currentBranch,
      'hasLocalChanges': hasLocalChanges,
      // NEW fields
      'forks': forks,
      'openIssues': openIssues,
      'watchers': watchers,
      if (language != null) 'language': language,
      if (languageColor != null) 'languageColor': languageColor,
      if (topics.isNotEmpty) 'topics': topics,
      if (license != null) 'license': license,
      'isTemplate': isTemplate,
      'hasIssues': hasIssues,
      'hasWiki': hasWiki,
      'hasPages': hasPages,
      'hasProjects': hasProjects,
      'isFork': isFork,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'pushedAt': pushedAt.toIso8601String(),
      'size': size,
      if (homepage != null) 'homepage': homepage,
    };
  }

  // ===========================================================================
  // COPY WITH
  // ===========================================================================

  /// Creates a copy with specified fields replaced.
  GitHubRepo copyWith({
    String? id,
    String? name,
    String? owner,
    String? description,
    bool? isPrivate,
    String? defaultBranch,
    int? stars,
    DateTime? lastSynced,
    String? repoId,
    String? cloneUrl,
    String? htmlUrl,
    String? sshUrl,
    String? currentBranch,
    bool? hasLocalChanges,
    // NEW fields
    int? forks,
    int? openIssues,
    int? watchers,
    String? language,
    String? languageColor,
    List<String>? topics,
    String? license,
    bool? isTemplate,
    bool? hasIssues,
    bool? hasWiki,
    bool? hasPages,
    bool? hasProjects,
    bool? isFork,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? pushedAt,
    int? size,
    String? homepage,
  }) {
    return GitHubRepo(
      id: id ?? this.id,
      name: name ?? this.name,
      owner: owner ?? this.owner,
      description: description ?? this.description,
      isPrivate: isPrivate ?? this.isPrivate,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      stars: stars ?? this.stars,
      lastSynced: lastSynced ?? this.lastSynced,
      repoId: repoId ?? this.repoId,
      cloneUrl: cloneUrl ?? this.cloneUrl,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      sshUrl: sshUrl ?? this.sshUrl,
      currentBranch: currentBranch ?? this.currentBranch,
      hasLocalChanges: hasLocalChanges ?? this.hasLocalChanges,
      forks: forks ?? this.forks,
      openIssues: openIssues ?? this.openIssues,
      watchers: watchers ?? this.watchers,
      language: language ?? this.language,
      languageColor: languageColor ?? this.languageColor,
      topics: topics ?? this.topics,
      license: license ?? this.license,
      isTemplate: isTemplate ?? this.isTemplate,
      hasIssues: hasIssues ?? this.hasIssues,
      hasWiki: hasWiki ?? this.hasWiki,
      hasPages: hasPages ?? this.hasPages,
      hasProjects: hasProjects ?? this.hasProjects,
      isFork: isFork ?? this.isFork,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pushedAt: pushedAt ?? this.pushedAt,
      size: size ?? this.size,
      homepage: homepage ?? this.homepage,
    );
  }

  // ===========================================================================
  // SYNC HELPERS
  // ===========================================================================

  /// Returns a copy with updated sync timestamp.
  GitHubRepo markSynced() => copyWith(lastSynced: DateTime.now());

  /// Returns a copy with local changes flag set.
  GitHubRepo markHasChanges() => copyWith(hasLocalChanges: true);

  /// Returns a copy with local changes flag cleared.
  GitHubRepo clearChanges() => copyWith(hasLocalChanges: false);

  // ===========================================================================
  // COMPUTED PROPERTIES
  // ===========================================================================

  /// Full repository identifier: 'owner/name'
  String get fullName => '$owner/$name';

  /// URL to view repository on GitHub web
  String get webUrl => htmlUrl ?? 'https://github.com/$fullName';

  /// Time elapsed since last sync
  Duration get timeSinceSync => DateTime.now().difference(lastSynced);

  /// Whether the repository needs syncing (synced > 5 minutes ago)
  bool get needsSync => timeSinceSync.inMinutes > 5;

  /// Formatted size string: "1.2 MB" / "450 KB" / "2.1 GB"
  String get formattedSize {
    if (size <= 0) return '0 KB';
    const kb = 1;
    const mb = 1024;
    const gb = 1024 * 1024;

    if (size >= gb) {
      return '${(size / gb).toStringAsFixed(1)} GB';
    } else if (size >= mb) {
      return '${(size / mb).toStringAsFixed(1)} MB';
    } else {
      return '$size KB';
    }
  }

  /// Activity label based on last push date
  /// Returns: "活跃" (active within 7 days),
  ///          "最近更新" (updated within 30 days),
  ///          "N个月前" (N months ago),
  ///          "N年前" (N years ago)
  String get activityLabel {
    final now = DateTime.now();
    final diff = now.difference(pushedAt);

    if (diff.inDays < 7) return '\u6d3b\u8dc3'; // 活跃
    if (diff.inDays < 30) return '\u6700\u8fd1\u66f4\u65b0'; // 最近更新
    if (diff.inDays < 365) {
      final months = diff.inDays ~/ 30;
      return '$months\u4e2a\u6708\u524d'; // N个月前
    }
    final years = diff.inDays ~/ 365;
    return '$years\u5e74\u524d'; // N年前
  }

  /// Whether the repository was pushed to within the last 30 days
  bool get isRecentlyActive {
    final diff = DateTime.now().difference(pushedAt);
    return diff.inDays <= 30;
  }

  /// Whether the repository is highly starred (> 1000 stars)
  bool get isPopular => stars >= 1000;

  /// Short description (truncated to max 100 chars)
  String get shortDescription {
    if (description.length <= 100) return description;
    return '${description.substring(0, 97)}...';
  }

  // ===========================================================================
  // EQUALITY & HASH CODE
  // ===========================================================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitHubRepo &&
        other.id == id &&
        other.name == name &&
        other.owner == owner &&
        other.description == description &&
        other.isPrivate == isPrivate &&
        other.defaultBranch == defaultBranch &&
        other.stars == stars &&
        other.lastSynced == lastSynced &&
        other.repoId == repoId &&
        other.currentBranch == currentBranch &&
        other.hasLocalChanges == hasLocalChanges &&
        // NEW fields in equality
        other.forks == forks &&
        other.openIssues == openIssues &&
        other.language == language &&
        other.isFork == isFork &&
        other.pushedAt == pushedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        owner,
        description,
        isPrivate,
        defaultBranch,
        stars,
        lastSynced,
        repoId,
        currentBranch,
        hasLocalChanges,
        // NEW fields in hashCode
        forks,
        openIssues,
        language,
        isFork,
        pushedAt,
      );

  @override
  String toString() {
    return 'GitHubRepo(id: $id, fullName: $fullName, '
        'branch: $defaultBranch, stars: $stars, language: $language, '
        'forks: $forks, issues: $openIssues)';
  }
}

// =============================================================================
// GITHUB LANGUAGE HELPER
// =============================================================================

/// Helper class for GitHub programming language metadata.
///
/// Provides a mapping of language names to their GitHub-defined
/// color hex codes, and utility methods for language lookups.
///
/// ```dart
/// final color = GitHubLanguage.getColor('Dart'); // '#00B4AB'
/// final allLangs = GitHubLanguage.allLanguages;
/// ```
class GitHubLanguage {
  GitHubLanguage._();

  /// GitHub's official language color mappings.
  ///
  /// Colors are sourced from GitHub's linguist library:
  /// https://github.com/github/linguist
  static const Map<String, String> colors = {
    'Dart': '#00B4AB',
    'Python': '#3572A5',
    'JavaScript': '#F1E05A',
    'TypeScript': '#3178C6',
    'Java': '#B07219',
    'Kotlin': '#A97BFF',
    'Swift': '#F05138',
    'Go': '#00ADD8',
    'Rust': '#DEA584',
    'C++': '#F34B7D',
    'C': '#555555',
    'HTML': '#E34C26',
    'CSS': '#563D7C',
    'Ruby': '#701516',
    'PHP': '#4F5D95',
    'Shell': '#89E051',
    'Vue': '#41B883',
    'Flutter': '#02569B',
    // Additional languages
    'Objective-C': '#438EFF',
    'Objective-C++': '#6866FB',
    'Scala': '#C22D40',
    'Haskell': '#5E5086',
    'Lua': '#000080',
    'Perl': '#0298C3',
    'R': '#198CE7',
    'MATLAB': '#E16737',
    'PowerShell': '#012456',
    'Elixir': '#6E4A7E',
    'Clojure': '#DB5855',
    'F#': '#B845FC',
    'Groovy': '#4298B8',
    'Jupyter Notebook': '#DA5B0B',
    'TeX': '#3D6117',
    'Vim Script': '#199F4B',
    'CoffeeScript': '#244776',
    'Erlang': '#B83998',
    'OCaml': '#3BE133',
    'Emacs Lisp': '#C065DB',
    'Common Lisp': '#3FB68B',
    'CMake': '#DA3434',
    'Dockerfile': '#384D54',
    'Makefile': '#427819',
    'Assembly': '#6E4C13',
    'WebAssembly': '#04133B',
    'Svelte': '#FF3E00',
    'Astro': '#FF5A03',
    'Solidity': '#AA6746',
    'Markdown': '#083FA1',
    'JSON': '#292929',
    'YAML': '#CB171E',
    'XML': '#0060AC',
    'SQL': '#E38C00',
    'GraphQL': '#E10098',
    'Sass': '#A53B70',
    'Less': '#1D365D',
    'Stylus': '#FF6347',
    'Racket': '#3C5CAA',
    'Nim': '#FFC200',
    'Crystal': '#000100',
    'D': '#BA595E',
    'FORTRAN': '#4D41B1',
    'Julia': '#A270BA',
    'PureScript': '#1D222D',
    'Elm': '#60B5CC',
    'Reason': '#FF5847',
    'Rescript': '#E6484F',
    'Zig': '#EC915C',
    'V': '#4F87C4',
    'Nix': '#7E7EFF',
    'Haxe': '#EA8220',
    'Pascal': '#E3F171',
    'PLSQL': '#DAD8D8',
    'Processing': '#0096D8',
    'Tcl': '#E4F0F4',
    'Vala': '#A56DE2',
    'Verilog': '#B2A7D9',
    'VHDL': '#ADB2CA',
    'Ada': '#02F88C',
    'COBOL': '#013C9D',
    'ABAP': '#E8274B',
    'Gherkin': '#5B2063',
    'IDL': '#A3522F',
    'Prolog': '#74283C',
    'Smalltalk': '#596706',
    'SQF': '#3F3F3F',
    'SourcePawn': '#F69E1D',
    'DOT': '#DA5B0B',
    'Hack': '#878787',
  };

  /// Get the color hex string for a programming language.
  ///
  /// Returns the GitHub-defined color for the given [language] name,
  /// or a default gray color if the language is not in the known set.
  ///
  /// ```dart
  /// final color = GitHubLanguage.getColor('Dart');
  /// // Returns: '#00B4AB'
  ///
  /// final unknown = GitHubLanguage.getColor('UnknownLang');
  /// // Returns: '#8B949E' (default gray)
  /// ```
  static String? getColor(String? language) {
    if (language == null || language.isEmpty) return null;
    return colors[language] ?? '#8B949E';
  }

  /// Get a list of all known programming languages.
  ///
  /// Returns an alphabetically sorted list of all language names
  /// that have associated color mappings.
  static List<String> get allLanguages {
    final langs = colors.keys.toList();
    langs.sort();
    return langs;
  }

  /// Check if a language is in the known set.
  static bool isKnown(String language) => colors.containsKey(language);

  /// Get the total number of known languages.
  static int get languageCount => colors.length;
}
