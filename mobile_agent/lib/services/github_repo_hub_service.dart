import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/github_repo.dart';
import 'github_deep_service.dart';

const mobileCodeProjectsFolderName = 'mobilecode_projects';
const githubWorkspaceFolderName = 'github';

class GitHubRepoLocalState {
  const GitHubRepoLocalState({
    required this.path,
    required this.exists,
    required this.hasGit,
    required this.remoteLinked,
    this.runtimeGit = false,
  });

  final String path;
  final bool exists;
  final bool hasGit;
  final bool remoteLinked;
  final bool runtimeGit;

  String get statusLabel {
    if (runtimeGit) return 'Termux git clone';
    if (hasGit) return 'Git clone';
    if (remoteLinked) return 'Remote-linked';
    if (exists) return 'Phone folder';
    return 'Not on phone';
  }

  String get modeDescription {
    if (runtimeGit) return 'Real git clone inside the active runtime workspace.';
    if (hasGit) return 'Real git clone with a .git folder on this phone.';
    if (remoteLinked) return 'GitHub API workspace marker; files are remote-linked, not cloned.';
    if (exists) return 'Phone folder exists, but it is not linked to GitHub yet.';
    return 'No phone workspace has been created for this repo yet.';
  }
}

class GitHubRemoteWorkspaceLink {
  const GitHubRemoteWorkspaceLink({
    required this.owner,
    required this.name,
    required this.workspacePath,
    this.htmlUrl,
    this.defaultBranch = 'main',
  });

  final String owner;
  final String name;
  final String workspacePath;
  final String? htmlUrl;
  final String defaultBranch;

  String get fullName => '$owner/$name';
}

class GitHubRepoCloneTarget {
  const GitHubRepoCloneTarget({
    required this.finalPath,
    required this.clonePath,
    required this.usesTemporaryPath,
  });

  final String finalPath;
  final String clonePath;
  final bool usesTemporaryPath;
}

class GitHubRepoHubItem {
  const GitHubRepoHubItem({
    required this.repo,
    required this.localState,
    required this.watched,
  });

  final GitHubRepo repo;
  final GitHubRepoLocalState localState;
  final bool watched;

  String get key => GitHubRepoHubService.repoKey(repo);
}

class GitHubActionsSnapshot {
  const GitHubActionsSnapshot({
    required this.workflows,
    required this.runs,
    required this.artifacts,
    required this.jobs,
  });

  final List<dynamic> workflows;
  final List<dynamic> runs;
  final List<dynamic> artifacts;
  final List<dynamic> jobs;

  Map<String, dynamic>? get latestRun {
    final first = runs.isEmpty ? null : runs.first;
    return first is Map<String, dynamic> ? first : null;
  }
}

class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.contentType,
    this.sizeBytes,
    this.downloadCount,
  });

  final String name;
  final String downloadUrl;
  final String? contentType;
  final int? sizeBytes;
  final int? downloadCount;

  bool get isBuildArtifact {
    final lower = name.toLowerCase();
    return lower.endsWith('.apk') ||
        lower.endsWith('.aab') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.ipa') ||
        lower.endsWith('.tar.gz');
  }

  factory GitHubReleaseAsset.fromJson(Map<String, dynamic> json) {
    return GitHubReleaseAsset(
      name: json['name']?.toString() ?? 'asset',
      downloadUrl: json['browser_download_url']?.toString() ?? '',
      contentType: json['content_type']?.toString(),
      sizeBytes: json['size'] is int ? json['size'] as int : null,
      downloadCount: json['download_count'] is int ? json['download_count'] as int : null,
    );
  }
}

class GitHubReleaseSummary {
  const GitHubReleaseSummary({
    required this.tagName,
    required this.title,
    required this.releaseUrl,
    required this.publishedAt,
    required this.assets,
    required this.prerelease,
    required this.draft,
  });

  final String tagName;
  final String title;
  final String releaseUrl;
  final DateTime? publishedAt;
  final List<GitHubReleaseAsset> assets;
  final bool prerelease;
  final bool draft;

  List<GitHubReleaseAsset> get buildAssets =>
      assets.where((asset) => asset.isBuildArtifact && asset.downloadUrl.isNotEmpty).toList();

  bool get hasBuildAssets => buildAssets.isNotEmpty;

