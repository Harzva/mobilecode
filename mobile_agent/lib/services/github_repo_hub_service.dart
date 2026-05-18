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
  });

  final String path;
  final bool exists;
  final bool hasGit;
  final bool remoteLinked;

  String get statusLabel {
    if (hasGit) return 'Git on phone';
    if (remoteLinked) return 'Remote-linked';
    if (exists) return 'Local folder';
    return 'Not on phone';
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

class GitHubRepoHubService {
  GitHubRepoHubService(this.github);

  static const _watchlistKey = 'mobilecode.github.repoWatchlist.v1';
  static const _artifactDownloadsKey = 'mobilecode.github.artifactDownloads.v1';
  static const _markerName = '.mobilecode-remote.json';

  final GitHubDeepService github;

  static String repoKey(GitHubRepo repo) => '${repo.owner}/${repo.name}';

  Future<void> initialize() => github.initialize();

  bool get isAuthenticated => github.isAuthenticated;

  String? get currentUser => github.currentUser;

  Future<List<GitHubRepoHubItem>> loadHubItems({
    String? owner,
    String sort = 'pushed',
  }) async {
    await initialize();
    final normalizedOwner = owner?.trim();
    final watchlist = await loadWatchlist();
    final repos = normalizedOwner == null || normalizedOwner.isEmpty || normalizedOwner == currentUser
        ? await github.getRepos(sort: sort)
        : await github.getUserRepos(normalizedOwner, sort: sort);
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

  Future<Set<String>> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_watchlistKey) ?? const <String>[];
    return raw.where((item) => item.trim().isNotEmpty).toSet();
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
    final workflows = await github.getWorkflows(repo.owner, repo.name);
    final runs = await github.getWorkflowRuns(repo.owner, repo.name, perPage: 5);
    var artifacts = const <dynamic>[];
    var jobs = const <dynamic>[];
    final latestRun = runs.isEmpty ? null : runs.first;
    if (latestRun is Map<String, dynamic>) {
      final id = latestRun['id'];
      if (id is int) {
        artifacts = await github.getWorkflowRunArtifacts(repo.owner, repo.name, id);
        jobs = await github.getWorkflowRunJobs(repo.owner, repo.name, id);
      }
    }
    return GitHubActionsSnapshot(
      workflows: workflows,
      runs: runs,
      artifacts: artifacts,
      jobs: jobs,
    );
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

  Future<List<GitHubWorkspaceEntry>> loadRemoteTree(GitHubRepo repo, {String path = ''}) async {
    final items = await github.getContents(
      repo.owner,
      repo.name,
      path: path.isEmpty ? null : path,
      ref: repo.defaultBranch,
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
    final items = await github.getContents(repo.owner, repo.name, path: path, ref: repo.defaultBranch);
    final metadata = items.isNotEmpty && items.first is Map<String, dynamic> ? items.first as Map<String, dynamic> : null;
    final content = await github.getFileContent(repo.owner, repo.name, path, ref: repo.defaultBranch);
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