  factory GitHubReleaseSummary.fromJson(Map<String, dynamic> json) {
    final rawAssets = (json['assets'] as List<dynamic>?) ?? const [];
    final rawTitle = json['name']?.toString().trim();
    final rawTag = json['tag_name']?.toString() ?? 'untagged';
    return GitHubReleaseSummary(
      tagName: rawTag,
      title: rawTitle != null && rawTitle.isNotEmpty ? rawTitle : rawTag,
      releaseUrl: json['html_url']?.toString() ?? '',
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      assets: rawAssets
          .whereType<Map<String, dynamic>>()
          .map(GitHubReleaseAsset.fromJson)
          .where((asset) => asset.name.isNotEmpty)
          .toList(),
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
    );
  }
}

class GitHubWorkspaceEntry {
  const GitHubWorkspaceEntry({
    required this.name,
    required this.path,
    required this.type,
    this.sha,
    this.size,
    this.downloadUrl,
  });

  final String name;
  final String path;
  final String type;
  final String? sha;
  final int? size;
  final String? downloadUrl;

  bool get isDirectory => type == 'dir';

  bool get isFile => type == 'file';

  factory GitHubWorkspaceEntry.fromJson(Map<String, dynamic> json) {
    return GitHubWorkspaceEntry(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      type: json['type']?.toString() ?? 'file',
      sha: json['sha']?.toString(),
      size: json['size'] is int ? json['size'] as int : null,
      downloadUrl: json['download_url']?.toString(),
    );
  }
}

class GitHubRemoteFile {
  const GitHubRemoteFile({
    required this.path,
    required this.content,
    this.sha,
  });

  final String path;
  final String content;
  final String? sha;
}

class GitHubArtifactDownloadRecord {
  const GitHubArtifactDownloadRecord({
    required this.repoFullName,
    required this.artifactName,
    required this.path,
    required this.downloadedAt,
    this.sizeBytes,
  });

  final String repoFullName;
  final String artifactName;
  final String path;
  final DateTime downloadedAt;
  final int? sizeBytes;

  Map<String, dynamic> toJson() => {
        'repoFullName': repoFullName,
        'artifactName': artifactName,
        'path': path,
        'downloadedAt': downloadedAt.toIso8601String(),
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
      };

  factory GitHubArtifactDownloadRecord.fromJson(Map<String, dynamic> json) {
    return GitHubArtifactDownloadRecord(
      repoFullName: json['repoFullName']?.toString() ?? '',
      artifactName: json['artifactName']?.toString() ?? 'artifact',
      path: json['path']?.toString() ?? '',
      downloadedAt: DateTime.tryParse(json['downloadedAt']?.toString() ?? '') ?? DateTime.now(),
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : null,
    );
  }
}

class GitHubRuntimeWorkspaceSyncRecord {
  const GitHubRuntimeWorkspaceSyncRecord({
    required this.repoFullName,
    required this.runtimePath,
    required this.sharedPath,
    required this.syncedAt,
  });

  final String repoFullName;
  final String runtimePath;
  final String sharedPath;
  final DateTime syncedAt;

  Map<String, dynamic> toJson() => {
        'repoFullName': repoFullName,
        'runtimePath': runtimePath,
        'sharedPath': sharedPath,
        'syncedAt': syncedAt.toIso8601String(),
      };

  factory GitHubRuntimeWorkspaceSyncRecord.fromJson(Map<String, dynamic> json) {
    return GitHubRuntimeWorkspaceSyncRecord(
      repoFullName: json['repoFullName']?.toString() ?? '',
      runtimePath: json['runtimePath']?.toString() ?? '',
      sharedPath: json['sharedPath']?.toString() ?? '',
      syncedAt: DateTime.tryParse(json['syncedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class GitHubRepoHubService {
  GitHubRepoHubService(this.github);

  static const _watchlistKey = 'mobilecode.github.repoWatchlist.v1';
  static const _artifactDownloadsKey = 'mobilecode.github.artifactDownloads.v1';
  static const _runtimeWorkspaceSyncsKey = 'mobilecode.github.runtimeWorkspaceSyncs.v1';
  static const _markerName = '.mobilecode-remote.json';

  final GitHubDeepService github;

  static String repoKey(GitHubRepo repo) => '${repo.owner}/${repo.name}';

  Future<void> initialize() => github.initialize();

  bool get isAuthenticated => github.isAuthenticated;

  String? get currentUser => github.currentUser;

  List<String> get accountList => github.accountList;

  Future<bool> switchAccount(String username) => github.switchAccount(username);

  DateTime? authenticatedAtFor(String username) => github.authenticatedAtFor(username);

  String? avatarUrlFor(String username) => github.avatarUrlFor(username);

  Future<List<String>> loadTokenScopes({String? username}) => github.getTokenScopes(username: username);

  Future<List<GitHubRepoHubItem>> loadHubItems({
    String? owner,
    String sort = 'pushed',
  }) async {
    await initialize();
    final normalizedOwner = owner?.trim();
    final watchlist = await loadWatchlist();
    final repos = normalizedOwner == null || normalizedOwner.isEmpty || normalizedOwner == currentUser
        ? await github.getRepos(sort: sort)
        : await github.getUserRepos(normalizedOwner, sort: sort, public: true);
    final items = <GitHubRepoHubItem>[];
    for (final repo in repos) {
      items.add(GitHubRepoHubItem(
        repo: repo,
        localState: await localStateFor(repo),
        watched: watchlist.contains(repoKey(repo)),
      ));
    }
    return items;
  }

  Future<List<GitHubRepoHubItem>> searchHubItems({
    required String query,
    required String source,
    String sort = 'updated',
  }) async {
    await initialize();
    final trimmed = query.trim();
    final effectiveQuery = _searchQueryForSource(trimmed, source);
    final watchlist = await loadWatchlist();
    final rawRepos = await github.searchRepositories(
      effectiveQuery,
      sort: _searchSort(sort),
      perPage: 50,
      public: true,
    );
    final items = <GitHubRepoHubItem>[];
    final seen = <String>{};
    for (final raw in rawRepos) {
      if (raw is! Map<String, dynamic>) continue;
      final repo = GitHubRepo.fromGitHubApi(raw);
      if (!seen.add(repoKey(repo))) continue;
      items.add(GitHubRepoHubItem(
        repo: repo,
        localState: await localStateFor(repo),
        watched: watchlist.contains(repoKey(repo)),
      ));
    }
    return items;
  }

  Future<Set<String>> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_watchlistKey) ?? const <String>[];
    return raw.where((item) => item.trim().isNotEmpty).toSet();
  }

  String _searchQueryForSource(String query, String source) {
    final userQuery = query.isEmpty ? '' : '$query ';
    return switch (source) {
      'skill' => '${userQuery}(SKILL.md OR "agent skill" OR "codex skill" OR "claude skill") in:readme,description archived:false',
      'mcp' => '${userQuery}("mcp server" OR "model context protocol") in:name,description,readme archived:false',
      'release' => '${userQuery}(release OR apk OR android OR flutter) in:name,description,readme archived:false',
      _ => '${query.isEmpty ? 'stars:>10' : query} archived:false',
    };
  }

  String _searchSort(String sort) {
    if (sort == 'pushed' || sort == 'updated' || sort == 'created') return 'updated';
    if (sort == 'full_name') return '';
    return sort;
  }

  Future<bool> setWatched(GitHubRepo repo, bool watched) async {
    final prefs = await SharedPreferences.getInstance();
    final values = await loadWatchlist();
    final key = repoKey(repo);
    if (watched) {
      values.add(key);
    } else {
      values.remove(key);
    }
    await prefs.setStringList(_watchlistKey, values.toList()..sort());
    return watched;
  }

  Future<Directory> workspaceRoot() async {
    final directory = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(directory.path, mobileCodeProjectsFolderName, githubWorkspaceFolderName));
    await root.create(recursive: true);
    return root;
  }

  Future<String> workspacePathFor(GitHubRepo repo) async {
    final root = await workspaceRoot();
    return p.join(root.path, _safeSegment(repo.owner), _safeSegment(repo.name));
  }

  Future<GitHubRepoLocalState> localStateFor(GitHubRepo repo) async {
    final path = await workspacePathFor(repo);
    final directory = Directory(path);
    final exists = await directory.exists();
    final hasGit = await Directory(p.join(path, '.git')).exists();
    final marker = await File(p.join(path, _markerName)).exists();
    if (marker && !hasGit) {
      try {
        final decoded = jsonDecode(await File(p.join(path, _markerName)).readAsString());
        if (decoded is Map<String, dynamic> && decoded['mode'] == 'termux_git_workspace') {
          final runtimePath = decoded['runtimePath']?.toString().trim();
          if (runtimePath != null && runtimePath.isNotEmpty) {
            return GitHubRepoLocalState(
              path: runtimePath,
              exists: true,
              hasGit: true,
              remoteLinked: false,
              runtimeGit: true,
            );
          }
        }
      } catch (_) {
        // Fall back to the normal marker state below.
      }
    }
    return GitHubRepoLocalState(
      path: path,
      exists: exists,
      hasGit: hasGit,
      remoteLinked: marker && !hasGit,
    );
  }

  Future<GitHubRepoLocalState> ensureRemoteLinkedWorkspace(GitHubRepo repo) async {
    final path = await workspacePathFor(repo);
    final directory = Directory(path);
    await directory.create(recursive: true);
    final marker = File(p.join(path, _markerName));
    await marker.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'mode': 'github_api_workspace',
        'repo': repoKey(repo),
        'owner': repo.owner,
        'name': repo.name,
        'htmlUrl': repo.htmlUrl,
        'defaultBranch': repo.defaultBranch,
        'createdAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    return localStateFor(repo);
  }

  Future<GitHubRepoCloneTarget> prepareCloneTarget(GitHubRepo repo) async {
    final path = await workspacePathFor(repo);
    final directory = Directory(path);
    final parent = Directory(p.dirname(path));
    await parent.create(recursive: true);

    if (!await directory.exists()) {
      return GitHubRepoCloneTarget(
        finalPath: path,
        clonePath: await _uniqueCloneTempPath(path),
        usesTemporaryPath: true,
      );
    }
    if (await Directory(p.join(path, '.git')).exists()) {
      return GitHubRepoCloneTarget(
        finalPath: path,
        clonePath: path,
        usesTemporaryPath: false,
      );
    }

    final entities = await directory.list(followLinks: false).toList();
    final blockingEntries = entities
        .where((entity) => p.basename(entity.path) != _markerName)
        .toList();
    if (blockingEntries.isNotEmpty) {
      throw StateError(
        'Phone workspace already contains files but no .git folder. '
        'Move or remove that folder before cloning.',
      );
    }

    return GitHubRepoCloneTarget(
      finalPath: path,
      clonePath: await _uniqueCloneTempPath(path),
      usesTemporaryPath: true,
    );
  }

  String runtimeClonePathFor(GitHubRepo repo, String runtimeWorkspaceRoot) {
    final root = runtimeWorkspaceRoot.trim().isEmpty
        ? '~/mobilecode_projects'
        : runtimeWorkspaceRoot.trim();
    return p.posix.join(
      root,
      githubWorkspaceFolderName,
      _safeSegment(repo.owner),
      _safeSegment(repo.name),
    );
  }

  Future<GitHubRepoLocalState> ensureRuntimeGitWorkspace(
    GitHubRepo repo, {
    required String runtimePath,
  }) async {
    final markerPath = await workspacePathFor(repo);
    final directory = Directory(markerPath);
    await directory.create(recursive: true);
    final marker = File(p.join(markerPath, _markerName));
    await marker.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'mode': 'termux_git_workspace',
        'repo': repoKey(repo),
        'owner': repo.owner,
        'name': repo.name,
        'htmlUrl': repo.htmlUrl,
        'defaultBranch': repo.defaultBranch,
        'runtimePath': runtimePath,
        'createdAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    return localStateFor(repo);
  }

  Future<GitHubRepoLocalState> completeCloneTarget(
    GitHubRepo repo,
    GitHubRepoCloneTarget target,
  ) async {
    if (target.usesTemporaryPath) {
      final finalDirectory = Directory(target.finalPath);
      if (await finalDirectory.exists()) {
        final marker = File(p.join(target.finalPath, _markerName));
        if (await marker.exists()) {
          await marker.delete();
        }
        await finalDirectory.delete();
      }
      await Directory(target.clonePath).rename(target.finalPath);
    }
    return localStateFor(repo);
  }

  Future<void> cleanupCloneTarget(GitHubRepoCloneTarget target) async {
    if (!target.usesTemporaryPath) return;
    final directory = Directory(target.clonePath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String> _uniqueCloneTempPath(String finalPath) async {
    for (var attempt = 0; attempt < 10; attempt += 1) {
      final suffix = '${DateTime.now().millisecondsSinceEpoch}-$attempt';
      final candidate = '$finalPath.clone-tmp-$suffix';
      if (!await Directory(candidate).exists() &&
          !await File(candidate).exists()) {
        return candidate;
      }
    }
    throw StateError('Could not allocate a temporary clone path.');
  }

  static Future<GitHubRemoteWorkspaceLink?> findRemoteLinkForPath(String path) async {
    var current = FileSystemEntity.isDirectorySync(path) ? Directory(path) : Directory(p.dirname(path));
    for (var depth = 0; depth < 16; depth += 1) {
      final marker = File(p.join(current.path, _markerName));
      if (await marker.exists()) {
        try {
          final data = jsonDecode(await marker.readAsString());
          if (data is Map<String, dynamic>) {
            final owner = data['owner']?.toString();
            final name = data['name']?.toString();
            if (owner != null && owner.isNotEmpty && name != null && name.isNotEmpty) {
              return GitHubRemoteWorkspaceLink(
                owner: owner,
                name: name,
                workspacePath: current.path,
                htmlUrl: data['htmlUrl']?.toString(),
                defaultBranch: data['defaultBranch']?.toString() ?? 'main',
              );
            }
          }
        } on Object {
          return null;
        }
      }

      final parentPath = p.dirname(current.path);
      if (parentPath == current.path) break;
      current = Directory(parentPath);
    }
    return null;
  }

  Future<GitHubActionsSnapshot> loadActionsSnapshot(GitHubRepo repo) async {
    final usePublicRead = !repo.isPrivate;
    final workflows = await github.getWorkflows(repo.owner, repo.name, public: usePublicRead);
    final runs = await github.getWorkflowRuns(repo.owner, repo.name, perPage: 5, public: usePublicRead);
    var artifacts = const <dynamic>[];
    var jobs = const <dynamic>[];
    final latestRun = runs.isEmpty ? null : runs.first;
    if (latestRun is Map<String, dynamic>) {
      final id = latestRun['id'];
      if (id is int) {
        artifacts = await github.getWorkflowRunArtifacts(repo.owner, repo.name, id, public: usePublicRead);
        jobs = await github.getWorkflowRunJobs(repo.owner, repo.name, id, public: usePublicRead);
      }
    }
    return GitHubActionsSnapshot(
      workflows: workflows,
      runs: runs,
      artifacts: artifacts,
      jobs: jobs,
    );
  }

  Future<List<GitHubReleaseSummary>> loadReleaseSummaries(GitHubRepo repo) async {
    final releases = await github.getReleases(repo.owner, repo.name, public: !repo.isPrivate);
    return releases
        .whereType<Map<String, dynamic>>()
        .map(GitHubReleaseSummary.fromJson)
        .where((release) => release.tagName.isNotEmpty || release.releaseUrl.isNotEmpty)
        .toList();
  }

  Future<GitHubReleaseSummary?> loadLatestReleaseSummary(GitHubRepo repo) async {
    final releases = await loadReleaseSummaries(repo);
    if (releases.isEmpty) return null;
    return releases.first;
  }

  Future<void> dispatchWorkflow(GitHubRepo repo, String workflowId) {
    return github.dispatchWorkflow(
      repo.owner,
      repo.name,
      workflowId,
      ref: repo.defaultBranch,
    );
  }

  Future<String> downloadArtifactZip(GitHubRepo repo, Map<String, dynamic> artifact) async {
    final id = artifact['id'];
    if (id is! int) {
      throw const GitHubDeepException(message: 'Artifact id is missing.');
    }
    final bytes = await github.downloadWorkflowArtifactZip(repo.owner, repo.name, id);
    final root = await workspaceRoot();
    final artifactDir = Directory(p.join(root.path, '_actions_artifacts', _safeSegment(repo.owner), _safeSegment(repo.name)));
    await artifactDir.create(recursive: true);
    final rawName = artifact['name']?.toString() ?? 'artifact-$id';
    final file = File(p.join(artifactDir.path, '${_safeSegment(rawName)}.zip'));
    await file.writeAsBytes(bytes, flush: true);
    await _recordArtifactDownload(repo, artifact, file.path);
    return file.path;
  }

  Future<List<GitHubArtifactDownloadRecord>> loadArtifactDownloads({GitHubRepo? repo}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_artifactDownloadsKey) ?? const <String>[];
    final records = <GitHubArtifactDownloadRecord>[];
    for (final item in raw) {
      try {
        final data = jsonDecode(item);
        if (data is Map<String, dynamic>) {
          final record = GitHubArtifactDownloadRecord.fromJson(data);
          if (record.path.isEmpty) continue;
          if (repo != null && record.repoFullName != repoKey(repo)) continue;
          records.add(record);
        }
      } on Object {
        continue;
      }
    }
    records.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return records;
  }

  Future<void> _recordArtifactDownload(GitHubRepo repo, Map<String, dynamic> artifact, String path) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await loadArtifactDownloads();
    final next = [
      GitHubArtifactDownloadRecord(
        repoFullName: repoKey(repo),
        artifactName: artifact['name']?.toString() ?? 'artifact',
        path: path,
        downloadedAt: DateTime.now(),
        sizeBytes: artifact['size_in_bytes'] is int ? artifact['size_in_bytes'] as int : null,
      ),
      ...records.where((record) => record.path != path),
    ].take(24).map((record) => jsonEncode(record.toJson())).toList();
    await prefs.setStringList(_artifactDownloadsKey, next);
  }

  Future<List<GitHubRuntimeWorkspaceSyncRecord>> loadRuntimeWorkspaceSyncs({GitHubRepo? repo}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_runtimeWorkspaceSyncsKey) ?? const <String>[];
    final records = <GitHubRuntimeWorkspaceSyncRecord>[];
    for (final item in raw) {
      try {
        final data = jsonDecode(item);
        if (data is Map<String, dynamic>) {
          final record = GitHubRuntimeWorkspaceSyncRecord.fromJson(data);
          if (record.sharedPath.isEmpty) continue;
          if (repo != null && record.repoFullName != repoKey(repo)) continue;
          records.add(record);
        }
      } on Object {
        continue;
      }
    }
    records.sort((a, b) => b.syncedAt.compareTo(a.syncedAt));
    return records;
  }

  Future<void> recordRuntimeWorkspaceSync(
    GitHubRepo repo, {
    required String runtimePath,
    required String sharedPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await loadRuntimeWorkspaceSyncs();
    final next = [
      GitHubRuntimeWorkspaceSyncRecord(
        repoFullName: repoKey(repo),
        runtimePath: runtimePath,
        sharedPath: sharedPath,
        syncedAt: DateTime.now(),
      ),
      ...records.where((record) => record.sharedPath != sharedPath),
    ].take(24).map((record) => jsonEncode(record.toJson())).toList();
    await prefs.setStringList(_runtimeWorkspaceSyncsKey, next);
  }

  Future<List<GitHubWorkspaceEntry>> loadRemoteTree(GitHubRepo repo, {String path = ''}) async {
    final usePublicRead = !repo.isPrivate;
    final items = await github.getContents(
      repo.owner,
      repo.name,
      path: path.isEmpty ? null : path,
      ref: repo.defaultBranch,
      public: usePublicRead,
    );
    return items
        .whereType<Map<String, dynamic>>()
        .map(GitHubWorkspaceEntry.fromJson)
        .where((entry) => entry.name.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<GitHubRemoteFile> readRemoteFile(GitHubRepo repo, String path) async {
    final usePublicRead = !repo.isPrivate;
    final items = await github.getContents(repo.owner, repo.name, path: path, ref: repo.defaultBranch, public: usePublicRead);
    final metadata = items.isNotEmpty && items.first is Map<String, dynamic> ? items.first as Map<String, dynamic> : null;
    final content = await github.getFileContent(repo.owner, repo.name, path, ref: repo.defaultBranch, public: usePublicRead);
    return GitHubRemoteFile(
      path: path,
      content: content,
      sha: metadata?['sha']?.toString(),
    );
  }

  Future<void> commitRemoteFile(
    GitHubRepo repo, {
    required String path,
    required String content,
    required String message,
    String? sha,
  }) async {
    await github.createOrUpdateFile(
      repo.owner,
      repo.name,
      path,
      content,
      message,
      branch: repo.defaultBranch,
      sha: sha,
    );
  }

  static String _safeSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'repo' : cleaned;
  }
}
